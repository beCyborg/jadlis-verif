---
name: verif
description: Triple adversarial верификация — Codex (GPT-5.6 Sol) + Claude Fable 5 + Grok (grok-4.6) параллельно. Проверяет факты через search, оспаривает решения, находит пропущенные риски. После merge — этап Арбитра (Fable 5 судит дедуплицированные находки, кросс-чекает провайдеров, помечает опровергнутые), затем батч-интервью по находкам с рекомендациями арбитра и параллельное применение одобренных правок субагентами. Для single-provider — флаг --only codex|fable|grok; --report-only / --json — отчёт без интервью. TRIGGER when — user says "/verif", "/jadlis-research:verif", "верифицируй план", "проверь план перед имплементацией", "adversarial review плана", "verify plan", "проверь ресерч на факты", "фактчек документа". DO NOT TRIGGER when — ревью кода/diff (use /code-review), полное исследование темы (use /jadlis-research:full-research), быстрый фактчек одного утверждения (use /jadlis-research:search).
argument-hint: "[focus] [--file <path>] [--type plan|research|doc] [--only codex|fable|grok] [--report-only] [--json]"
allowed-tools: Read, Glob, Write, Edit, MultiEdit, AskUserQuestion, Task, Agent, Bash(codex:*), Bash(claude:*), Bash(grok:*), Bash(mktemp:*), Bash(cat:*), Bash(ls:*), Bash(jq:*), Bash(rm:*), Bash(trap:*), Bash(grep:*), Bash(echo:*), Bash(ln:*), Bash(bash:*), Bash(test:*), Bash(chmod:*), Bash(mkdir:*), Bash(date:*), Bash(sed:*), Bash(wc:*), Bash(stat:*)
---

# /jadlis-research:verif — Triple adversarial верификация (Codex + Fable 5 + Grok) с арбитром

Тонкий orchestrator трёх независимых верификаторов: OpenAI GPT-5.6 Sol через `codex exec`, Anthropic Claude Fable 5 через `claude -p` (headless), xAI grok-4.6 (high effort) через `grok --prompt-file` (подписочный CLI, $0). Все возвращают JSON по единой `schema/verdict.json`. Результаты сливаются через `scripts/merge_verdicts.sh` (strict hierarchy: unreliable > needs-revision > approve, N провайдеров с метками) и рендерятся через `scripts/render_merged.sh`.

Provider-agnostic policy — `${CLAUDE_PLUGIN_DATA}/verif-homes/codex-home/AGENTS.md` для Codex, `system-prompts/fable-verifier.md` для Fable, `${CLAUDE_PLUGIN_DATA}/verif-homes/grok-home/AGENTS.md` для Grok (разворачиваются из `${CLAUDE_PLUGIN_ROOT}/assets/verif-homes/` при первом запуске). Templates — `prompts/{plan,research,doc}.md`.

**Архитектура v6:** single-turn запуск, три параллельных `Bash(run_in_background: true)`. Completion notification приходит независимо для каждого — скилл показывает результат каждого завершившегося верификатора сразу (стриминг). Grok при сбое деградирует (один retry → dual-режим без него, пайплайн жив). После merge — **этап Арбитра**: headless Fable 5 (high) судит дедуплицированные находки в контексте целевого файла, кросс-чекает провайдеров и помечает опровергнутые. Затем Фаза A: батч-интервью по находкам с рекомендациями арбитра, и Фаза B: параллельное применение одобренных правок субагентами (один файл = один субагент).

## Аргументы

`$ARGUMENTS`

- `--file <path>` — путь к файлу для верификации.
- `--type plan|research|doc` — тип файла (если не указан — определи автоматически).
- `--only codex|fable|grok` — запустить только один верификатор. По умолчанию — все три параллельно. Арбитр, интервью и применение не запускаются.
- `--report-only` — вывести merged-отчёт и остановиться (без арбитра, интервью и применения).
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

