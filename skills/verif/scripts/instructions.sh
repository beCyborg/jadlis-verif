#!/usr/bin/env bash
# instructions.sh — the ONE source of the edit instruction for every accepted finding.
#
# Phase B gives these instructions to the fixing subagents; Phase C (delta-recheck.md, C1) checks
# each edit against the same text. Before 3.5.0 Phase C rebuilt the instruction from
# `finding.recommendation`, while Phase B applied `decision_question.recommended_detail` for a
# decision answered "as the arbiter advises" — the re-check then compared the edit with a text
# nobody had applied.
#
# Usage:
#   instructions.sh --decisions <decisions.json> --findings <findings.json> [--arbiter <arbiter.json>] [--ids "F3 F5"]
#
# Output: JSON array, one object per accepted finding (decision applied|custom), in decisions order:
#   {id, title, file, line_start, line_end, round, depends_on, instruction, instruction_source}
# instruction_source, first match wins:
#   instruction         — decisions.json carries `instruction` (A4 wrote the exact text applied)
#   custom              — decision custom → custom_instruction
#   recommended_detail  — kind decision, answer recommended → arbiter decision_question.recommended_detail
#   recommendation      — everything else → findings.json recommendation
# A missing or unreadable arbiter file is fine: the chain just skips that step.
set -euo pipefail

DECISIONS=""; FINDINGS=""; ARBITER=""; IDS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --decisions) DECISIONS="$2"; shift 2 ;;
    --findings)  FINDINGS="$2";  shift 2 ;;
    --arbiter)   ARBITER="$2";   shift 2 ;;
    --ids)       IDS="$2";       shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done
[[ -s "$DECISIONS" && -s "$FINDINGS" ]] || { echo "Usage: $0 --decisions <f> --findings <f> [--arbiter <f>] [--ids \"F1 F2\"]" >&2; exit 64; }

ARB='{"assessments":[]}'
if [[ -n "$ARBITER" && -s "$ARBITER" ]] && jq -e '.assessments | type == "array"' "$ARBITER" >/dev/null 2>&1; then
  ARB=$(cat "$ARBITER")
fi

jq -n --slurpfile d "$DECISIONS" --slurpfile f "$FINDINGS" --argjson arb "$ARB" --arg ids "$IDS" '
  ($f[0] | map({key: .id, value: .}) | from_entries) as $byid
  | ($arb.assessments | map({key: .id, value: .}) | from_entries) as $ass
  | ($ids | split(" ") | map(select(. != ""))) as $only
  | $d[0]
  | map(select(.decision == "applied" or .decision == "custom"))
  | map(select(($only | length) == 0 or (.id as $i | $only | index($i)) != null))
  | map(. as $x
      | ($byid[$x.id] // {}) as $fi
      | ($ass[$x.id] // {}) as $a
      | (if (($x.instruction // "") | length) > 0 then {t: $x.instruction, s: "instruction"}
         elif $x.decision == "custom" then {t: ($x.custom_instruction // ""), s: "custom"}
         elif ($x.kind // $a.kind // null) == "decision" and ($x.answer // null) == "recommended"
              and (($a.decision_question.recommended_detail // "") | length) > 0
           then {t: $a.decision_question.recommended_detail, s: "recommended_detail"}
         else {t: ($fi.recommendation // ""), s: "recommendation"} end) as $ins
      | {id: $x.id,
         title: ($x.title // $fi.title // null),
         file: ($x.file // $fi.file // null),
         line_start: ($fi.line_start // null),
         line_end: ($fi.line_end // null),
         round: ($x.round // 1),
         depends_on: ($a.depends_on // []),
         instruction: $ins.t,
         instruction_source: $ins.s})'
