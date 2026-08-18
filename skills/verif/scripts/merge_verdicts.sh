#!/usr/bin/env bash
# merge_verdicts.sh — Merge N labeled verdict JSON files under strict hierarchy.
#
# Usage:
#   merge_verdicts.sh <label>:<path> [<label>:<path> ...]
#   e.g. merge_verdicts.sh codex:/p/c.json fable:/p/f.json grok:/p/g.json
#
# Output (to stdout):
#   { "consensus": { verdict, rule, disagreement, providers: [...] },
#     "<label>": {...}, ... }
#
# Semantics:
#   - A provider that IS passed but has invalid/empty JSON → {verdict:"unreliable"} stub
#     (a participating provider that failed is evidence of unreliability).
#   - A provider that is NOT passed (e.g. degraded out) is simply absent from the
#     consensus — absence != unreliable.
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
normalize() {
  local f="$1" label="$2"
  if [[ -s "$f" ]] && jq -e '.verdict' "$f" >/dev/null 2>&1; then
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
done

LABELS_JSON=$(printf '%s\n' "${LABELS[@]}" | jq -R . | jq -s .)

jq -n "${JQ_ARGS[@]}" --argjson labels "$LABELS_JSON" '
  def rank(v): {approve:0, "needs-revision":1, unreliable:2}[v] // 2;
  ($labels | map({key: ., value: $ARGS.named[.]}) | from_entries) as $providers
  | [$providers[] | .verdict] as $verdicts
  | {
      consensus: {
        verdict: ($verdicts | max_by(rank(.))),
        rule: "strict_hierarchy",
        disagreement: (($verdicts | unique | length) > 1),
        providers: $labels
      }
    } + $providers
'
