#!/usr/bin/env bash
# selftest.sh — offline checks of the deterministic /verif scripts on synthetic data (3.5.0).
# No CLI, no network, no vault: everything happens in a temp dir that is removed at the end.
# Usage: bash tools/selftest.sh   → prints PASS/FAIL per check, exit 1 on any FAIL.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/skills/verif/scripts"
T=$(mktemp -d -t verif-selftest.XXXXXX)
trap 'rm -rf "$T"' EXIT
FAILS=0
check() { # check <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then echo "PASS  $1"; else echo "FAIL  $1"; echo "      expected: $2"; echo "      actual:   $3"; FAILS=$((FAILS+1)); fi
}

# ---------- instructions.sh: one source for Phase B and Phase C (G4) ----------
cat > "$T/findings.json" <<'J'
[{"id":"F1","title":"fact","recommendation":"REC-F1","file":"/x/plan.md","line_start":3},
 {"id":"F2","title":"decision rec","recommendation":"REC-F2","file":null},
 {"id":"F3","title":"decision custom","recommendation":"REC-F3","file":null},
 {"id":"F4","title":"skipped","recommendation":"REC-F4","file":null},
 {"id":"F5","title":"decision, own text in decisions","recommendation":"REC-F5","file":null},
 {"id":"F6","title":"decision rec, no decision_question","recommendation":"REC-F6","file":null}]
J
cat > "$T/arbiter.json" <<'J'
{"assessments":[
 {"id":"F1","kind":"fact","recommendation":"apply","depends_on":[],"decision_question":null},
 {"id":"F2","kind":"decision","recommendation":"apply","depends_on":["F1"],
  "decision_question":{"question":"q","recommended":"r","recommended_detail":"DETAIL-F2","alternative":null,"alternative_detail":null}},
 {"id":"F3","kind":"decision","recommendation":"discuss","depends_on":[],
  "decision_question":{"question":"q","recommended":"r","recommended_detail":"DETAIL-F3","alternative":"a","alternative_detail":"ALT-F3"}},
 {"id":"F5","kind":"decision","recommendation":"apply","depends_on":[],
  "decision_question":{"question":"q","recommended":"r","recommended_detail":"DETAIL-F5","alternative":null,"alternative_detail":null}},
 {"id":"F6","kind":"decision","recommendation":"apply","depends_on":[],"decision_question":null}]}
J
cat > "$T/decisions.json" <<'J'
[{"id":"F1","decision":"applied","kind":"fact","answer":null,"decided_by":"auto","self_decided":true,"auto_decision":"applied"},
 {"id":"F2","decision":"applied","kind":"decision","answer":"recommended","decided_by":"auto","self_decided":true,"auto_decision":"applied","round":2},
 {"id":"F3","decision":"custom","kind":"decision","answer":"alternative","custom_instruction":"ALT-F3","decided_by":"user"},
 {"id":"F4","decision":"skipped","kind":"fact","decided_by":"auto","self_decided":true,"auto_decision":"skipped"},
 {"id":"F5","decision":"applied","kind":"decision","answer":"recommended","instruction":"MAIN-THREAD-F5","decided_by":"user"},
 {"id":"F6","decision":"applied","kind":"decision","answer":"recommended","decided_by":"user"}]
