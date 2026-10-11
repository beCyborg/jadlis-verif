#!/usr/bin/env bash
# rounds.sh — Разложить находки по раундам интервью по зависимостям из оценки арбитра.
#
# Usage:
#   rounds.sh --findings <findings.json> [--arbiter <arbiter.json>] [--ids "F1 F3 …"]
#
# Раунд 1 — находки, которые ни от чего не зависят. Раунд k — находки, у которых все
# зависимости лежат в раундах < k. Так в одном раунде нет двух находок, где ответ на одну
# меняет другую: сначала решаются корни, потом то, что от них зависит.
#
# Зависимости берутся из `assessments[].depends_on` арбитра. Ссылки на id, которых нет в
# разбираемом наборе (`--ids` или все находки), на себя и повторы отбрасываются. Цикл не
# роняет разбор: ребро A→B, где B сам (через цепочку) зависит от A, отбрасывается, а A
# получает `cycle: true`. Зависимости цикла от находок вне цикла остаются в силе.
# Нет арбитра или у находки нет оценки — она ни от чего не зависит.
#
# Вывод — JSON-массив в порядке раундов, внутри раунда — в порядке findings.json:
#   [{"id":"F1","round":1,"depends_on":[],"cycle":false}, …]
set -euo pipefail

FINDINGS=""
ARBITER=""
IDS=""

usage() {
  echo "Usage: $0 --findings <findings.json> [--arbiter <arbiter.json>] [--ids \"F1 F3 …\"]" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --findings) FINDINGS="$2"; shift 2 ;;
    --arbiter)  ARBITER="$2";  shift 2 ;;
    --ids)      IDS="$2";      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$FINDINGS" && -s "$FINDINGS" ]] || usage

ARB_JSON=null
if [[ -n "$ARBITER" && -s "$ARBITER" ]] && jq -e . "$ARBITER" >/dev/null 2>&1; then
  ARB_JSON=$(cat "$ARBITER")
fi

jq -c \
  --argjson arb "$ARB_JSON" \
  --arg ids "$IDS" '
  [.[] | .id] as $all
  | (if $ids == "" then $all else ($ids | split(" ") | map(select(. != ""))) end) as $scope
  | [$all[] | select(. as $i | $scope | index($i))] as $order
  | (($arb.assessments // []) | map({key: .id, value: (.depends_on // [])}) | from_entries) as $raw
  | ($order | map(. as $i | {key: $i,
        value: (($raw[$i] // []) | map(select(. != $i and (. as $d | $order | index($d)))) | unique)})
     | from_entries) as $deps0
  # Достижимость: $reach[i] — все находки, от которых i зависит прямо или через цепочку.
  | (reduce range(0; ($order | length)) as $_ ($deps0;
       . as $m | with_entries(.value = ((.value + ([.value[] | $m[.][]])) | unique))) ) as $reach
  | ($order | map(. as $i | {key: $i,
        value: ($deps0[$i] | map(select(. as $d | ($reach[$d] | index($i)) | not)))}) | from_entries) as $deps
  | ($order | map(. as $i | {key: $i, value: (($deps0[$i] | length) != ($deps[$i] | length))}) | from_entries) as $cyc
  | {left: $order, done: [], out: [], r: 1}
  | until((.left | length) == 0;
      . as $s
      | ($s.left | map(select(. as $i | $deps[$i] | all(. as $d | $s.done | index($d))))) as $ready
      # После разрыва циклов граф ацикличен, и $ready не бывает пустым; страховка — сбросить остаток.
      | (if ($ready | length) > 0 then $ready else $s.left end) as $take
      | {left: ($s.left - $take), done: ($s.done + $take),
         out: ($s.out + ($take | map({id: ., round: $s.r, depends_on: $deps[.], cycle: $cyc[.]}))),
         r: ($s.r + 1)})
  | .out
' "$FINDINGS"