- **Default (triple):** Codex + Fable + Grok параллельно (три `Bash(run_in_background: true)`
  в одном сообщении) → notifications → merge + render → Арбитр → Фаза A → Фаза B.
- **`--only codex|fable|grok`:** соответствующий Bash в одиночку, рендер single-verifier
  (Шаг 7), без арбитра и интервью. Grok в этом режиме без retry-деградации: при сбое
  просто показать ошибку.

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
GROK_HOME_DIR="$VERIF_HOMES/grok-home"
GROK_BIN="$HOME/.grok/bin/grok"

# First-run deploy шаблонов (идемпотентно: существующие файлы не перетираем)
mkdir -p "$CODEX_HOME_DIR" "$GROK_HOME_DIR"
for f in AGENTS.md config.toml; do
  [[ -e "$CODEX_HOME_DIR/$f" ]] || cp "$VERIF_HOMES_TEMPLATE/codex-home/$f" "$CODEX_HOME_DIR/$f"
  [[ -e "$GROK_HOME_DIR/$f" ]]  || cp "$VERIF_HOMES_TEMPLATE/grok-home/$f"  "$GROK_HOME_DIR/$f"
done
# Пустой HOME для Grok: CLI безусловно читает ~/.claude/settings.json и транслирует
# permissions.deny в свои правила (deny > allow, тумблера нет — [compat.claude] это НЕ покрывает).
# Без изоляции deny "WebFetch" глушит grok'ов web_fetch → верификатор не дочитывает первоисточники.
GROK_ISO_HOME="$HOME/.cache/grok-iso-home"
mkdir -p "$GROK_ISO_HOME"
SCHEMA_PATH="$VERIFIER_ROOT/schema/verdict.json"
ARBITER_SCHEMA_PATH="$VERIFIER_ROOT/schema/arbiter.json"
BUILD_PROMPT="$VERIFIER_ROOT/scripts/build_prompt.sh"
FABLE_SYSTEM_PROMPT="$VERIFIER_ROOT/system-prompts/fable-verifier.md"
ARBITER_SYSTEM_PROMPT="$VERIFIER_ROOT/system-prompts/arbiter.md"

# First-run symlinks (safe no-op если существуют)
if [[ ! -e "$CODEX_HOME_DIR/auth.json" ]]; then
  ln -s "$HOME/.codex/auth.json" "$CODEX_HOME_DIR/auth.json"
fi
if [[ ! -e "$GROK_HOME_DIR/auth.json" ]]; then
  ln -s "$HOME/.grok/auth.json" "$GROK_HOME_DIR/auth.json"
fi

# Hardcoded settings
EFFORT_CODEX="xhigh"
EFFORT_FABLE="high"
CODEX_MODEL="gpt-5.6-sol"
GROK_MODEL="grok-4.6"     # frontier-модель подписки (500K ctx); effort: low|medium|high|xhigh, high = дефолт

# Выбор Fable-модели: Fable 5 по умолчанию; big-file guard — файлы >350 KB
# (~100K токенов) уводим сразу на claude-opus-5 (1M-контекст по умолчанию).
FABLE_MODEL_PRIMARY="claude-fable-5"
FABLE_MODEL_FALLBACK="claude-opus-5"
TARGET_BYTES=$(wc -c < "$ABSOLUTE_PATH")
if [[ "$TARGET_BYTES" -gt 350000 ]]; then
  FABLE_MODEL="$FABLE_MODEL_FALLBACK"
else
  FABLE_MODEL="$FABLE_MODEL_PRIMARY"
fi

# Claude-совместимая производная схема: structured outputs Anthropic не поддерживает
# minLength/minimum/maximum и мета-ключи корня ($schema/$id/title/description) — с ними
# claude -p ТИХО не заполняет .structured_output (проверено смоуком 2026-07-02).
# verdict.json остаётся канонической для codex (--output-schema) и grok (--json-schema).
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
if [[ -e "$PERSIST_DIR/${BASE}--codex.json" || -e "$PERSIST_DIR/${BASE}--fable.json" || -e "$PERSIST_DIR/${BASE}--grok.json" ]]; then
  V=2
  while [[ -e "$PERSIST_DIR/${BASE}-v${V}--codex.json" || -e "$PERSIST_DIR/${BASE}-v${V}--fable.json" || -e "$PERSIST_DIR/${BASE}-v${V}--grok.json" ]]; do
    V=$((V+1))
  done
  BASE="${BASE}-v${V}"