J
OUT=$(bash "$S/instructions.sh" --decisions "$T/decisions.json" --findings "$T/findings.json" --arbiter "$T/arbiter.json")
check "instructions: fact applied → recommendation" "REC-F1/recommendation" "$(jq -r '.[]|select(.id=="F1")|"\(.instruction)/\(.instruction_source)"' <<<"$OUT")"
check "instructions: decision recommended → recommended_detail (the G4 gap)" "DETAIL-F2/recommended_detail" "$(jq -r '.[]|select(.id=="F2")|"\(.instruction)/\(.instruction_source)"' <<<"$OUT")"
check "instructions: custom → custom_instruction" "ALT-F3/custom" "$(jq -r '.[]|select(.id=="F3")|"\(.instruction)/\(.instruction_source)"' <<<"$OUT")"
check "instructions: skipped not listed" "" "$(jq -r '.[]|select(.id=="F4")|.id' <<<"$OUT")"
check "instructions: explicit instruction wins" "MAIN-THREAD-F5/instruction" "$(jq -r '.[]|select(.id=="F5")|"\(.instruction)/\(.instruction_source)"' <<<"$OUT")"
check "instructions: no decision_question → recommendation" "REC-F6/recommendation" "$(jq -r '.[]|select(.id=="F6")|"\(.instruction)/\(.instruction_source)"' <<<"$OUT")"
check "instructions: depends_on and round carried" '["F1"]/2' "$(jq -r -c '.[]|select(.id=="F2")|"\(.depends_on|tojson)/\(.round)"' <<<"$OUT")"
check "instructions: --ids filter" "F2" "$(bash "$S/instructions.sh" --decisions "$T/decisions.json" --findings "$T/findings.json" --arbiter "$T/arbiter.json" --ids "F2" | jq -r 'map(.id)|join(",")')"
NOARB=$(bash "$S/instructions.sh" --decisions "$T/decisions.json" --findings "$T/findings.json" --arbiter "$T/missing.json")
check "instructions: no arbiter file → recommendation" "REC-F2/recommendation" "$(jq -r '.[]|select(.id=="F2")|"\(.instruction)/\(.instruction_source)"' <<<"$NOARB")"
# Phase C frozen list exactly as delta-recheck.md C1 builds it
FROZEN=$(jq -c 'map({id, title, file, instruction})' <<<"$OUT")
check "Phase C frozen list = Phase B instruction" "DETAIL-F2" "$(jq -r '.[]|select(.id=="F2")|.instruction' <<<"$FROZEN")"

# ---------- verif-settings.py ----------
vs() { VERIF_SETTINGS_FILE="$1" python3 "$S/verif-settings.py" "${@:2}" | jq -r -c '"\(.interview)/\(.decisions)/\(.reason)"'; }
check "settings: no file → ask/ask" "ask/ask/no file" "$(vs "$T/none.json")"
echo '{"interview":"auto","decisions":"auto"}' > "$T/v1.json"
check "settings: both auto" "auto/auto/file" "$(vs "$T/v1.json")"
echo '{"interview":"auto"}' > "$T/v2.json"
check "settings: missing key → ask" "auto/ask/file" "$(vs "$T/v2.json")"
echo '{"interview":"auto","decisions":"always"}' > "$T/v3.json"
check "settings: unknown value → today's behaviour" "ask/ask/bad decisions value" "$(vs "$T/v3.json")"
echo '{oops' > "$T/v4.json"
check "settings: broken JSON → today's behaviour" "ask/ask/unreadable JSON" "$(vs "$T/v4.json")"
echo '["auto"]' > "$T/v5.json"
check "settings: not an object → today's behaviour" "ask/ask/unreadable JSON" "$(vs "$T/v5.json")"
check "settings: --manual wins over the file" "manual/ask/--manual" "$(vs "$T/v1.json" --manual)"

# ---------- changed_sections.py ----------
printf '# Plan\nintro\n## Steps\na\nb\n## Risks\nr1\n```\n# not a heading\n```\n## Tail\nz\n' > "$T/old.md"
printf '# Plan\nintro\n## Steps\na\nB changed\n## Risks\nr1\n```\n# not a heading\nnew code line\n```\n## Tail\n' > "$T/new.md"
CS=$(python3 "$S/changed_sections.py" "$T/old.md" "$T/new.md" | jq -r -c '.sections|join(" | ")')
check "changed_sections: headings of edits and deletions, fenced # ignored" "## Steps | ## Risks | ## Tail" "$CS"
check "changed_sections: new file from /dev/null" "# Plan" "$(python3 "$S/changed_sections.py" /dev/null "$T/old.md" | jq -r '.sections[0]')"

