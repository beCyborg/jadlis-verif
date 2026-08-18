#!/usr/bin/env bash
# Нормализация сырых ответов трёх CLI → merge → render → save.
#
# Каждый провайдер отдаёт verdict по-своему, и форма менялась между версиями CLI,
# поэтому каскад из нескольких попыток обязателен — не «на всякий случай»:
#   Codex — exec пишет прогресс-лог в stdout, verdict-JSON идёт ПОСЛЕДНЕЙ строкой;
#   Fable — .structured_output, либо .result чистым JSON, либо .result в ```json-fence;
#   Grok  — .structuredOutput (top-level, camelCase), либо .text как JSON,
#           либо (grok CLI ≥1.0.3) .text = НЕСКОЛЬКО конкатенированных JSON-объектов
#           (модель эмитит промежуточный JSON до tool-call'ов; CLI склеивает все
#           сообщения, его собственный парсер падает на «trailing characters» и
#           оставляет .structuredOutput = null) → берём ПОСЛЕДНИЙ валидный объект
#           с полем verdict.
# Не распознали — пишем '{}', merge превратит его в stub unreliable (провайдер молчит,
# а не «согласен»).
#
# Вход — переменные окружения:
#   CODEX_OUT FABLE_OUT GROK_OUT   сырые stdout-файлы верификаторов
#   GROK_PARTICIPATED              1, если Grok запускался (отсутствие != unreliable)
#   MERGED_OUT VERDICT_MD          куда положить merged JSON и rendered markdown
#   JSON_MODE                      1 → печатать merged JSON вместо рендера
#   PROMPT_FILE CLAUDE_SCHEMA_FILE опц., удаляются в конце
set -euo pipefail

# ${CLAUDE_PLUGIN_ROOT} в Bash НЕ подставляется — резолвим корень скилла от самого скрипта.
VERIFIER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Срезать мусорные префиксы CLI (warning-строки до JSON): взять с первой строки, начинающейся с {
strip_preamble() { sed -n '/^{/,$p' "$1"; }

CODEX_VERDICT=$(mktemp -t verif-codex-verdict.XXXXXX.json)
if [[ -s "$CODEX_OUT" ]] && jq -e '.verdict' "$CODEX_OUT" >/dev/null 2>&1; then
  jq . "$CODEX_OUT" > "$CODEX_VERDICT"
elif [[ -s "$CODEX_OUT" ]] && tail -1 "$CODEX_OUT" | jq -e '.verdict' >/dev/null 2>&1; then
  tail -1 "$CODEX_OUT" > "$CODEX_VERDICT"
else
  echo '{}' > "$CODEX_VERDICT"
fi

FABLE_ENV=$(mktemp -t verif-fable-env.XXXXXX.json)
strip_preamble "$FABLE_OUT" > "$FABLE_ENV"
FABLE_VERDICT=$(mktemp -t verif-fable-verdict.XXXXXX.json)
if [[ -s "$FABLE_ENV" ]] && jq -e '.structured_output' "$FABLE_ENV" >/dev/null 2>&1; then
  jq '.structured_output' "$FABLE_ENV" > "$FABLE_VERDICT"
elif [[ -s "$FABLE_ENV" ]] && jq -e '.result | fromjson | .verdict' "$FABLE_ENV" >/dev/null 2>&1; then
  jq '.result | fromjson' "$FABLE_ENV" > "$FABLE_VERDICT"
elif [[ -s "$FABLE_ENV" ]] && jq -r '.result // empty' "$FABLE_ENV" | sed -n '/^```/,/^```/p' | sed '1d;$d' | jq -e '.verdict' >/dev/null 2>&1; then
  jq -r '.result' "$FABLE_ENV" | sed -n '/^```/,/^```/p' | sed '1d;$d' | jq . > "$FABLE_VERDICT"
elif [[ -s "$FABLE_ENV" ]] && jq -e '.verdict' "$FABLE_ENV" >/dev/null 2>&1; then
  jq . "$FABLE_ENV" > "$FABLE_VERDICT"
else
  echo '{}' > "$FABLE_VERDICT"
fi

MERGE_ARGS=("codex:$CODEX_VERDICT" "fable:$FABLE_VERDICT")

if [[ "${GROK_PARTICIPATED:-0}" == "1" ]]; then
  GROK_ENV=$(mktemp -t verif-grok-env.XXXXXX.json)
  strip_preamble "$GROK_OUT" > "$GROK_ENV"
  GROK_VERDICT=$(mktemp -t verif-grok-verdict.XXXXXX.json)
  if [[ -s "$GROK_ENV" ]] && jq -e '.structuredOutput' "$GROK_ENV" >/dev/null 2>&1; then
    jq '.structuredOutput' "$GROK_ENV" > "$GROK_VERDICT"
  elif [[ -s "$GROK_ENV" ]] && jq -e '.text | fromjson | .verdict' "$GROK_ENV" >/dev/null 2>&1; then
    jq '.text | fromjson' "$GROK_ENV" > "$GROK_VERDICT"
  elif [[ -s "$GROK_ENV" ]] && python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
t = d.get("text") or ""
dec = json.JSONDecoder()
i = 0
last = None
while True:
    j = t.find("{", i)
    if j < 0:
        break
    try:
        obj, end = dec.raw_decode(t, j)
        if isinstance(obj, dict) and "verdict" in obj:
            last = obj
        i = end
    except ValueError:
        i = j + 1
if last is None:
    sys.exit(1)
print(json.dumps(last, ensure_ascii=False))
' "$GROK_ENV" > "$GROK_VERDICT" 2>/dev/null && jq -e '.verdict' "$GROK_VERDICT" >/dev/null 2>&1; then
    : # последний валидный JSON-объект с verdict уже в $GROK_VERDICT
  elif [[ -s "$GROK_ENV" ]] && jq -e '.verdict' "$GROK_ENV" >/dev/null 2>&1; then
    jq . "$GROK_ENV" > "$GROK_VERDICT"
  else
    echo '{}' > "$GROK_VERDICT"
  fi
  MERGE_ARGS+=("grok:$GROK_VERDICT")
fi

bash "$VERIFIER_ROOT/scripts/merge_verdicts.sh" "${MERGE_ARGS[@]}" > "$MERGED_OUT"

if [[ "${JSON_MODE:-0}" == "1" ]]; then
  cat "$MERGED_OUT"
else
  bash "$VERIFIER_ROOT/scripts/render_merged.sh" "$MERGED_OUT"
fi
bash "$VERIFIER_ROOT/scripts/render_merged.sh" "$MERGED_OUT" > "$VERDICT_MD"

rm -f "${PROMPT_FILE:-}" "${CLAUDE_SCHEMA_FILE:-}" 2>/dev/null || true
