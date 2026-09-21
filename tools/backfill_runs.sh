#!/usr/bin/env bash
# backfill_runs.sh — РАЗОВЫЙ скрипт: собрать журнал `_runs.jsonl` из артефактов, которые уже
# лежат в <vault>/AI/verif, чтобы у релиза 3.1.0 была базовая линия для сравнения.
#
# Не часть рантайма скилла: живёт в tools/, зовётся руками один раз. Дальше журнал ведёт
# `skills/verif/scripts/log_run.sh` из самого прогона.
#
# Usage:
#   tools/backfill_runs.sh [--persist-dir <dir>] [--out <file>] [--dry-run] [--force]
#
#   --persist-dir  каталог артефактов (по умолчанию $VAULT_PATH/AI/verif, иначе ~/Jadlis/AI/verif)
#   --out          куда писать (по умолчанию <persist-dir>/_runs.jsonl)
#   --dry-run      показать список запусков и выйти, ничего не записав
#   --force        писать, даже если файл журнала уже существует (дубликаты на твоей совести)
#
# Что восстановимо и что нет:
#   ЕСТЬ   — дата, покрытие и выпавшие ветки (по заглушкам merged), вердикт, подано по ветке,
#            дубликаты, принято / отклонено, уникальные принятые, по тяжести, решения арбитра
#            и перевороты, цель находок.
#   НЕТ    — время интервью и машинной части (никто не мерил), режим интервью, пины моделей,
#            круги доправок и кто перепроверял: до 3.1.0 этого не существовало. Всё это `null`,
#            а не ноль. Каждая строка помечена `"backfilled": true`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_RUN="$(cd "$SCRIPT_DIR/.." && pwd)/skills/verif/scripts/log_run.sh"

PERSIST_DIR=""
OUT=""
DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --persist-dir) PERSIST_DIR="$2"; shift 2 ;;
    --out)         OUT="$2";         shift 2 ;;
    --dry-run)     DRY_RUN=1;        shift ;;
    --force)       FORCE=1;          shift ;;
    *) echo "Unknown argument: $1" >&2; exit 64 ;;
  esac
done

if [[ -z "$PERSIST_DIR" ]]; then
  PERSIST_DIR="${VAULT_PATH:-$HOME/Jadlis}/AI/verif"
fi
[[ -d "$PERSIST_DIR" ]] || { echo "No such directory: $PERSIST_DIR" >&2; exit 66; }
[[ -x "$LOG_RUN" || -f "$LOG_RUN" ]] || { echo "log_run.sh not found at $LOG_RUN" >&2; exit 66; }

: "${OUT:=$PERSIST_DIR/_runs.jsonl}"

if [[ -s "$OUT" && "$FORCE" == 0 && "$DRY_RUN" == 0 ]]; then
  echo "Журнал уже существует и не пуст: $OUT" >&2
  echo "Обратная заливка запускается один раз. Нужно всё равно — --force." >&2
  exit 65
fi

# Базы прогонов: имя файла без последнего сегмента «--<что-то>.<ext>».
# Служебные файлы аудита (`_all_findings.json` и прочие на подчёркивание) не трогаем.
BASES=$(
  for f in "$PERSIST_DIR"/*.json "$PERSIST_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    name=$(basename "$f")
    # Без `case`: bash 3.2 (системный на macOS) ломается о `)` шаблона внутри $( … ).
    if [[ "$name" == _* ]]; then continue; fi
    if [[ "$name" != *--* ]]; then continue; fi
    printf '%s\n' "${name%--*}"
  done | sort -u
)

COUNT=0
SKIPPED=0
FAILED=0
# Через read, а не `for base in $BASES`: имена баз бывают кириллическими и длинными,
# и разбиение по IFS тут не нужно.
while IFS= read -r base; do
  [[ -n "$base" ]] || continue
  # Настоящий прогон — тот, у кого есть хотя бы один артефакт вердикта или разбора.
  HAS=0
  for part in merged codex fable opus grok findings decisions arbiter; do
    if [[ -e "$PERSIST_DIR/${base}--${part}.json" ]]; then HAS=1; break; fi
  done
  if [[ "$HAS" == 0 ]]; then
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  # Цель восстанавливаем из находок: самый частый непустой `file`.
  TARGET=""
  if [[ -s "$PERSIST_DIR/${base}--findings.json" ]]; then
    TARGET=$(jq -r '[.[]? | .file // empty] | group_by(.) | max_by(length) | .[0] // empty' \
      "$PERSIST_DIR/${base}--findings.json" 2>/dev/null || true)
  fi

  if [[ "$DRY_RUN" == 1 ]]; then
    printf '%s\t%s\n' "$base" "${TARGET:-—}"
    COUNT=$((COUNT+1))
    continue
  fi

  ARGS=(--persist-dir "$PERSIST_DIR" --base "$base" --backfilled --out "$OUT"
        --times "$PERSIST_DIR/${base}--no-such-times")
  if [[ -n "$TARGET" ]]; then ARGS+=(--target "$TARGET"); fi
  if bash "$LOG_RUN" "${ARGS[@]}" > /dev/null; then
    COUNT=$((COUNT+1))
  else
    echo "⚠ не удалось собрать строку: $base" >&2
    FAILED=$((FAILED+1))
  fi
done <<< "$BASES"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "— dry-run: $COUNT запусков к заливке, $SKIPPED баз пропущено (нет артефактов прогона)"
else
  echo "Залито строк: $COUNT (пропущено баз без артефактов: $SKIPPED, сорвалось: $FAILED) → $OUT"
fi
