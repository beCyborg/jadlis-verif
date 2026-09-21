#!/usr/bin/env bash
# verif_stats.sh — Сводка по журналу запусков `_runs.jsonl`.
#
# Usage:
#   verif_stats.sh [<runs.jsonl>] [--since YYYY-MM-DD] [--fresh]
#
# По умолчанию читает `<vault>/AI/verif/_runs.jsonl`, если путь не передан и задан VAULT_PATH,
# иначе требует путь аргументом. `--fresh` отбрасывает строки `backfilled: true` — обратная
# заливка даёт базовую линию, но времени интервью и решений в ней нет, и средние она портит.
#
# Считает только то, на что есть что ответить: метрика, по движению которой ничего не сделаешь,
# в сводку не попадает. Поля, которых в строке нет (`null`), из знаменателя исключаются —
# «не измеряли» и «ноль» здесь разные вещи.
set -euo pipefail

RUNS=""
SINCE=""
FRESH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since) SINCE="$2"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    -h|--help) echo "Usage: $0 [<runs.jsonl>] [--since YYYY-MM-DD] [--fresh]" >&2; exit 0 ;;
    *) RUNS="$1"; shift ;;
  esac
done

if [[ -z "$RUNS" ]]; then
  if [[ -n "${VAULT_PATH:-}" ]]; then
    RUNS="$VAULT_PATH/AI/verif/_runs.jsonl"
  else
    echo "Usage: $0 <runs.jsonl> [--since YYYY-MM-DD] [--fresh]" >&2
    exit 64
  fi
fi

[[ -s "$RUNS" ]] || { echo "Журнал пуст или не найден: $RUNS" >&2; exit 66; }

jq -r -s --arg since "$SINCE" --argjson fresh "$FRESH" '
  def pct($a; $b): if $b == 0 then "—" else (((($a / $b) * 1000) | round) / 10 | tostring) + " %" end;
  def num($x): if $x == null then "—" else ($x | tostring) end;
  def sum_of(f): [.[] | f | select(. != null)] | add // 0;
  def count_of(f): [.[] | f | select(. != null)] | length;

  map(select($since == "" or (.date // "") >= $since))
  | map(select($fresh == 0 or (.backfilled != true)))
  | . as $runs
  | ($runs | length) as $n
  | if $n == 0 then "Нечего считать: под фильтр не попала ни одна строка." else

  ([$runs[] | (.raised // {}) | keys[]] | unique) as $labels
  | (sum_of(.accepted)) as $acc
  | (sum_of(.rejected)) as $rej
  | ([$runs[] | select(.coverage != null)] | length) as $cov_known
  | ([$runs[] | select(.coverage == "partial")] | length) as $cov_partial
  | (sum_of(.arbiter_overruled)) as $ovr
  | (sum_of(.arbiter_judged)) as $judged
  | ([$runs[] | select(.fix_rounds != null and .fix_rounds >= 1)] | length) as $fixed
  | ([$runs[] | select(.fix_rounds != null and .fix_rounds >= 1 and (.fix_regressions // 0) > 0)] | length) as $fixreg
  | ([$runs[] | select(.interview_min != null and (.findings // 0) > 0)]) as $timed
  | ([$runs[] | select(.spot_check.asked == true)]) as $spot
  | ([$spot[] | select(.spot_check.agreed == false)] | length) as $spot_dis
  | (sum_of(.duplicates)) as $dups
  | ([$runs[] | .raised | select(. != null) | ([.[]] | add)] | add // 0) as $raised_total

  | [
      "Запусков в выборке: \($n)  (восстановлено задним числом: \([$runs[] | select(.backfilled == true)] | length))",
      "Принято находок: \($acc) из \($acc + $rej) решённых — \(pct($acc; $acc + $rej))",
      "",
      "Точность по проверяющему (принято / подано):"
    ]
    + ($labels | map(. as $l
        | ([$runs[] | .raised[$l] // null | select(. != null)] | add // 0) as $raised
        | ([$runs[] | (.accepted_by[$l] // null) | select(. != null)] | add // 0) as $ok
        | "  \($l): \($ok) / \($raised) — \(pct($ok; $raised))"
          + "   уникальных принятых: \([$runs[] | (.unique_accepted[$l] // null) | select(. != null)] | add // 0)"))
    + [
      "",
      "Дубликаты (доля согласия веток): \($dups) из \($raised_total) поданных — \(pct($dups; $raised_total))",
      "Частичное покрытие: \($cov_partial) из \($cov_known) — \(pct($cov_partial; $cov_known))",
      "Арбитра перевернули: \($ovr) из \($judged) рассуженных находок — \(pct($ovr; $judged))",
      "Выборочная проверка: задана \($spot | length) раз, разошлась с авто-решением \($spot_dis)",
      "",
      "Минут интервью на находку: " + (if ($timed | length) == 0 then "— (нет замеров времени)"
        else ((((([$timed[] | .interview_min] | add) / ([$timed[] | .findings] | add)) * 10) | round) / 10 | tostring)
             + "   (запусков: \($timed | length))" end),
      "Правки с регрессией: " + (if $fixed == 0 then "— (перепроверка ещё ни разу не гоняла круг доправок)"
        else "\($fixreg) из \($fixed) — \(pct($fixreg; $fixed))" end),
      "Перепроверял правки: " + ([$runs[] | .delta_by | select(. != null)] | group_by(.)
        | map("\(.[0]) ×\(length)") | if length == 0 then "—" else join(", ") end),
      "",
      "Вердикты: " + ([$runs[] | .status // .verdict | select(. != null)] | group_by(.)
        | map("\(.[0]) ×\(length)") | if length == 0 then "—" else join(", ") end)
    ]
  | join("\n")
  end
' "$RUNS"
