#!/usr/bin/env bash
# log_run.sh — Собрать одну строку журнала запуска и дописать её в <vault>/AI/verif/_runs.jsonl.
#
# Usage:
#   log_run.sh --persist-dir <dir> --base <BASE> [опции]
#
# Всё, что можно вывести из артефактов прогона (merged / findings / arbiter / decisions / delta),
# выводится здесь детерминированно — модель журнал не пишет и цифры в него не диктует. Флагами
# передаётся только то, чего в артефактах нет: путь цели, тип, пины моделей, режим интервью,
# кто перепроверял правки и сколько было кругов доправок.
#
# Опции:
#   --persist-dir <dir>   каталог артефактов (обычно <vault>/AI/verif)         [обязательно]
#   --base <BASE>         префикс имён артефактов, например 2026-09-21--plan   [обязательно]
#   --target <path>       абсолютный путь проверенного файла (для sha256)
#   --type plan|research|doc
#   --models '<json>'     {"codex":…,"fable":…,"effort_codex":…,"effort_fable":…}
#   --mode auto|manual    режим интервью
#   --delta-by <who>      codex | fable | none | skipped
#   --fix-rounds <n>      сколько кругов доправок отработала Фаза C (0, 1 или 2)
#   --times <file>        файл меток времени (по умолчанию <persist-dir>/<BASE>--run.times)
#   --out <file>          куда дописывать (по умолчанию <persist-dir>/_runs.jsonl)
#   --backfilled          пометить строку как восстановленную задним числом
#   --keep-times          не удалять файл меток после успешной записи
#
# Файл меток времени — строки вида `ключ=<epoch>`; пишутся прелюдией и границами интервью:
#   prelude=…  machine_done=…  interview_start=…  interview_done=…
#
# Чего нет — то `null`, а не ноль: «не измеряли» и «ноль» в журнале разные вещи.
set -euo pipefail

PERSIST_DIR=""
BASE=""
TARGET=""
TYPE=""
MODELS="null"
MODE="null"
DELTA_BY="null"
FIX_ROUNDS="null"
TIMES_FILE=""
OUT=""
BACKFILLED="false"
KEEP_TIMES=0

usage() {
  echo "Usage: $0 --persist-dir <dir> --base <BASE> [--target <path>] [--type <t>] [--models <json>] [--mode auto|manual] [--delta-by <who>] [--fix-rounds <n>] [--times <file>] [--out <file>] [--backfilled] [--keep-times]" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persist-dir) PERSIST_DIR="$2"; shift 2 ;;
    --base)        BASE="$2";        shift 2 ;;
    --target)      TARGET="$2";      shift 2 ;;
    --type)        TYPE="$2";        shift 2 ;;
    --models)      MODELS="$2";      shift 2 ;;
    --mode)        MODE="$(printf '%s' "$2" | jq -R .)"; shift 2 ;;
    --delta-by)    DELTA_BY="$(printf '%s' "$2" | jq -R .)"; shift 2 ;;
    --fix-rounds)  FIX_ROUNDS="$2";  shift 2 ;;
    --times)       TIMES_FILE="$2";  shift 2 ;;
    --out)         OUT="$2";         shift 2 ;;
    --backfilled)  BACKFILLED="true"; shift ;;
    --keep-times)  KEEP_TIMES=1;     shift ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$PERSIST_DIR" && -n "$BASE" ]] || usage
[[ -d "$PERSIST_DIR" ]] || { echo "No such directory: $PERSIST_DIR" >&2; exit 66; }

: "${OUT:=$PERSIST_DIR/_runs.jsonl}"
: "${TIMES_FILE:=$PERSIST_DIR/${BASE}--run.times}"