fi

CODEX_OUT="$PERSIST_DIR/${BASE}--codex.json"
FABLE_OUT="$PERSIST_DIR/${BASE}--fable.json"
GROK_OUT="$PERSIST_DIR/${BASE}--grok.json"
MERGED_OUT="$PERSIST_DIR/${BASE}--merged.json"
VERDICT_MD="$PERSIST_DIR/${BASE}--verdict.md"
FINDINGS_OUT="$PERSIST_DIR/${BASE}--findings.json"
ARBITER_OUT="$PERSIST_DIR/${BASE}--arbiter.json"
DECISIONS_OUT="$PERSIST_DIR/${BASE}--decisions.json"

echo "VERIF_PATHS:"
echo "  PROMPT_FILE=$PROMPT_FILE"
echo "  CLAUDE_SCHEMA_FILE=$CLAUDE_SCHEMA_FILE"
echo "  TARGET_PATH=$ABSOLUTE_PATH"
echo "  TARGET_BYTES=$TARGET_BYTES"
echo "  CODEX_OUT=$CODEX_OUT"
echo "  FABLE_OUT=$FABLE_OUT"
echo "  GROK_OUT=$GROK_OUT"
echo "  MERGED_OUT=$MERGED_OUT"
echo "  VERDICT_MD=$VERDICT_MD"
echo "  FINDINGS_OUT=$FINDINGS_OUT"
echo "  ARBITER_OUT=$ARBITER_OUT"
echo "  DECISIONS_OUT=$DECISIONS_OUT"
echo "  EFFORT_CODEX=$EFFORT_CODEX"
echo "  EFFORT_FABLE=$EFFORT_FABLE"
echo "  FABLE_MODEL=$FABLE_MODEL"
echo "  CODEX_MODEL=$CODEX_MODEL"
echo "  GROK_MODEL=$GROK_MODEL"
echo "  SCHEMA_PATH=$SCHEMA_PATH"
echo "  ARBITER_SCHEMA_PATH=$ARBITER_SCHEMA_PATH"
echo "  CODEX_HOME_DIR=$CODEX_HOME_DIR"
echo "  GROK_HOME_DIR=$GROK_HOME_DIR"
echo "  GROK_ISO_HOME=$GROK_ISO_HOME"
echo "  GROK_BIN=$GROK_BIN"
echo "  FABLE_SYSTEM_PROMPT=$FABLE_SYSTEM_PROMPT"
echo "  ARBITER_SYSTEM_PROMPT=$ARBITER_SYSTEM_PROMPT"
```

## Шаг 5: Запуск верификаторов через Bash(run_in_background)

Три `Bash(run_in_background: true)` вызова — в **одном сообщении**, иначе они выполнятся последовательно и прогон растянется втрое. При `--only` — один Bash.

Каждый Bash — фоновый процесс с отдельным completion notification. В системе нет команды `timeout` — предельное время задаёт timeout самого Bash-инструмента (600000 мс на вызов).

### Bash A: Codex (run_in_background: true, timeout: 600000)

```bash
CODEX_HOME="{CODEX_HOME_DIR}" codex exec \
  -m "gpt-5.6-sol" \
  --sandbox read-only \
  --skip-git-repo-check \
  --output-schema "{SCHEMA_PATH}" \
  -c model_reasoning_effort="xhigh" \
  -c service_tier="default" \
  - < "{PROMPT_FILE}" > "{CODEX_OUT}" 2>&1
