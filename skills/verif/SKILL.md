---
name: verif
description: "Dual adversarial verification of a plan/research/doc: Codex + Fable in parallel, arbiter merge, batch interview, fixes, re-check of the fixes. Flags: --only codex|fable, --report-only, --no-recheck, --json. Triggers: /verif, verify plan, adversarial review, fact-check. RU triggers: верифицируй план, проверь план, проверь ресерч на факты, фактчек документа. Do NOT use for: code → /code-review; research → /full-research."
argument-hint: "[focus] [--file <path>] [--type plan|research|doc] [--only codex|fable] [--report-only] [--no-recheck] [--json]"
allowed-tools: Read, Glob, Write, Edit, MultiEdit, AskUserQuestion, Task, Agent, Bash(codex:*), Bash(claude:*), Bash(mktemp:*), Bash(cat:*), Bash(ls:*), Bash(jq:*), Bash(rm:*), Bash(trap:*), Bash(grep:*), Bash(echo:*), Bash(ln:*), Bash(bash:*), Bash(test:*), Bash(chmod:*), Bash(mkdir:*), Bash(date:*), Bash(sed:*), Bash(wc:*), Bash(stat:*), Bash(cp:*), Bash(diff:*), Bash(shasum:*), Bash(awk:*), Bash(tr:*), Bash(printf:*), Bash(python3:*)
---

# /verif — Dual adversarial верификация (Codex + Fable 5) с арбитром

Тонкий orchestrator двух независимых верификаторов: OpenAI GPT-6 Astra через `codex exec`, Anthropic Claude Fable 5 через `claude -p` (headless). Оба возвращают JSON по единой `schema/verdict.json`. Результаты сливаются через `scripts/merge_verdicts.sh` (strict hierarchy: unreliable > needs-revision > approve, N провайдеров с метками) и рендерятся через `scripts/render_merged.sh`.

Provider-agnostic policy — `${CLAUDE_PLUGIN_DATA}/verif-homes/codex-home/AGENTS.md` для Codex, `system-prompts/fable-verifier.md` для Fable (codex-home разворачивается из `${CLAUDE_PLUGIN_ROOT}/assets/verif-homes/` при первом запуске). Templates — `prompts/{plan,research,doc}.md`.

**Архитектура v6 (v6.1 — интервью простым языком: арбитр отдаёт `plain.*`, вопросы строятся по `references/plain-language.md`; v7 — развилка режима интервью «авто / вручную» перед первым батчем; v8 — статус покрытия вместо заглушки, Фаза C и журнал запусков):** single-turn запуск, два параллельных `Bash(run_in_background: true)`. Completion notification приходит независимо для каждого — скилл показывает результат каждого завершившегося верификатора сразу (стриминг). После merge — **этап Арбитра**: headless Fable 5 (high) судит дедуплицированные находки в контексте целевого файла, кросс-чекает провайдеров и помечает опровергнутые. Затем Фаза A: батч-интервью по находкам с рекомендациями арбитра (сначала развилка «авто / вручную»), Фаза B: параллельное применение одобренных правок субагентами (один файл = один субагент), Фаза C: один ограниченный проход Codex по диффу правок. Каждый прогон дописывает строку в журнал `AI/verif/_runs.jsonl`.