# Артефакт читаем, только если он валидный JSON; иначе null — строка всё равно пишется.
read_json() {
  local f="$1"
  if [[ -s "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then cat "$f"; else echo null; fi
}

MERGED=$(read_json "$PERSIST_DIR/${BASE}--merged.json")
FINDINGS=$(read_json "$PERSIST_DIR/${BASE}--findings.json")
ARBITER=$(read_json "$PERSIST_DIR/${BASE}--arbiter.json")
DECISIONS=$(read_json "$PERSIST_DIR/${BASE}--decisions.json")
DELTA=$(read_json "$PERSIST_DIR/${BASE}--delta.json")
DELTA1=$(read_json "$PERSIST_DIR/${BASE}--delta.round1.json")

# Журнал считает решения только из массива объектов. До 3.0.0 пара прогонов записала
# `decisions.json` объектом другой формы — такие читаются как «решений нет» (null),
# а не роняют заливку.
if [[ "$DECISIONS" != "null" ]] \
   && ! printf '%s' "$DECISIONS" | jq -e 'type == "array" and all(.[]; type == "object")' >/dev/null 2>&1; then
  DECISIONS=null
fi

if [[ -s "$TIMES_FILE" ]]; then
  TIMES=$(jq -Rn '[inputs | select(test("^[a-z_]+=[0-9]+$")) | split("=") | {key: .[0], value: (.[1] | tonumber)}] | from_entries' < "$TIMES_FILE")
else
  TIMES='{}'
fi

DOC_SHA="null"
if [[ -n "$TARGET" && -f "$TARGET" ]]; then
  DOC_SHA=$(shasum -a 256 "$TARGET" | awk '{print $1}' | jq -R .)
fi

# Порядковый номер — просто число уже записанных строк + 1 (журнал только дозаписывается).
if [[ -s "$OUT" ]]; then
  RUN_NO=$(( $(grep -c '' "$OUT") + 1 ))
else
  RUN_NO=1
fi

ROW=$(jq -n -c \
  --argjson merged "$MERGED" \
  --argjson findings "$FINDINGS" \
  --argjson arbiter "$ARBITER" \
  --argjson decisions "$DECISIONS" \
  --argjson delta "$DELTA" \
  --argjson delta1 "$DELTA1" \
  --argjson times "$TIMES" \
  --argjson models "$MODELS" \
  --argjson mode "$MODE" \
  --argjson delta_by "$DELTA_BY" \
  --argjson doc_sha "$DOC_SHA" \
  --argjson fix_rounds "$FIX_ROUNDS" \
  --argjson run_no "$RUN_NO" \
  --argjson backfilled "$BACKFILLED" \
  --arg base "$BASE" \
  --arg target "$TARGET" \
  --arg type "$TYPE" '

  def minutes($a; $b):
    if ($times[$a] // null) == null or ($times[$b] // null) == null then null
    else (((($times[$b] - $times[$a]) / 60) * 10) | round) / 10 end;
  def accepted: [$decisions[]? | select(.decision == "applied" or .decision == "custom")];
  def sev_of: (.severity // "unknown");

  # Ветки прогона: `consensus.providers` появился не сразу, а в одном старом формате был
  # объектом label→verdict. Ничего не нашлось — берём ключи merged кроме `consensus`.
  (($merged.consensus.providers // null)
   | if type == "array" then . elif type == "object" then keys else null end) as $prov
  | ($prov // (if ($merged | type) == "object" then (($merged | keys) - ["consensus"]) else [] end)) as $labels
  | ($labels | map(. as $l | {key: $l,
       value: ((($merged[$l] // {}) | if type == "object" then (.findings // []) else [] end) | length)})
     | from_entries) as $raised
  | (if $findings == null then null else ($findings | length) end) as $n_findings
  | (if $findings == null or ($labels | length) == 0 then null
     else (([$raised[]] | add) - ($findings | length)) end) as $duplicates
  | (accepted) as $acc
  | ($arbiter.assessments // []) as $ass
  | ([$decisions[]? | select(.why_asked == "spot-check")] | first) as $spot
  # merged до 3.1.0 полей покрытия не несёт — восстанавливаем их по признаку заглушки,
  # иначе обратная заливка не даёт базовой линии по доле partial.
  | ($labels | map(. as $l | select(
        ((($merged[$l] // {}) | if type == "object" then (.summary // "") else "" end)
         | test("produced no valid JSON output"))
        and ($raised[$l] == 0)))) as $stubbed
  | (if ($merged.consensus.coverage // null) != null then $merged.consensus.coverage
     elif ($labels | length) == 0 then null
     elif ($stubbed | length) == 0 then "full"
     else "partial" end) as $coverage
  | ($merged.consensus.verdict // null) as $verdict
  | {
      run: $run_no,
      date: ($base | split("--")[0]),
      base: $base,
      target: (if $target == "" then null else $target end),
      doc_sha256: $doc_sha,
      type: (if $type == "" then null else $type end),
      models: $models,

      coverage: $coverage,
      dropped: ($merged.consensus.dropped // (if ($labels | length) == 0 then null else $stubbed end)),
      verdict: $verdict,
      status: ($merged.consensus.status
               // (if $coverage == "partial" and $verdict == "approve" then "needs-revision" else $verdict end)),

      raised: (if ($labels | length) == 0 then null else $raised end),
      findings: $n_findings,
      duplicates: $duplicates,

      to_human: (if $decisions == null then null
                 else ([$decisions[] | select(.decided_by == "user")] | length) end),
      accepted: (if $decisions == null then null else ($acc | length) end),
      rejected: (if $decisions == null then null
                 else ([$decisions[] | select(.decision == "skipped")] | length) end),
      accepted_by: (if $decisions == null or ($labels | length) == 0 then null
                    else ($labels | map(. as $l | {key: $l,
                          value: ([$acc[] | select(((.sources // []) | index($l)) != null)] | length)})
                          | from_entries) end),
      unique_accepted: (if $decisions == null or ($labels | length) == 0 then null
                        else ($labels | map(. as $l | {key: $l,
                              value: ([$acc[] | select((.sources // []) == [$l])] | length)})
                              | from_entries) end),
      by_severity: (if $decisions == null then null
                    else ($acc | map(sev_of) | group_by(.)
                          | map({key: .[0], value: length}) | from_entries) end),

      interview_mode: $mode,
      decided_by: (if $decisions == null then null
                   else ([$decisions[] | .decided_by // "unknown"] | group_by(.)
                         | map({key: .[0], value: length}) | from_entries) end),
      auto_low_confidence: (if $decisions == null then null
                            else ([$decisions[] | select(.auto_low_confidence == true)] | length) end),
      forks: (if $decisions == null then null
              else ([$decisions[] | select((.why_asked // null) != null and .why_asked != "spot-check")] | length) end),
      why_asked: (if $decisions == null then null
                  else ([$decisions[] | select((.why_asked // null) != null) | .why_asked]
                        | group_by(.) | map({key: .[0], value: length}) | from_entries) end),
      spot_check: (if $decisions == null then null
                   elif $spot == null then {asked: false, agreed: null}
                   else {asked: true,
                         # Auto-decision per A3.2: refuted or skip -> skipped; apply and leftover discuss -> applied.
                         agreed: (if ($spot.arbiter_recommendation // null) == null then null
                                  elif ($spot.refuted // false) or $spot.arbiter_recommendation == "skip"
                                    then ($spot.decision == "skipped")
                                  else ($spot.decision != "skipped") end)} end),

      arbiter_judged: (if $decisions == null then null
                       else ([$decisions[] | select((.arbiter_recommendation // null) != null)] | length) end),
      arbiter_overruled: (if $decisions == null then null
                          else ([$decisions[]
                                 | select((.arbiter_recommendation // null) != null)
                                 | select((.arbiter_recommendation == "apply" and .decision == "skipped")
                                       or (.arbiter_recommendation == "skip" and .decision != "skipped"))]
                                | length) end),
      irreversible: (if $arbiter == null then null
                     else ([$ass[] | select(.reversible == false)] | length) end),

      machine_min: minutes("prelude"; "machine_done"),
      interview_min: minutes("interview_start"; "interview_done"),

      fix_rounds: $fix_rounds,
      # Regressions of the FIRST re-check pass when a fix round happened (round1 copy), else of the only pass.
      fix_regressions: (if $delta == null then null
                        else ((($delta1 // $delta).regressions // []) | length) end),
      fix_regressions_left: (if $delta == null then null else (($delta.regressions // []) | length) end),
      delta_by: $delta_by,
      delta_status: ($delta.status // null),

      backfilled: $backfilled
    }
')

# Одна строка, одна дозапись. jq уже проверил валидность — печатаем как есть.
printf '%s\n' "$ROW" >> "$OUT"

if [[ "$KEEP_TIMES" == 0 && -e "$TIMES_FILE" ]]; then
  rm -f "$TIMES_FILE"
fi

echo "LOGGED run=$RUN_NO base=$BASE → $OUT"