```

### Bash B: Fable (run_in_background: true, timeout: 600000)

```bash
claude -p "$(cat "{PROMPT_FILE}")" \
  --model "{FABLE_MODEL}" \
  --effort high \
  --output-format json \
  --json-schema "$(cat "{CLAUDE_SCHEMA_FILE}")" \
  --append-system-prompt "$(cat "{FABLE_SYSTEM_PROMPT}")" \
  --allowedTools "Read,Grep,Glob,mcp__plugin_jadlis-research_brave-search__brave_web_search,mcp__plugin_jadlis-research_firecrawl__firecrawl_scrape" \
  < /dev/null > "{FABLE_OUT}" 2>&1
```

`< /dev/null` обязателен: без него фоновый `claude -p` ждёт stdin и печатает warning-строку ПЕРЕД JSON-envelope — ломает парсинг (источник нулевых прогонов v5).

### Bash C: Grok (run_in_background: true, timeout: 600000)

```bash
HOME="{GROK_ISO_HOME}" GROK_HOME="{GROK_HOME_DIR}" "{GROK_BIN}" \
  --prompt-file "{PROMPT_FILE}" \
  -m grok-4.6 \
  --effort high \
  --json-schema "$(cat "{SCHEMA_PATH}")" \
  --tools "read_file,grep,list_dir,web_search,web_fetch" \
  --disallowed-tools "run_terminal_cmd" \
  --no-memory --no-plan --no-auto-update --yolo \
  --max-turns 300 \
  > "{GROK_OUT}" 2>&1