> **Оговорка о направлении ревью (KDD'26, arXiv 2607.21656, 116 задач):** в чистой паре «писатель→ревьюер» ревью Codex работ Claude РОНЯЛО pass rate 91,4%→82,8% (обратное направление поднимало 71,6%→89,7%; модели прошлого поколения, ревьюер не запускал тесты). Наш пайплайн от этого защищён арбитром-Fable — поэтому вердиктам одного Codex (`--only codex`) по Claude-артефактам без арбитра не доверять слепо; при расхождении провайдеров вес у арбитра. Перенос выводов на Opus 5/Fable 5 не проверен — свой A/B при случае.

## Аргументы

`$ARGUMENTS`

- `--file <path>` — путь к файлу для верификации.
- `--type plan|research|doc` — тип файла (если не указан — определи автоматически).
- `--only codex|fable` — запустить только один верификатор. По умолчанию — оба параллельно. Арбитр, интервью и применение не запускаются.
- `--report-only` — вывести merged-отчёт и остановиться (без арбитра, интервью и применения).
- `--no-recheck` — не запускать Фазу C: правки применяются и не перепроверяются. Снимки файлов тоже не делаются.
- `--json` — вернуть полный merged JSON (без арбитра, интервью и применения).
- Остальной текст — фокус верификации.

## Шаг 1: Найти файл

Приоритет:
1. `--file <path>` если передан.
2. Путь в аргументах (содержит `/` или `.md`).
3. Самый свежий план: `ls -t ".claude/plans/"*.md 2>/dev/null | head -1`.
4. Самый свежий plan-mode файл: `ls -t "$HOME/.claude/projects/*/plans/"*.md 2>/dev/null | head -1`.

Файл не найден — сообщить пользователю и остановиться.

## Шаг 2: Прочитать и определить тип

Read target. Если `--type` не указан:
- **plan** — Context, Evidence, Steps, Implementation.
- **research** — findings, сравнения, recommendations.
- **doc** — version numbers, CLI commands, URLs.

## Шаг 3: Режим выполнения

- **Default (dual):** Codex + Fable параллельно (два `Bash(run_in_background: true)`
  в одном сообщении) → notifications → merge + render → Арбитр → Фаза A → Фаза B → Фаза C → журнал.
- **`--only codex|fable`:** соответствующий Bash в одиночку, рендер single-verifier
  (Шаг 7), без арбитра, интервью и Фазы C.
- **Сбой одной ветки** merge поддерживает штатно: сначала **один перезапуск той же ветки**
  (см. «Обработка notifications»), и только если и он пуст — ветка уходит в `dropped`,
  консенсус считается по выжившей, покрытие становится `partial`, а approve запрещён
  (см. «Ошибки и fallbacks»).

## Шаг 4: Synchronous prelude — подготовка

Один foreground Bash-вызов. Подготовить все переменные, промпт, output paths.

```bash
set -euo pipefail
VERIFIER_ROOT="${CLAUDE_PLUGIN_ROOT}/skills/verif"
# Рабочие homes живут в PLUGIN_DATA, а НЕ в PLUGIN_ROOT: root меняется при каждом
# обновлении плагина, а homes копят сессии и кэш на сотни МБ. Шаблоны (AGENTS.md,
# config.toml) едут в плагине как assets и разворачиваются сюда при первом запуске.
VERIF_HOMES="${CLAUDE_PLUGIN_DATA}/verif-homes"
VERIF_HOMES_TEMPLATE="${CLAUDE_PLUGIN_ROOT}/assets/verif-homes"
CODEX_HOME_DIR="$VERIF_HOMES/codex-home"

# First-run deploy шаблонов (идемпотентно: существующие файлы не перетираем)
# ⚠️ Обратная сторона идемпотентности: при СМЕНЕ МОДЕЛИ рабочая копия
# `$CODEX_HOME_DIR/config.toml` НЕ обновляется — ни этим блоком, ни рендером
# личного контура. Иначе скилл утверждает одно, а config говорит другое.
# После правки `CODEX_MODEL` всегда руками:
#   cp "$VERIF_HOMES_TEMPLATE/codex-home/config.toml" "$CODEX_HOME_DIR/config.toml"
mkdir -p "$CODEX_HOME_DIR"
for f in AGENTS.md config.toml; do
  [[ -e "$CODEX_HOME_DIR/$f" ]] || cp "$VERIF_HOMES_TEMPLATE/codex-home/$f" "$CODEX_HOME_DIR/$f"
done
SCHEMA_PATH="$VERIFIER_ROOT/schema/verdict.json"
ARBITER_SCHEMA_PATH="$VERIFIER_ROOT/schema/arbiter.json"
DELTA_SCHEMA_PATH="$VERIFIER_ROOT/schema/delta.json"      # Фаза C; запрещённых для claude ключей не содержит — производную делать не нужно
BUILD_PROMPT="$VERIFIER_ROOT/scripts/build_prompt.sh"
LOG_RUN="$VERIFIER_ROOT/scripts/log_run.sh"
FABLE_SYSTEM_PROMPT="$VERIFIER_ROOT/system-prompts/fable-verifier.md"
ARBITER_SYSTEM_PROMPT="$VERIFIER_ROOT/system-prompts/arbiter.md"
DELTA_SYSTEM_PROMPT="$VERIFIER_ROOT/system-prompts/delta-check.md"
PLAIN_RULES="$VERIFIER_ROOT/references/plain-language.md"   # правила простого языка: дописываются в system prompt арбитра, читаются главным тредом для интервью/«Коротко»

# First-run symlinks (safe no-op если существуют)
if [[ ! -e "$CODEX_HOME_DIR/auth.json" ]]; then
  ln -s "$HOME/.codex/auth.json" "$CODEX_HOME_DIR/auth.json"
fi

# Hardcoded settings
EFFORT_CODEX="high"
EFFORT_FABLE="high"
CODEX_MODEL="gpt-6-astra"   # GPT-6 Astra с 05.09.2026; effort `high` с 06.09.2026 по ресёрчу «Effort для плана и кода» (выше high растут токены, не качество); `ultra` = авто-делегирование, не нужен; откат = `gpt-5.6-sol` (в каталоге жив)

# Выбор Fable-модели: Fable 5.1 — 1M-контекст нативно, big-file guard снят 01.09.2026.
FABLE_MODEL_PRIMARY="claude-fable-5-1"
FABLE_MODEL_FALLBACK="claude-opus-5"
FABLE_MODEL="$FABLE_MODEL_PRIMARY"

# Claude-совместимая производная схема: structured outputs Anthropic не поддерживает
# minLength/minimum/maximum и мета-ключи корня ($schema/$id/title/description) — с ними
# claude -p ТИХО не заполняет .structured_output (проверено смоуком 2026-07-02).
# verdict.json остаётся канонической для codex (--output-schema).
CLAUDE_SCHEMA_FILE=$(mktemp -t verif-claude-schema.XXXXXX.json)
jq 'walk(if type == "object" then del(.minLength, .minimum, .maximum) else . end)
    | del(."$schema", ."$id", .title, .description)' "$SCHEMA_PATH" > "$CLAUDE_SCHEMA_FILE"

# Prompt file (temp)
PROMPT_FILE=$(mktemp -t verif-prompt.XXXXXX)
bash "$BUILD_PROMPT" --type "$TYPE" --file "$ABSOLUTE_PATH" --focus "$USER_FOCUS" > "$PROMPT_FILE"

# Persistence paths
VAULT_DIR="${user_config.VAULT_PATH}"
PERSIST_DIR="$VAULT_DIR/AI/verif"
mkdir -p "$PERSIST_DIR"

DATE=$(date +%Y-%m-%d)
# Slug: filename without extension, transliterated
SLUG=$(basename "$ABSOLUTE_PATH" .md | sed -e 's/[[:space:]]/-/g' -e 's/[^a-zA-Z0-9а-яА-ЯёЁ_-]//g' | tr '[:upper:]' '[:lower:]')
[[ -z "$SLUG" ]] && SLUG="unnamed"

# Collision avoidance
BASE="${DATE}--${SLUG}"
if [[ -e "$PERSIST_DIR/${BASE}--codex.json" || -e "$PERSIST_DIR/${BASE}--fable.json" ]]; then
  V=2
  while [[ -e "$PERSIST_DIR/${BASE}-v${V}--codex.json" || -e "$PERSIST_DIR/${BASE}-v${V}--fable.json" ]]; do
    V=$((V+1))
  done
  BASE="${BASE}-v${V}"
fi

CODEX_OUT="$PERSIST_DIR/${BASE}--codex.json"
FABLE_OUT="$PERSIST_DIR/${BASE}--fable.json"
MERGED_OUT="$PERSIST_DIR/${BASE}--merged.json"
VERDICT_MD="$PERSIST_DIR/${BASE}--verdict.md"
FINDINGS_OUT="$PERSIST_DIR/${BASE}--findings.json"
ARBITER_OUT="$PERSIST_DIR/${BASE}--arbiter.json"
DECISIONS_OUT="$PERSIST_DIR/${BASE}--decisions.json"
DELTA_OUT="$PERSIST_DIR/${BASE}--delta.json"

# Метки времени для журнала. Рабочий файл, а не переменная: границы интервью ставятся
# в других Bash-вызовах, а состояние между ними не переживает. log_run.sh удаляет его сам.
RUN_TIMES="$PERSIST_DIR/${BASE}--run.times"
echo "prelude=$(date +%s)" > "$RUN_TIMES"

echo "VERIF_PATHS:"
echo "  PROMPT_FILE=$PROMPT_FILE"
echo "  CLAUDE_SCHEMA_FILE=$CLAUDE_SCHEMA_FILE"
echo "  TARGET_PATH=$ABSOLUTE_PATH"
echo "  TARGET_BYTES=$TARGET_BYTES"
echo "  CODEX_OUT=$CODEX_OUT"
echo "  FABLE_OUT=$FABLE_OUT"
echo "  MERGED_OUT=$MERGED_OUT"
echo "  VERDICT_MD=$VERDICT_MD"
echo "  FINDINGS_OUT=$FINDINGS_OUT"
echo "  ARBITER_OUT=$ARBITER_OUT"
echo "  DECISIONS_OUT=$DECISIONS_OUT"
echo "  DELTA_OUT=$DELTA_OUT"
echo "  RUN_TIMES=$RUN_TIMES"
echo "  EFFORT_CODEX=$EFFORT_CODEX"
echo "  EFFORT_FABLE=$EFFORT_FABLE"
echo "  FABLE_MODEL=$FABLE_MODEL"
echo "  CODEX_MODEL=$CODEX_MODEL"
# Одной строкой — пин моделей и effort: видно в логе прогона, проверяется тестом TESTS.md
echo "  MODELS=$FABLE_MODEL / $CODEX_MODEL / $EFFORT_FABLE / $EFFORT_CODEX"
echo "  SCHEMA_PATH=$SCHEMA_PATH"
echo "  ARBITER_SCHEMA_PATH=$ARBITER_SCHEMA_PATH"
echo "  DELTA_SCHEMA_PATH=$DELTA_SCHEMA_PATH"
echo "  CODEX_HOME_DIR=$CODEX_HOME_DIR"
echo "  FABLE_SYSTEM_PROMPT=$FABLE_SYSTEM_PROMPT"
echo "  ARBITER_SYSTEM_PROMPT=$ARBITER_SYSTEM_PROMPT"
echo "  DELTA_SYSTEM_PROMPT=$DELTA_SYSTEM_PROMPT"
echo "  LOG_RUN=$LOG_RUN"
echo "  PLAIN_RULES=$PLAIN_RULES"
```

## Шаг 5: Запуск верификаторов через Bash(run_in_background)

Два `Bash(run_in_background: true)` вызова — в **одном сообщении**, иначе они выполнятся последовательно и прогон растянется вдвое. При `--only` — один Bash.

Каждый Bash — фоновый процесс с отдельным completion notification. В системе нет команды `timeout` — предельное время задаёт timeout самого Bash-инструмента (600000 мс на вызов).

### Bash A: Codex (run_in_background: true, timeout: 600000)

```bash
CODEX_HOME="{CODEX_HOME_DIR}" codex exec \
  -m "{CODEX_MODEL}" \
  --sandbox read-only \
  --skip-git-repo-check \
  --output-schema "{SCHEMA_PATH}" \
  -c model_reasoning_effort="{EFFORT_CODEX}" \
  -c service_tier="default" \
  - < "{PROMPT_FILE}" > "{CODEX_OUT}" 2>&1
```

Плейсхолдеры `{CODEX_MODEL}` / `{EFFORT_CODEX}` / `{EFFORT_FABLE}` / `{FABLE_MODEL}` подставляются из `VERIF_PATHS` prelude — литералы в Bash A/B не дублировать. `service_tier="default"` — в плагине стандартный тир; локальный пин `priority` (−15 % латентности, 15.08) — личная настройка получателя, в дистрибутив не входит.

### Bash B: Fable (run_in_background: true, timeout: 600000)

```bash
claude -p "$(cat "{PROMPT_FILE}")" \
  --model "{FABLE_MODEL}" \
  --effort {EFFORT_FABLE} \
  --output-format json \
  --json-schema "$(cat "{CLAUDE_SCHEMA_FILE}")" \
  --append-system-prompt "$(cat "{FABLE_SYSTEM_PROMPT}")" \
  --allowedTools "Read,Grep,Glob,mcp__plugin_jadlis-search_brave-search__brave_web_search,mcp__plugin_jadlis-search_firecrawl__firecrawl_scrape" \
  < /dev/null > "{FABLE_OUT}" 2>&1
```

`< /dev/null` обязателен: без него фоновый `claude -p` ждёт stdin и печатает warning-строку ПЕРЕД JSON-envelope — ломает парсинг (источник нулевых прогонов v5).

Сообщи пользователю: "Верификаторы запущены параллельно (Codex GPT-6 Astra + Fable 5). Результаты будут появляться по мере завершения..."

### Обработка notifications

При каждом notification:
1. Определить какой верификатор завершился (по тексту notification — он содержит команду и путь output файла).
2. Прочитать output файл, нормализовать (см. Шаг 6), отрендерить single verdict через jq.
3. Показать: `"✓ {Codex|Fable} завершён. Ожидание остальных..."`
4. **Ветка не дала вердикта** (exit != 0, пустой файл, каскад Шага 6 ничего не извлёк) —
   **один перезапуск той же ветки тем же вызовом** (тот же Bash A/B, тот же промпт, вывод в тот
   же файл), с сообщением «{Codex|Fable} не ответил — перезапускаю один раз». Второй раз пусто —
   перезапусков больше нет, ветка уходит в `dropped` на Шаге 6. Перезапускаем **то же место, а
   не другое семейство**: по ресёрчу («Состязательная верификация», раздел «Покрытие и повторные
   прогоны») повторный прогон того же проверяющего добавляет покрытия, а подмена семейства — нет.

Когда обе ветки закончили (с учётом перезапуска) → Шаг 6.

## Шаг 6: Нормализация + Merge + Render + Save

Один Bash-вызов. Каскады разбора ответов обоих CLI (форма verdict у каждого своя и менялась
между версиями) живут в скрипте — там же объяснено, почему каскад обязателен:

```bash
CODEX_OUT="$CODEX_OUT" FABLE_OUT="$FABLE_OUT" JSON_MODE="$JSON_MODE" \
MERGED_OUT="$MERGED_OUT" VERDICT_MD="$VERDICT_MD" \
PROMPT_FILE="$PROMPT_FILE" CLAUDE_SCHEMA_FILE="$CLAUDE_SCHEMA_FILE" \
bash "${CLAUDE_PLUGIN_ROOT}/skills/verif/scripts/normalize_and_merge.sh"
```

Нераспознанный ответ провайдера становится `{}` → merge помечает его stub unreliable
(провайдер молчит, а не «согласен») И заносит метку в `consensus.dropped`: такая ветка не
голосует, консенсус считается по ответившим, `consensus.coverage` становится `partial`, а
`consensus.status` поднимает approve до needs-revision. Рендер печатает строку «ПОКРЫТИЕ».

## Шаг 7: Отчёт и развилка

Сначала — блок «Коротко» (3–5 строк для человека, по правилам `references/plain-language.md`; прочитать файл, если ещё не читал в этой сессии), затем rendered verdict как есть (не перефразируй и не резюмируй) и пути к артефактам.

Блок «Коротко» строится из `$MERGED_OUT`:

```
Коротко: {нужны правки | можно делать | план ненадёжен} — {N} сырых находок от {k} проверяющих (до склейки дубликатов), из них {M} серьёзных (critical/high).
1. {самая серьёзная находка одной строкой, простыми словами — что не так и что сломается}
2. {вторая}
3. {третья}
```

`consensus.verdict` → «нужны правки» (needs-revision) / «можно делать» (approve) / «план ненадёжен» (unreliable). `N` — сумма `findings` всех веток merged; это число честно названо «сырым»: дедуп делается позже в Arb-1, и точное число проблем = число вопросов интервью. Три строки — по убыванию severity из объединённых findings; если две ветки явно описывают одну и ту же проблему — показать её один раз; при < 3 находок — сколько есть; при 0 — «Проблем не нашли». Только пересказ `title`/`body` находок, без новых фактов. Строка деградации — из состояния пайплайна, не из merged: stub-провайдер в merged (`⚠ СБОЙ` в рендере) → «Не участвовал: {провайдер} (сбой — ответ не JSON, перезапуск не помог)»; ветка не запускалась (`⚠ НЕ УЧАСТВОВАЛ` в рендере) → «Не участвовал: {провайдер} (обрыв — {что видел: пустой ответ / exit≠0 / таймаут})». При `consensus.coverage = "partial"` первой строкой «Коротко» идёт «Покрытие частичное: проверял только {выжившая ветка} — вердикт не финальный».

Rendered verdict и пути:

```
Артефакты сохранены:
- Codex verdict:  AI/verif/{BASE}--codex.json
- Fable verdict:  AI/verif/{BASE}--fable.json
- Merged:         AI/verif/{BASE}--merged.json
- Summary:        AI/verif/{BASE}--verdict.md
```

Затем развилка:

На этом работа заканчивается (арбитр и интервью не запускаются):
- **`--json`** — выведен полный merged JSON;
- **`--report-only`** — выведен rendered verdict;
- **`--only codex|fable`** — single-verifier рендер (см. ниже).
- **Иначе (default dual)** — merged-вердикт уже показан (UX не ждёт арбитра); перейти к этапу Арбитра.

### Single-verifier режимы

Вердикт рендерится напрямую, без merge. Codex отдаёт готовый JSON; Fable сначала
прогнать через тот же каскад извлечения, что и в Шаге 6 (`.structured_output` →
`.result | fromjson` → ```json-fence); каскад целиком — в
`scripts/normalize_and_merge.sh`.

```bash
# Direct single-verifier render (без merge)
jq -r '
  "VERDICT: \(.verdict | ascii_upcase)\n" +
  "SUMMARY: \(.summary)\n" +
  "FINDINGS (\(.findings | length)):\n" +
  ((.findings // [])
    | map("  [\(.severity | ascii_upcase)] \(.title) (\(.category), \(.claim_type))"
          + (if .file then " — \(.file)" + (if .line_start then ":\(.line_start)" else "" end) else "" end))
    | (if length == 0 then ["  (none)"] else . end)
    | join("\n")) +
  "\n\nNEXT STEPS:\n" +
  ((.next_steps // [])
    | (if length == 0 then ["  (none)"] else map("  - " + .) end)
    | join("\n"))
' "$SINGLE_VERDICT"
```

## Этап Арбитр

Только в default-режиме (без `--json` / `--report-only` / `--only`). Merged-вердикт пользователю уже показан — арбитр работает после, не блокируя вывод.

### Arb-1. Дедуп и findings.json

1. Прочитать `$MERGED_OUT`. Собрать findings обеих веток (`.codex.findings`, `.fable.findings`), каждую пометить source-меткой провайдера.
2. Дедуп между ветками: если у находок одинаковый целевой файл (`file`; `null` считается равным TARGET_PATH) И смысловое совпадение title/body (одна и та же проблема, пусть в разных формулировках) — слить в одну: `sources` = массив всех провайдеров-источников, severity = максимум, recommendation объединить (формулировки через « / » если различаются). **При сомнении — НЕ сливать**: два отдельных вопроса дешевле ложного слияния.
3. Отсортировать: critical → high → medium → low. Присвоить стабильные id в порядке сортировки: `F1`, `F2`, …
4. Записать (Write) `$FINDINGS_OUT` — массив объектов: `{id, title, body, severity, confidence, claim_type, recommendation, evidence_urls, sources, file, line_start, line_end}`.
5. **0 находок** → пропустить Арбитра и Фазы A/B. Сообщить: «Все ветки без findings — применять нечего». Конец.

### Arb-2. Headless-вызов арбитра (run_in_background: true, timeout: 600000)

**Анонимизация провайдеров** (family-bias: арбитр-Fable систематически переоценивает находки Fable; подтверждено ресерчем): выбери случайный маппинг провайдеров на метки `Verifier A/B`, запомни его для деанонимизации в интервью. В промпте арбитра все упоминания провайдеров (summaries и `sources` находок) заменить на анонимные метки; `$FINDINGS_OUT` на диске остаётся с реальными именами.

Сборка промпта: Write во временный файл `ARBITER_PROMPT_FILE` (mktemp) с содержимым:

```
TARGET FILE: {TARGET_PATH}

VERIFIER VERDICT SUMMARIES (anonymized):
- Verifier A: {verdict} — {summary}
- Verifier B: {verdict} — {summary}

FINDINGS TO JUDGE (deduplicated; sources anonymized to A/B):
{содержимое $FINDINGS_OUT с sources → метки}

Judge each finding per your role instructions. Return one assessment per finding id.
```

Запуск (арбитр наследует резолвнутую Fable-модель):

```bash
claude -p "$(cat "{ARBITER_PROMPT_FILE}")" \
  --model "{FABLE_MODEL}" \
  --effort {EFFORT_FABLE} \
  --output-format json \
  --json-schema "$(cat "{ARBITER_SCHEMA_PATH}")" \
  --append-system-prompt "$(cat "{ARBITER_SYSTEM_PROMPT}" "{PLAIN_RULES}")" \
  --allowedTools "Read,Grep,Glob" \
  < /dev/null > "{ARBITER_OUT}.raw" 2>&1
```

Сообщи: "Арбитр (Fable 5) оценивает {N} находок..."

`{PLAIN_RULES}` дописывается вторым файлом в system prompt: арбитр заполняет `plain.*` (шесть полей для человека) по тем же правилам, по которым главный тред строит вопросы интервью. `plain` намеренно не в `required` схемы: если арбитр его не заполнил у какого-то id — судейство этого id берётся, plain-поля дописывает главный тред (частичный fallback в `interview-apply.md`).

### Arb-3. Нормализация и деградация

После notification:

```bash
# Извлечь structured_output (с очисткой префиксов) → перезаписать $ARBITER_OUT чистым объектом оценок
ARB_ENV=$(mktemp -t verif-arb-env.XXXXXX.json)
sed -n '/^{/,$p' "{ARBITER_OUT}.raw" > "$ARB_ENV"
if jq -e '.structured_output.assessments' "$ARB_ENV" >/dev/null 2>&1; then
  jq '.structured_output' "$ARB_ENV" > "{ARBITER_OUT}"
  rm -f "{ARBITER_OUT}.raw"
else
  ARBITER_AVAILABLE=0   # (после одного foreground retry)
fi
```

- Сбой (exit != 0 / нет `.structured_output.assessments`) → **один foreground retry**; при повторном сбое `ARBITER_AVAILABLE=0` — интервью идёт по эвристике A3-fallback (главный тред сам пишет plain-поля по `plain-language.md`), пайплайн жив. Сообщи пользователю по-русски и просто: «Арбитр не ответил — вопросы будут без его оценки».
- Рассинхрон id: оценки с id, которых нет в findings.json — игнорировать; findings без оценки — обрабатывать по эвристике A3-fallback.

## Фазы A и B: интервью по находкам и применение правок

Только в default-режиме, после арбитра. Сначала развилка режима (один AskUserQuestion,
header «Режим»): **авто** — решения арбитра применяются сразу, вопросы только по сильным
развилкам, не больше четырёх; **вручную** — каждая находка отдельным вопросом, батчами до 4,
как раньше. Развилка показывается, только если арбитр доступен и покрыл находки; иначе
молча идём вручную и говорим об этом одной строкой. Вся фактура находки живёт ВНУТРИ
`question` (5 строк обычного текста, без разметки; сегменты «Цена» и «Риск» выбрасываются,
если в материале их нет) — отдельных сообщений перед вопросами не печатать.
Спека режимов, шаблон вопроса, guard против галлюцинаций, процедурное правило развилок
авто-режима и выборочная проверка, фиксация решений (`decided_by`, `auto_low_confidence`,
`why_asked`) и параллельное применение субагентами —
`@${CLAUDE_PLUGIN_ROOT}/skills/verif/references/interview-apply.md`.

Перед интервью и после него поставить метки времени для журнала:

```bash
echo "machine_done=$(date +%s)" >> "$RUN_TIMES"    # сразу после этапа Арбитра
echo "interview_start=$(date +%s)" >> "$RUN_TIMES" # перед первым AskUserQuestion
echo "interview_done=$(date +%s)" >> "$RUN_TIMES"  # после A4, до Фазы B
```

## Фаза C: перепроверка правок

Только после Фазы B и только если в ней что-то применено. Один ограниченный проход **Codex** по
диффу правок (другое семейство, чем у субагентов-исправителей), три вопроса — закрыта ли каждая
находка, не сломано ли соседнее, не вырос ли объём; `MAX_FIX_ROUNDS = 2`. Codex недоступен —
откат на Fable headless (`delta_by: fable`). Пропуск: нет принятых находок, `--report-only`,
`--json`, `--only`, `--no-recheck`.

Снимки файлов (C0), сборка диффа и замороженного списка, промпт, вызовы, круг доправок,
артефакт `$DELTA_OUT` и строка сводки —
`@${CLAUDE_PLUGIN_ROOT}/skills/verif/references/delta-recheck.md`.

## Журнал запуска

Последним шагом любого default-прогона — один foreground вызов. Строку собирает скрипт из
артефактов; числа из сводки в него не переписывать и журнал руками не редактировать.

```bash
bash "$LOG_RUN" \
  --persist-dir "$PERSIST_DIR" --base "$BASE" \
  --target "$ABSOLUTE_PATH" --type "$TYPE" \
  --models "$(jq -nc --arg c "$CODEX_MODEL" --arg f "$FABLE_MODEL" \
                     --arg ec "$EFFORT_CODEX" --arg ef "$EFFORT_FABLE" \
                     '{codex:$c, fable:$f, effort_codex:$ec, effort_fable:$ef}')" \
  --mode "{auto|manual}" --delta-by "{codex|fable|none|skipped}" --fix-rounds "{0|1|2}"
```

Дозапись в `AI/verif/_runs.jsonl`, одна строка на прогон. Сводка по журналу —
`bash "$VERIFIER_ROOT/scripts/verif_stats.sh"` (путь берётся из `VAULT_PATH` или аргументом).

## Ошибки и fallbacks

- **Background Bash exit != 0** — notification содержит exit code. Прочитать output файл для диагностики. `merge_verdicts.sh` увидит невалидный JSON → `unreliable` stub. Покажи пользователю tail stderr + диагностику CLI: `codex login status` (auth) и `codex exec -m gpt-6-astra "ping" < /dev/null` (живость модели).
- **Fable: цепочка моделей** `claude-fable-5-1` → `claude-opus-5`. Переключение вниз: (а) unknown model / модель отвергнута; (б) context-overflow post-run (ошибка про превышение контекста в output) → перезапуск Bash B на следующей модели цепочки. Арбитр наследует резолвнутую `FABLE_MODEL`.
- **Fable exit != 0 или bad JSON** — `$FABLE_OUT` либо plain-text ошибка, либо headless-envelope без извлекаемого вердикта (в т.ч. `stop_reason: refusal` на security-фокусных прогонах — для Fable это ожидаемый режим отказа, при нём перезапуск на claude-opus-5). Если каскад Шага 6 ничего не извлёк — stub unreliable. Покажи `cat "$FABLE_OUT"` для диагностики.
- **Арбитр-сбой** — один retry → интервью по A3-fallback эвристике. Пайплайн не падает.
- **Обе ветки crashed** (после перезапуска каждой) — `consensus.verdict = unreliable`, `coverage: partial`, обе метки в `dropped`. Пайплайн сломан — диагностировать через raw output файлы. Интервью не запускать; строка журнала всё равно пишется.
- **Один верификатор упал** (перезапуск не помог) — ветка в `dropped`, `coverage: partial`, вердикт от выжившей, approve запрещён (`consensus.status` = needs-revision). Интервью идёт по находкам выжившей ветки, и в сводке это названо прямо: проверка неполная.
- **Фаза C не отработала** — правки остаются применёнными, прогон не блокируется; в сводке строка «Перепроверка правок: не выполнена», в журнале `delta_by: none`.
- **CLI зависнет** — timeout Bash-инструмента (600000 мс) убьёт процесс → notification с ошибкой → partial verdict из остальных верификаторов сохраняется. (Команды `timeout` в системе нет — не использовать.)
- **Finding без `file`** (`null`) — целевой файл = TARGET_PATH.
- **Все находки skipped** — Фаза B пропускается, сводка без применения.
- **Субагент не смог применить правку** — отметить в сводке (`skipped: <причина>` от субагента), пайплайн не падает.

`claude -p --output-format json --json-schema` имеет встроенный retry. Собственного retry-loop не строим (кроме описанного одиночного retry арбитра).

## Структура файлов

Карта каталога и таблица «что где менять» — `STRUCTURE.md` (для человека, рантайму не нужна).
Артефакты прогона — в `AI/verif/`: `{BASE}--{codex,fable,merged,findings,arbiter,decisions,delta}.json`, `{BASE}--verdict.md`; журнал всех прогонов — `AI/verif/_runs.jsonl`.
