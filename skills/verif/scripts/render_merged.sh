#!/usr/bin/env bash
# render_merged.sh — Human-readable rendering of a merged N-provider verdict.
#
# Usage:
#   render_merged.sh <merged.json>
#
# Reads JSON shaped as { consensus: {verdict, rule, disagreement, providers[]},
# <label>: {...}, ... } and prints a compact summary with per-verifier findings
# and a union of next_steps across all providers.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <merged.json>" >&2
  exit 64
fi

MERGED="$1"

if [[ ! -s "$MERGED" ]] || ! jq -e . "$MERGED" >/dev/null 2>&1; then
  echo "ERROR: merged file missing or invalid JSON: $MERGED" >&2
  exit 65
fi

jq -r '
  def block(lbl; v):
    "=== \(lbl | ascii_upcase) (\(v.verdict | ascii_upcase)) ===\n" +
    "SUMMARY: \(v.summary // "(no summary)")\n" +
    "FINDINGS (\(v.findings | length)):\n" +
    ((v.findings // [])
      | map("  [\(.severity | ascii_upcase)] \(.title)"
            + " (\(.category), \(.claim_type))"
            + (if .file then " — \(.file)" + (if .line_start then ":\(.line_start)" else "" end) else "" end))
      | (if length == 0 then ["  (none)"] else . end)
      | join("\n"));

  . as $m
  | (.consensus.providers // (keys - ["consensus"])) as $labels
  | "VERDICT: \(.consensus.verdict | ascii_upcase)\n" +
    "RULE: \(.consensus.rule)\n" +
    "PROVIDERS: \($labels | join(", "))\n" +
    "DISAGREEMENT: \(.consensus.disagreement)\n\n" +
    ($labels | map(block(.; $m[.])) | join("\n\n")) + "\n\n" +
    "NEXT STEPS (union):\n" +
    ([$labels[] | $m[.].next_steps // []] | add
      | unique
      | (if length == 0 then ["  (none)"] else map("  - " + .) end)
      | join("\n"))
' "$MERGED"