```

ВАЖНО про Grok: `--effort high` передаём явно (grok-4.6 поддерживает `low|medium|high|xhigh`; high и так дефолт, но пин защищает от смены дефолта на стороне xAI); `HOME="{GROK_ISO_HOME}"` обязателен — иначе Grok читает `~/.claude/settings.json` и его `permissions.deny: ["WebFetch"]` глушит `web_fetch` («Denied by permission policy»), верификатор остаётся без чтения первоисточников; `--allow web_fetch` и `GROK_WEB_FETCH=1` НЕ помогают (deny > allow, проверено 2026-07-10); `--sandbox read-only` НЕ использовать (блокирует сеть → ломает web_search); изоляция — через allowlist `--tools` + запрет `run_terminal_cmd`. `--max-turns 300` — заведомо недостижимый потолок (при 30 Grok упирался в него до выдачи structured output; флаг оставлен явно, т.к. дефолт CLI без него не документирован); реальный backstop от зависания — timeout Bash-инструмента 600000 мс. Allowlist из одного `web_search` ломает сборку агента — использовать ровно указанный набор.

Сообщи пользователю: "Верификаторы запущены параллельно (Codex GPT-5.6 Sol + Fable 5 + Grok). Результаты будут появляться по мере завершения..."

### Обработка notifications

При каждом notification:
1. Определить какой верификатор завершился (по тексту notification — он содержит команду и путь output файла).
2. Прочитать output файл, нормализовать (см. Шаг 6), отрендерить single verdict через jq.
3. Показать: `"✓ {Codex|Fable|Grok} завершён. Ожидание остальных..."`

Признаки сбоя Grok: exit != 0, невалидный JSON, `.type == "error"` или пустые
`.structuredOutput` И `.text` — обработка в «Ошибки и fallbacks». Успех → `GROK_PARTICIPATED=1`. Когда все участвующие верификаторы завершились → Шаг 6.

## Шаг 6: Нормализация + Merge + Render + Save

Один Bash-вызов. Каскады разбора ответов трёх CLI (форма verdict у каждого своя и менялась
между версиями) живут в скрипте — там же объяснено, почему каскад обязателен:

```bash
CODEX_OUT="$CODEX_OUT" FABLE_OUT="$FABLE_OUT" GROK_OUT="${GROK_OUT:-}" \
GROK_PARTICIPATED="${GROK_PARTICIPATED:-0}" JSON_MODE="$JSON_MODE" \
MERGED_OUT="$MERGED_OUT" VERDICT_MD="$VERDICT_MD" \
PROMPT_FILE="$PROMPT_FILE" CLAUDE_SCHEMA_FILE="$CLAUDE_SCHEMA_FILE" \
bash "${CLAUDE_PLUGIN_ROOT}/skills/verif/scripts/normalize_and_merge.sh"
```

Нераспознанный ответ провайдера становится `{}` → merge помечает его stub unreliable
(провайдер молчит, а не «согласен»). Grok при `GROK_PARTICIPATED=0` в merge не попадает:
отсутствие ≠ unreliable.

## Шаг 7: Отчёт и развилка

Выведи rendered verdict (как есть — не перефразируй и не резюмируй) + пути к сохранённым артефактам:

```
Артефакты сохранены:
- Codex verdict:  AI/verif/{BASE}--codex.json
- Fable verdict:  AI/verif/{BASE}--fable.json
- Grok verdict:   AI/verif/{BASE}--grok.json      (если участвовал)
- Merged:         AI/verif/{BASE}--merged.json
- Summary:        AI/verif/{BASE}--verdict.md
```

Затем развилка:

На этом работа заканчивается (арбитр и интервью не запускаются):
- **`--json`** — выведен полный merged JSON;
- **`--report-only`** — выведен rendered verdict;
- **`--only codex|fable|grok`** — single-verifier рендер (см. ниже).
- **Иначе (default triple)** — merged-вердикт уже показан (UX не ждёт арбитра); перейти к этапу Арбитра.

### Single-verifier режимы

Вердикт рендерится напрямую, без merge. Codex отдаёт готовый JSON; Fable и Grok сначала
прогнать через тот же каскад извлечения, что и в Шаге 6 (`.structured_output` /
`.structuredOutput` → `.result`/`.text | fromjson`); каскад целиком — в
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

1. Прочитать `$MERGED_OUT`. Собрать findings всех веток (`.codex.findings`, `.fable.findings`, `.grok.findings` если есть), каждую пометить source-меткой провайдера.
2. Дедуп между ветками: если у находок одинаковый целевой файл (`file`; `null` считается равным TARGET_PATH) И смысловое совпадение title/body (одна и та же проблема, пусть в разных формулировках) — слить в одну: `sources` = массив всех провайдеров-источников, severity = максимум, recommendation объединить (формулировки через « / » если различаются). **При сомнении — НЕ сливать**: два отдельных вопроса дешевле ложного слияния.
3. Отсортировать: critical → high → medium → low. Присвоить стабильные id в порядке сортировки: `F1`, `F2`, …
4. Записать (Write) `$FINDINGS_OUT` — массив объектов: `{id, title, body, severity, confidence, claim_type, recommendation, evidence_urls, sources, file, line_start, line_end}`.
5. **0 находок** → пропустить Арбитра и Фазы A/B. Сообщить: «Все ветки без findings — применять нечего». Конец.

### Arb-2. Headless-вызов арбитра (run_in_background: true, timeout: 600000)

**Анонимизация провайдеров** (family-bias: арбитр-Fable систематически переоценивает находки Fable; подтверждено ресерчем): выбери случайный маппинг провайдеров на метки `Verifier A/B/C`, запомни его для деанонимизации в интервью. В промпте арбитра все упоминания провайдеров (summaries и `sources` находок) заменить на анонимные метки; `$FINDINGS_OUT` на диске остаётся с реальными именами.

Сборка промпта: Write во временный файл `ARBITER_PROMPT_FILE` (mktemp) с содержимым:

```
TARGET FILE: {TARGET_PATH}

VERIFIER VERDICT SUMMARIES (anonymized):
- Verifier A: {verdict} — {summary}
- Verifier B: {verdict} — {summary}
- Verifier C: {verdict} — {summary}      (если участвовал)

FINDINGS TO JUDGE (deduplicated; sources anonymized to A/B/C):
{содержимое $FINDINGS_OUT с sources → метки}

