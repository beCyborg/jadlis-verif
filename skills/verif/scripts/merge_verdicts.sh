#!/usr/bin/env bash
# merge_verdicts.sh — Merge N labeled verdict JSON files under strict hierarchy.
#
# Usage:
#   merge_verdicts.sh <label>:<path> [<label>:<path> ...]
#   e.g. merge_verdicts.sh codex:/p/c.json fable:/p/f.json
#
# Output (to stdout):
#   { "consensus": { verdict, rule, disagreement, providers: [...],
#                    coverage: "full|partial", dropped: [...], status },
#     "<label>": {...}, ... }
#
# Semantics:
#   - A provider that IS passed but has invalid/empty JSON → {verdict:"unreliable"} stub
#     on disk AND its label goes to `dropped`: the branch did not answer, so it does not
#     vote. Консенсус с 3.1.0 считается ТОЛЬКО по ответившим веткам — одна упавшая ветка
#     больше не делает весь прогон unreliable, она делает покрытие частичным.
#   - A provider that is NOT passed (e.g. degraded out) is simply absent from the
#     consensus — absence != unreliable (и в `dropped` не попадает: его не звали).
#   - Ответивших веток нет вовсе → verdict "unreliable", как раньше.
#   - `coverage`: "full" пока `dropped` пуст, иначе "partial".
#   - `status` — вердикт прогона после гейта покрытия: при `partial` approve поднимается
#     до needs-revision (неполная проверка не выдаёт финального «можно делать»).
#     `verdict` при этом остаётся сырым — что сказали ответившие ветки.
#
# Hierarchy: unreliable (2) > needs-revision (1) > approve (0).
set -euo pipefail

usage() {
  echo "Usage: $0 <label>:<path> [<label>:<path> ...]" >&2
  exit 64
}

[[ $# -lt 1 ]] && usage

# Pre-flight per file: valid JSON С полем .verdict, иначе {verdict:"unreliable"} stub.
# Именно .verdict, не просто валидность: '{}' от normalize_and_merge.sh — валидный JSON,
# но без verdict merge падал на rank(null) («Cannot index object with null»).
# Тот же предикат отдельной функцией — по нему ниже собирается список `dropped`.
# Флагом внутри normalize() это не сделать: её зовут в $(...), т.е. в подоболочке,
# и присваивание туда не возвращается.
answered() {
  local f="$1"
  [[ -s "$f" ]] && jq -e '.verdict' "$f" >/dev/null 2>&1
}

normalize() {
  local f="$1" label="$2"
  if answered "$f"; then
    cat "$f"
  else
    jq -n --arg l "$label" '{
      verdict: "unreliable",
      summary: "\($l) produced no valid JSON output — treated as unreliable.",
      findings: [],
      next_steps: []
    }'
  fi
}

JQ_ARGS=()
LABELS=()
DROPPED=()
for spec in "$@"; do
  label="${spec%%:*}"
  file="${spec#*:}"
  if [[ -z "$label" || -z "$file" || "$label" == "$spec" ]]; then
    echo "Invalid argument '$spec' — expected <label>:<path>" >&2
    usage
  fi
  if [[ "$label" == "consensus" ]] || ! [[ "$label" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "Invalid label '$label' (reserved or non [a-z][a-z0-9_-]*)" >&2
    usage
  fi
  for seen in "${LABELS[@]:-}"; do
    [[ "$seen" == "$label" ]] && { echo "Duplicate label '$label'" >&2; usage; }
  done
  JQ_ARGS+=(--argjson "$label" "$(normalize "$file" "$label")")
  LABELS+=("$label")
  answered "$file" || DROPPED+=("$label")
done

LABELS_JSON=$(printf '%s\n' "${LABELS[@]}" | jq -R . | jq -s .)
if [[ ${#DROPPED[@]} -eq 0 ]]; then
  DROPPED_JSON='[]'
else
  DROPPED_JSON=$(printf '%s\n' "${DROPPED[@]}" | jq -R . | jq -s .)
fi

jq -n "${JQ_ARGS[@]}" --argjson labels "$LABELS_JSON" --argjson dropped "$DROPPED_JSON" '
  def rank(v): {approve:0, "needs-revision":1, unreliable:2}[v] // 2;
  ($labels | map({key: ., value: $ARGS.named[.]}) | from_entries) as $providers
  # Голосуют только ответившие ветки; упавшая уходит в dropped и покрытие становится частичным.
  | ($labels - $dropped) as $responding
  | [$responding[] | $providers[.].verdict] as $verdicts
  | (if ($verdicts | length) == 0 then "unreliable" else ($verdicts | max_by(rank(.))) end) as $verdict
  | (if ($dropped | length) == 0 then "full" else "partial" end) as $coverage
  | {
      consensus: {
        verdict: $verdict,
        rule: "strict_hierarchy",
        disagreement: (($verdicts | unique | length) > 1),
        providers: $labels,
        coverage: $coverage,
        dropped: $dropped,
        status: (if $coverage == "partial" and $verdict == "approve"
                 then "needs-revision" else $verdict end)
      }
    } + $providers
'