# ---------- log_run.sh: settings, self_decided, --update ----------
P="$T/persist"; mkdir -p "$P"; B="2026-11-09--selftest"
cp "$T/findings.json" "$P/$B--findings.json"; cp "$T/arbiter.json" "$P/$B--arbiter.json"; cp "$T/decisions.json" "$P/$B--decisions.json"
echo '{"consensus":{"providers":["codex","fable"],"verdict":"needs-revision","coverage":"full","dropped":[],"status":"needs-revision"},"codex":{"findings":[1,2,3]},"fable":{"findings":[1,2,3,4]}}' > "$P/$B--merged.json"
printf 'prelude=1000\nmachine_done=1600\ninterview_start=1600\ninterview_done=1660\n' > "$P/$B--run.times"
echo '{"run":1,"base":"older"}' > "$P/_runs.jsonl"
SET=$(VERIF_SETTINGS_FILE="$T/v1.json" python3 "$S/verif-settings.py")
bash "$S/log_run.sh" --persist-dir "$P" --base "$B" --mode auto --delta-by codex --fix-rounds 0 --settings "$SET" >/dev/null
ROW=$(tail -1 "$P/_runs.jsonl")
check "log: settings recorded, path not leaked" '{"interview":"auto","decisions":"auto","source":"file"}' "$(jq -c '.settings' <<<"$ROW")"
check "log: self_decided counts" '{"listed":3,"applied":2,"skipped":1,"decisions_applied":1,"returned":0,"returned_decisions":0,"volume_cut":0}' "$(jq -c '.self_decided' <<<"$ROW")"
check "log: interview minutes" "1" "$(jq -r '.interview_min' <<<"$ROW")"
# owner returns F2 after the run (A5): decision flips, auto_decision stays
jq 'map(if .id=="F2" then .decision="skipped" | .decided_by="user" | .returned=true else . end)' "$P/$B--decisions.json" > "$T/d2" && mv "$T/d2" "$P/$B--decisions.json"
bash "$S/log_run.sh" --persist-dir "$P" --base "$B" --settings "$SET" --update >/dev/null
check "log --update: still 2 lines" "2" "$(grep -c '' "$P/_runs.jsonl")"
ROW2=$(jq -c --arg b "$B" 'select(.base==$b)' "$P/_runs.jsonl")
check "log --update: run number kept" "2" "$(jq -r '.run' <<<"$ROW2")"
check "log --update: returned counted" "1/1/1" "$(jq -r '"\(.self_decided.returned)/\(.self_decided.returned_decisions)/\(.self_decided.decisions_applied)"' <<<"$ROW2")"
check "log --update: minutes and mode kept from old row" "1/auto/codex" "$(jq -r '"\(.interview_min)/\(.interview_mode)/\(.delta_by)"' <<<"$ROW2")"
check "log --update: other line untouched" '{"run":1,"base":"older"}' "$(head -1 "$P/_runs.jsonl")"
# a pre-3.5.0 decisions.json gives nulls, not zeros
B0="2026-11-09--old"; echo '[{"id":"F1","decision":"applied","decided_by":"user"}]' > "$P/$B0--decisions.json"
bash "$S/log_run.sh" --persist-dir "$P" --base "$B0" >/dev/null
check "log: pre-3.5.0 run → settings and self_decided null" "null/null" "$(tail -1 "$P/_runs.jsonl" | jq -r '"\(.settings)/\(.self_decided)"')"

# ---------- verif_stats.sh ----------
ST=$(bash "$S/verif_stats.sh" "$P/_runs.jsonl" | grep '^Решил сам')
check "stats: self-decided line" "Решил сам: 3 пунктов, применено 2, из них решений 1; ты вернул 1 — 33.3 %, решений 1 — 100 %   (прогонов: 1)" "$ST"

echo
if [[ "$FAILS" == 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAIL"; exit 1; fi