Judge each finding per your role instructions. Return one assessment per finding id.
```

Запуск (арбитр наследует резолвнутую Fable-модель):

```bash
claude -p "$(cat "{ARBITER_PROMPT_FILE}")" \
  --model "{FABLE_MODEL}" \
  --effort high \
  --output-format json \
  --json-schema "$(cat "{ARBITER_SCHEMA_PATH}")" \
  --append-system-prompt "$(cat "{ARBITER_SYSTEM_PROMPT}")" \
  --allowedTools "Read,Grep,Glob" \
  < /dev/null > "{ARBITER_OUT}.raw" 2>&1
```

Сообщи: "Арбитр (Fable 5) оценивает {N} находок..."

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

- Сбой (exit != 0 / нет `.structured_output.assessments`) → **один foreground retry**; при повторном сбое `ARBITER_AVAILABLE=0` — интервью идёт по старой эвристике A3-fallback, пайплайн жив. Сообщи пользователю о деградации.
- Рассинхрон id: оценки с id, которых нет в findings.json — игнорировать; findings без оценки — обрабатывать по эвристике A3-fallback.

## Фазы A и B: интервью по находкам и применение правок

Только в default-режиме, после арбитра. Спека батч-интервью (пороги, формат вопросов,
guard против галлюцинаций, фиксация решений) и параллельного применения субагентами —
`@${CLAUDE_PLUGIN_ROOT}/skills/verif/references/interview-apply.md`.

## Ошибки и fallbacks

- **Background Bash exit != 0** — notification содержит exit code. Прочитать output файл для диагностики. `merge_verdicts.sh` увидит невалидный JSON → `unreliable` stub. Покажи пользователю tail stderr + предложи `/codex:setup` (auth issues) или `/codex:rescue`.
- **Fable: цепочка моделей** `claude-fable-5` → `claude-opus-5`. Переключение вниз: (а) unknown model / модель отвергнута; (б) context-overflow post-run (ошибка про превышение контекста в output) → перезапуск Bash B на следующей модели цепочки. Арбитр наследует резолвнутую `FABLE_MODEL`.
- **Fable exit != 0 или bad JSON** — `$FABLE_OUT` либо plain-text ошибка, либо headless-envelope без извлекаемого вердикта (в т.ч. `stop_reason: refusal` на security-фокусных прогонах — для Fable 5 это ожидаемый режим отказа, при нём перезапуск на claude-opus-5). Если каскад Шага 6 ничего не извлёк — stub unreliable. Покажи `cat "$FABLE_OUT"` для диагностики.
- **Grok-сбой** — один foreground retry того же Bash C (timeout 600000); при повторном сбое `GROK_PARTICIPATED=0`, сообщить о деградации в dual. Отсутствие Grok в merge ≠ unreliable. НЕ фоллбэчить на `mcp__grok-mcp` — это платный xAI API, кредиты исчерпаны.
- **Арбитр-сбой** — один retry → интервью по A3-fallback эвристике. Пайплайн не падает.
- **Все верификаторы crashed** — `consensus.verdict = unreliable`. Пайплайн сломан — диагностировать через raw output файлы. Интервью не запускать.
- **Один верификатор упал** (stub unreliable) — интервью идёт по находкам выживших веток.
- **CLI зависнет** — timeout Bash-инструмента (600000 мс) убьёт процесс → notification с ошибкой → partial verdict из остальных верификаторов сохраняется. (Команды `timeout` в системе нет — не использовать.)
- **Finding без `file`** (`null`) — целевой файл = TARGET_PATH.
- **Все находки skipped** — Фаза B пропускается, сводка без применения.
- **Субагент не смог применить правку** — отметить в сводке (`skipped: <причина>` от субагента), пайплайн не падает.

`claude -p --output-format json --json-schema` имеет встроенный retry. Собственного retry-loop не строим (кроме описанных одиночных retry для Grok и арбитра).

## Структура файлов

Карта каталога и таблица «что где менять» — `README.md` (для человека, рантайму не нужна).
Артефакты прогона — в `AI/verif/`: `{BASE}--{codex,fable,grok,merged,findings,arbiter,decisions}.json`, `{BASE}--verdict.md`.
