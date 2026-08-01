#!/usr/bin/env bash
# build_prompt.sh — Assemble final verifier prompt from a template + target + focus.
#
# Usage:
#   build_prompt.sh --type plan|research|doc --file <absolute-path> --focus "<text>"
#
# Outputs the assembled prompt to stdout. No side effects other than reading
# the template. Testable standalone for debugging without invoking Codex.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROMPTS_DIR="$VERIFIER_ROOT/prompts"

TYPE=""
FILE=""
FOCUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)  TYPE="$2";  shift 2 ;;
    --file)  FILE="$2";  shift 2 ;;
    --focus) FOCUS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$TYPE" || -z "$FILE" ]]; then
  echo "Usage: $0 --type plan|research|doc --file <path> [--focus \"<text>\"]" >&2
  exit 64
fi

case "$TYPE" in
  plan|research|doc) ;;
  *) echo "Invalid --type '$TYPE'. Allowed: plan, research, doc" >&2; exit 64 ;;
esac

TEMPLATE="$PROMPTS_DIR/$TYPE.md"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 66
fi

# Default focus when caller omits it
: "${FOCUS:=general adversarial review}"

# Escape replacements for awk's gsub (backslashes and ampersands are special)
escape_for_sub() {
  printf '%s' "$1" | sed -e 's/[\&/]/\\&/g'
}

FILE_ESC=$(escape_for_sub "$FILE")
FOCUS_ESC=$(escape_for_sub "$FOCUS")

sed -e "s/{{TARGET_PATH}}/$FILE_ESC/g" \
    -e "s/{{USER_FOCUS}}/$FOCUS_ESC/g" \
    "$TEMPLATE"

# Footer reminding Codex of the schema binding
cat <<'FOOTER'

---

REMINDER: Emit ONLY JSON that matches the schema provided via --output-schema.
Do not include any prose outside the JSON document. See AGENTS.md (loaded from
CODEX_HOME) for epistemic discipline (FACT/INFERENCE/SPECULATION), primary-
source policy, and source-date requirements.
FOOTER
