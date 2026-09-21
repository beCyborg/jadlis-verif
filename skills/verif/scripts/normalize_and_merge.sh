#!/usr/bin/env bash
# Нормализация сырых ответов обоих CLI → merge → render → save.
#
# Каждый провайдер отдаёт verdict по-своему, и форма менялась между версиями CLI,
# поэтому каскад из нескольких попыток обязателен — не «на всякий случай»:
#   Codex — exec пишет прогресс-лог в stdout, verdict-JSON идёт ПОСЛЕДНЕЙ строкой;
#           GPT-6 Astra печатает его многострочным блоком после лога → третья ступень
#           сканирует файл с конца и берёт последний валидный объект с verdict;
#   Fable — .structured_output, либо .result чистым JSON, либо .result в ```json-fence.
# Не распознали — пишем '{}', merge превратит его в stub unreliable (провайдер молчит,
# а не «согласен»).
#
# Вход — переменные окружения:
#   CODEX_OUT FABLE_OUT            сырые stdout-файлы верификаторов
#   MERGED_OUT VERDICT_MD          куда положить merged JSON и rendered markdown
#   JSON_MODE                      1 → печатать merged JSON вместо рендера
#   PROMPT_FILE CLAUDE_SCHEMA_FILE опц., удаляются в конце
set -euo pipefail

# ${CLAUDE_PLUGIN_ROOT} в Bash НЕ подставляется — резолвим корень скилла от самого скрипта.
VERIFIER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Временные файлы нормализации — убрать при любом выходе (раньше копились в $TMPDIR)
TMP_FILES=()
cleanup() { rm -f "${TMP_FILES[@]:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Срезать мусорные префиксы CLI (warning-строки до JSON): взять с первой строки, начинающейся с {
# Отсутствующий/пустой файл — не ошибка, а «ветка не ответила»: отдаём пусто, ниже станет '{}'.
strip_preamble() { [[ -s "$1" ]] && sed -n '/^{/,$p' "$1" || true; }

CODEX_VERDICT=$(mktemp -t verif-codex-verdict.XXXXXX.json)

TMP_FILES+=("$CODEX_VERDICT")
if [[ -s "$CODEX_OUT" ]] && jq -e '.verdict' "$CODEX_OUT" >/dev/null 2>&1; then
  jq . "$CODEX_OUT" > "$CODEX_VERDICT"
elif [[ -s "$CODEX_OUT" ]] && tail -1 "$CODEX_OUT" | jq -e '.verdict' >/dev/null 2>&1; then
  tail -1 "$CODEX_OUT" > "$CODEX_VERDICT"
elif [[ -s "$CODEX_OUT" ]] && python3 -c '
# GPT-6 Astra (2026-09-05) печатает финальный verdict МНОГОСТРОЧНЫМ JSON после лога прогона,
# а не одной последней строкой, как GPT-5.6 Sol: обе ступени выше дают FAIL и verdict молча
# превращался в stub unreliable. Сканируем с конца файла и берём последний валидный объект
# с полем verdict.
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
dec = json.JSONDecoder()
for i in range(len(raw) - 1, -1, -1):
    if raw[i] != "{":
        continue
    try:
        obj, _ = dec.raw_decode(raw[i:])
    except Exception:
        continue
    if isinstance(obj, dict) and obj.get("verdict"):
        json.dump(obj, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
        sys.exit(0)
sys.exit(1)
' "$CODEX_OUT" "$CODEX_VERDICT" 2>/dev/null; then
  :
else
  echo '{}' > "$CODEX_VERDICT"
fi

FABLE_ENV=$(mktemp -t verif-fable-env.XXXXXX.json)

TMP_FILES+=("$FABLE_ENV")
strip_preamble "$FABLE_OUT" > "$FABLE_ENV"
FABLE_VERDICT=$(mktemp -t verif-fable-verdict.XXXXXX.json)
TMP_FILES+=("$FABLE_VERDICT")
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

bash "$VERIFIER_ROOT/scripts/merge_verdicts.sh" "${MERGE_ARGS[@]}" > "$MERGED_OUT"

# Один рендер: на диск всегда, на stdout — если не JSON-режим
if [[ "${JSON_MODE:-0}" == "1" ]]; then
  bash "$VERIFIER_ROOT/scripts/render_merged.sh" "$MERGED_OUT" > "$VERDICT_MD"
  cat "$MERGED_OUT"
else
  bash "$VERIFIER_ROOT/scripts/render_merged.sh" "$MERGED_OUT" | tee "$VERDICT_MD"
fi

rm -f "${PROMPT_FILE:-}" "${CLAUDE_SCHEMA_FILE:-}" 2>/dev/null || true
