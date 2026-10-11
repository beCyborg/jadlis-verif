# Changelog — jadlis-verif

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).
История до 1.0.0 — плагин `jadlis-research` 1.0.0–1.3.0 в репо [jadlis-start](https://github.com/beCyborg/jadlis-start) (`plugins/jadlis-research/CHANGELOG.md` до split).

## [Unreleased]

## [3.2.0] — 2026-10-11 — Факты и решения, раунды по зависимостям / Facts vs decisions, dependency rounds

### Для человека

- Арбитр делит находки на два вида. Факт — у находки один правильный ответ, его даёт файл или источник. Решение — ответ зависит от твоих целей, сроков, объёма или вкуса.
- В авто-режиме факты правятся сами, как раньше. Решения задаются все: вопросом, рекомендованным ответом и самой сильной альтернативой, а не выбором «исправить / оставить».
- Вопросы идут раундами. Сначала находки, от которых зависят другие, потом зависимые. Если ты решил корневую находку иначе, чем советовал арбитр, зависимая находка перечитывается: она снимается как ненужная или задаётся заново.
- Зачем: в журнале 68 из 957 решений (7 %) ты отвечал своим текстом, и почти всегда это было решение о цели или рамках. Идея — из скилла /grilling Matt Pocock (mattpocock/skills): факты ищет агент, решения принимает человек; вопросы — по дереву решений.
- Журнал считает свой ответ отдельно для фактов и решений: так видно, помогло ли разделение.

### For agents

- Added: `schema/arbiter.json` — required `kind` (`fact`|`decision`) and `depends_on` (array of ids) per assessment; optional `decision_question` {`question`, `recommended`, `recommended_detail`, `alternative`, `alternative_detail`} for decisions. No forbidden keys; Claude structured output unchanged.
- Added: `system-prompts/arbiter.md` — sections «Fact or decision — `kind`» and «Dependencies — `depends_on`»; output-contract line for both.
- Added: `scripts/rounds.sh` — deterministic interview rounds from `depends_on` (Kahn layers; edges to unknown ids/self dropped; a cycle is broken by dropping back-edges, members flagged `cycle: true`; no arbiter → one round).
- Changed: `references/interview-apply.md` — A3.0 fork text with decision count; new A3.0a (facts vs decisions), A3.0b (rounds, dependent re-check with `superseded_by`), A3.1a (decision question template, answer → decision mapping); A3.2 auto mode asks every decision with `apply`/`discuss` outside the 4-question fact cap, auto-skips decisions with `skip`; A4 adds `kind`, `answer`, `round`, `superseded_by`, `why_asked` += `decision`, `dependency`; Phase B passes findings in round order and uses `recommended_detail` for accepted decisions.
- Changed: `scripts/log_run.sh` — new fields `kinds`, `dependent`, `by_kind`, `answers`, `rounds`, `superseded` (null for pre-3.2.0 runs); `forks` now counts only the four procedural fork reasons (unchanged on old runs: verified on 2026-10-08 row).
- Changed: `scripts/verif_stats.sh` — «Факты и решения» (custom-answer share per kind, decision answers) and «Зависимости» lines.
- Changed: `references/plain-language.md` (`decision_question` field table), `SKILL.md` (v9 line, `ROUNDS` in prelude, arbiter and Phase A summaries), `STRUCTURE.md`, README pair.

## [3.1.5] — 2026-10-08 — репозиторий переехал на GitLab / repository moved to GitLab

### Для человека

- Плагин теперь живёт на GitLab: https://gitlab.com/beCyborg/jadlis-verif. Аккаунт GitHub beCyborg заблокирован, поэтому старые ссылки открывают 404.
- Каталог ставится новой командой: `claude plugin marketplace add https://gitlab.com/beCyborg/jadlis-hub.git`. Если ты уже ставил его со старой ссылки GitHub, удали каталог командой `claude plugin marketplace remove jadlis` и поставь всё заново по README. Плагины этого каталога при удалении тоже снимутся.
- Работа плагина не изменилась.

### For agents

- Changed: every `github.com/beCyborg/*` link in README pairs, `docs/tier/` README pair (images from the hub's GitLab raw URL; the dead hub `docs/3-research` link now points to the jadlis-research repo) now points to `gitlab.com/beCyborg/*`; `marketplace add` uses the full `https://…/jadlis-hub.git` URL (non-GitHub hosts have no `owner/repo` shorthand).
- Changed: `.claude-plugin/plugin.json` `homepage`/`repository` → GitLab; version 3.1.4 → 3.1.5.
- Changed: CI moved from `.github/workflows/ci.yml` (reusable workflow in `beCyborg/jadlis-hub`) to `.gitlab-ci.yml` including `/ci/plugin-ci.yml` from `beCyborg/jadlis-hub` on GitLab — same checks: `claude plugin validate --strict`, gitleaks full history, README parity, privacy grep.

## [3.1.4] — 2026-09-30 — Фоновые вызовы до 45 минут / Background calls up to 45 min

### Для человека

- Ветки проверки и арбитр больше не обрываются на 10-й минуте: на xhigh длинный план проверяется дольше, и старый лимит убивал вызов раньше, чем он успевал ответить.

### Technical

- Changed: `skills/verif/SKILL.md` Bash A/B and Arb-2, `references/delta-recheck.md` — `timeout` 600000 → 2700000 ms. 600000 is the foreground cap only; `run_in_background` allows up to 7200000. Failure-mode note updated to match.

## [3.1.3] — 2026-09-30 — Claude-ветка и арбитр на xhigh / Claude branch and arbiter at xhigh

### Для человека

- Вторая ветка проверки и арбитр думают глубже (effort xhigh вместо high). Проверка идёт дольше, зато на ревью Opus 5.5 на xhigh находит ошибки, которые high пропускает. Codex остаётся на high.

### Technical

- Changed: `skills/verif/SKILL.md` — `EFFORT_FABLE="xhigh"` (was `high`); applies to Bash B (`--effort {EFFORT_FABLE}`) and the arbiter. Reason: replay in the «Opus 5.5 на моих задачах» research — code review at xhigh found unique, actionable issues (3× time); verif is a single end-of-chain call, so the cost is bounded.

## [3.1.2] — 2026-09-29 — Claude-ветка на Opus 5.5 / Claude branch on Opus 5.5

### Для человека

- Вторая ветка проверки и арбитр теперь работают на Opus 5.5 вместо Fable 5.1. Если Opus 5.5 отказалась или не влезла в контекст, ветка один раз перезапускается на Opus 5.
- Зачем: по ресёрчу «Opus 5.5 на моих задачах» Opus 5.5 на high по индексу Artificial Analysis держится вровень с Fable 5.1 на max, а задача обходится примерно вчетверо дешевле. Взгляд модели другого семейства в проверке по-прежнему даёт Codex.

### For agents

- Changed: `skills/verif/SKILL.md` — `FABLE_MODEL_PRIMARY="claude-fable-5-1"` → `"claude-opus-5-5"`, `FABLE_MODEL_FALLBACK="claude-opus-5-5"` → `"claude-opus-5"`; model-chain and refusal-restart gotchas, headings, user-facing messages and the arbiter line now name Opus 5.5. `system-prompts/fable-verifier.md` and `system-prompts/arbiter.md` headers, `references/delta-recheck.md` fallback wording, `README*.md`, `docs/tier/README*.md`, `plugin.json` description and keyword (`fable` → `opus`) follow.
- Unchanged on purpose: the `fable` branch label — `FABLE_*` variables, `FABLE_OUT`, `EFFORT_FABLE`, `--only codex|fable`, merge labels, `delta_by: fable`, `_runs.jsonl` keys, file `fable-verifier.md`. Renaming them would break the run-log schema and the saved-run regressions; a comment next to `FABLE_MODEL_PRIMARY` marks the label as historical.
- Tests: `skills/verif/TESTS.md` gains a PENDING row for the first live dual run on `claude-opus-5-5`; past PASS rows naming `claude-fable-5-1` stay as history.
- Migration: none; the branch keeps its label, only the model behind it changes.

## [3.1.1] — 2026-09-22 — Переход на Opus 5.5 / Switch to Opus 5.5

### Для человека

- Если Fable 5.1 недоступна или отказалась, запасная ветка проверки теперь идёт на Opus 5.5 вместо Opus 5.
- Плагин требует Claude Code ≥ 2.1.280: более старые версии не знают новую модель.

### For agents

- Changed: `skills/verif/SKILL.md` — `FABLE_MODEL_FALLBACK="claude-opus-5"` → `"claude-opus-5-5"` (Opus 5.5, 1M context native, no `[1m]` suffix), the model chain and the refusal-restart note in the gotchas list now name `claude-opus-5-5`, the review-direction caveat names "Opus 5.5/Fable 5"; `skills/verif/system-prompts/fable-verifier.md` header → "fallback Opus 5.5". `FABLE_MODEL_PRIMARY`, `CODEX_MODEL` and effort values unchanged.
- Migration: requires Claude Code ≥ 2.1.280 — older versions may reject the unknown model ID `claude-opus-5-5` when the Fable branch falls back. `skills/verif/TESTS.md` keeps `claude-opus-5` as test history.

## [3.1.0] — 2026-09-21

### Для человека

- **Правки теперь перепроверяются.** После того как плагин внёс принятые находки в файл, он
  показывает получившиеся изменения другой модели — Codex, не той, что правила, — и спрашивает
  ровно три вещи: закрыта ли каждая находка, не сломано ли рядом, не переписано ли больше, чем
  просили. Нашлись проблемы — один круг доправок и повторная проверка; не сошлось со второго
  раза — плагин честно говорит, что осталось, и не правит дальше. Не нужно — флаг
  `--no-recheck`.
- **Упавшая проверка больше не топит весь разбор.** Раньше одна молчащая ветка делала общий
  вердикт «ненадёжен». Теперь ветку сначала перезапускают один раз, и только если она молчит
  снова — вердикт собирается по той, что ответила, а в шапке отчёта появляется строка
  «ПОКРЫТИЕ: частичное (выпал: …)». При неполном покрытии «можно делать» не выдаётся: даже
  когда выжившая ветка всем довольна, результат читается как «нужны правки».
- **Авто-режим спрашивает по делу, а не по уверенности.** Вопрос прилетает, если находка
  критическая, если правка необратима (удаление данных, отправка наружу, платёж), если
  проверяющие и арбитр спорят или если арбитр отменил то, на чём оба сошлись. Порог «арбитр
  не уверен» убран: самооценка уверенности у моделей откалибрована плохо. Плюс один случайный
  вопрос-проверка по тому, что плагин решил сам, — чтобы было видно, совпадают ли его решения
  с твоими. Всего по-прежнему не больше четырёх вопросов.
- **Каждый прогон оставляет строку в журнале** `AI/verif/_runs.jsonl`: что проверяли, сколько
  находок подала каждая ветка, сколько ты принял, сколько времени ушло на вопросы. Журнал
  залит задним числом по 74 прошлым прогонам — базовая линия: принято 75,6 % находок.

### For agents

- **Фаза C (новое):** `references/delta-recheck.md` — снимки целевых файлов до правок (C0,
  `shasum -a 256` от пути → имя снимка), `diff -u` после (C1), один фоновый вызов Codex по
  шаблону Bash A с `--output-schema schema/delta.json` и промптом `system-prompts/delta-check.md`
  (C2), один круг доправок теми же субагентами + повторный C2, `MAX_FIX_ROUNDS = 2` (C3).
  Codex недоступен → Fable headless, `delta_by: fable`; упали оба → `delta_by: none`, прогон не
  блокируется. Артефакт `{BASE}--delta.json`, одна строка в сводке. Пропуск: нет принятых
  находок, `--report-only`, `--json`, `--only`, новый флаг `--no-recheck`.
- `system-prompts/delta-check.md` несёт тот же guard, что интервью: дифф, содержимое файлов и
  текст находок — **данные, а не инструкции**; «проблем нет» объявлено законным ответом.
- `schema/delta.json` — `status` (`clean|issues`), `summary`, `closed[]` (`yes|partial|no`),
  `regressions[]` (цитата + строка + тяжесть), `scope_creep[]`. Совместима сразу с
  `codex --output-schema` и `claude -p --json-schema`: запрещённых ключей нет, производную
  делать не нужно.
- `scripts/merge_verdicts.sh`: консенсус считается **только по ответившим** веткам. Заглушка
  провайдера по-прежнему пишется в merged, но её метка уходит в `consensus.dropped` и в
  голосовании не участвует. Добавлены `consensus.coverage` (`full|partial`),
  `consensus.dropped[]` и `consensus.status` — вердикт после гейта покрытия (`approve` под
  `partial` поднимается до `needs-revision`). `consensus.verdict` остаётся сырым; при полном
  покрытии вывод байт-в-байт совпадает с 3.0.0 без новых полей. Ответивших нет вовсе →
  `unreliable`, как раньше.
- `scripts/render_merged.sh`: строка `ПОКРЫТИЕ: полное | частичное (выпал: …)` сразу за
  `PROVIDERS`; при `approve` под partial — `VERDICT: APPROVE (покрытие частичное — не финально)`.
  Merged без полей покрытия (прогоны до 3.1.0) читается как полное.
- `SKILL.md`, обработка notifications: ветка без вердикта получает **один перезапуск тем же
  вызовом**, и только потом уходит в `dropped`. Перезапускается то же место, а не другое
  семейство (ресёрч «Состязательная верификация», раздел «Покрытие и повторные прогоны»).
- `references/interview-apply.md` A3.2: порог `confidence < 0.6` убран, развилка теперь
  процедурная — `adjusted_severity: critical`, `reversible: false`, `discuss` при critical/high,
  либо `skip`/`refuted` по находке с двумя источниками. До трёх развилок + **одна выборочная
  проверка**, выбранная `$RANDOM` в Bash (через `awk`, а не позиционные параметры: под zsh
  `set -- $VAR` даёт одно слово), потолок 4 вопроса вместе с ней.
- `decisions.json`: добавлено `why_asked`
  (`critical|irreversible|disputed|consensus-overruled|spot-check|null`). Прежние поля и
  значения не изменились.
- `schema/arbiter.json`: добавлено `reversible` (`["boolean","null"]`, в `required`); правило —
  в `system-prompts/arbiter.md`: `false` только для необратимого действия (удаление данных,
  отправка наружу, платёж, смена контракта), `null` считается обратимым.
- **Журнал запусков (новое):** `scripts/log_run.sh` — детерминированная сборка строки из
  merged / findings / arbiter / decisions / delta, только дозапись в `<vault>/AI/verif/_runs.jsonl`;
  модель журнал не пишет. Метки времени (`prelude`, `machine_done`, `interview_start`,
  `interview_done`) кладутся в `{BASE}--run.times`, скрипт его читает и удаляет.
  `scripts/verif_stats.sh` — сводка по журналу. Разовый `tools/backfill_runs.sh` (не рантайм)
  собирает журнал из уже лежащих артефактов и отказывается писать поверх непустого файла;
  строки помечены `backfilled: true`, чего не восстановить — `null`, а не ноль.
- `references/plain-language.md`: раздел про язык отчёта перепроверки (слова «регрессия»,
  «дельта», «scope creep» в человеческой части запрещены). `TESTS.md`: восемь новых строк,
  из них четыре PASS по скриптам и обратной заливке, четыре PENDING до живого смоука; в Gate
  добавлены Фаза C, авто-режим 3.1.0 и перезапуск упавшей ветки. `STRUCTURE.md` и `plugin.json`
  (3.0.0 → 3.1.0) приведены в соответствие.

## [3.0.0] — 2026-09-21

### Для человека

- **Ломающее: ветки Grok больше нет.** Разбор идёт двумя моделями — Codex (GPT-6 Astra) и
  Claude (Fable 5.1); флаг `--only grok` удалён, остались `--only codex|fable`. Подписка Grok
  и Grok CLI больше не нужны ни для чего; арбитр анонимизирует источники метками A / B.
- Перед разбором находок плагин спрашивает, как их проходить: **авто** — применяю рекомендации
  арбитра сразу и спрашиваю только по сильным развилкам, не больше четырёх вопросов;
  **вручную** — по вопросу на каждую находку, как раньше. Перед тем как применить, авто-режим
  печатает список того, что решил, — можно вмешаться. Развилки нет, если арбитр не ответил:
  тогда сразу ручной режим.
- Вопросы стали короче и понятнее: одно короткое предложение на строку, никаких заглушек
  «не оценивалась» и «не описан» — если про цену или риск в находке ничего нет, строка просто
  не печатается. Вся фактура по-прежнему внутри окна вопроса.

### For agents

- **BREAKING:** удалён верификатор Grok целиком — `Bash(grok:*)` из `allowed-tools`, probe
  живости и все `GROK_*` переменные прелюдии, Bash C, ветки разбора ответов Grok в
  `normalize_and_merge.sh` (включая fallback по склеенному `.text` и гвард «пустого вердикта
  за один ход»), метка `grok` в списке «не участвовал» `render_merged.sh`, значение
  `--only grok`, каталог `assets/verif-homes/grok-home/`. `normalize_and_merge.sh` больше не
  читает `GROK_OUT`/`GROK_PARTICIPATED`; `strip_preamble` терпит отсутствующий файл ветки,
  так что деградация до одного провайдера рендерится без ошибки.
- `references/interview-apply.md`: новый шаг **A3.0** — развилка режима (`header` «Режим»,
  «Авто (Recommended)» / «Вручную»), показывается только при доступном арбитре с полным
  покрытием id и `N ≥ 1`. **A3.1** — прежний ручной протокол; вся фактура вернулась ВНУТРЬ
  `question` (пять строк обычного текста, без разметки), сегменты «Цена:»/«Риск:» выбрасываются
  при пустых `plain.cost` / `plain.risk_of_fix`. **A3.2** — авто-режим: `apply` → applied,
  `skip`/`refuted` → skipped, сильные развилки (`discuss` при critical/high либо `apply`/`skip`
  по critical/high с `confidence < 0.6`) — одним батчем до 4 вопросов, остаток применяется с
  пометкой низкой уверенности.
- `decisions.json`: у каждого объекта добавлены `decided_by` (`user` | `auto`) и
  `auto_low_confidence` (bool); прежние поля и значения `decision` не изменились.
- `references/plain-language.md`: разметки в интервью нет нигде (клиент сам показывает
  `question` жирным); `problem` / `if_fixed` / `if_kept` — одно предложение ≤ 18 слов,
  `cost` / `risk_of_fix` — короткий оборот или пусто; добавлена таблица «плохо → хорошо» по
  каждому полю. Заглушки «не оценивалась» / «не описан» / «ничем» запрещены — соответственно
  `schema/arbiter.json` разрешает `cost` и `risk_of_fix` пустыми (`["string","null"]`), а
  `system-prompts/arbiter.md` требует краткости и запрещает заглушки и страховочные цепочки.
- Вызов арбитра берёт effort из `{EFFORT_FABLE}` вместо литерала `high`; прелюдия печатает
  строку `MODELS=<fable> / <codex> / <effort fable> / <effort codex>`.
- `assets/verif-homes/codex-home/AGENTS.md`: убран устаревший «Opus 4.8», партнёрская ветка
  названа Claude Fable 5.1. Рабочую копию `~/.claude/verif-homes/codex-home/AGENTS.md`
  обновлять копированием — прелюдия существующие файлы не перетирает.
- `plugin.json`: `version` 2.0.0 → 3.0.0, описание и `keywords` без Grok. Тег релиза —
  `jadlis-verif--v3.0.0`.

## [2.0.0] — 2026-09-10

### Для человека

- Плагин переименован: `verif` → `jadlis-verif`. Ставится строкой
  `claude plugin install jadlis-verif@jadlis`, маркетплейс — `https://github.com/beCyborg/jadlis-hub`.
  Короткая команда `/verif` не изменилась; полная форма стала `/jadlis-verif:verif`.
  Обратной совместимости нет: старое имя `verif@jadlis` больше не ставится.
- README (RU и EN) приведён в соответствие с кодом: обязателен только Codex CLI (подписка
  ChatGPT). Grok необязателен — без него разбор идёт в режиме двух моделей, Codex + Fable,
  и сам возвращается к трём, когда Grok снова доступен.
- Тир-2 документ («ключи и первая проверка плана») переехал из хаба в репо:
  `docs/tier/README.md` и `docs/tier/README.en.md`.

### For agents

- `plugin.json`: `name` `verif` → `jadlis-verif`, `version` 1.0.0 → 2.0.0. Папки скиллов не
  переименованы, `${CLAUDE_PLUGIN_ROOT}`-пути прежние.
- Ссылки на MCP-инструменты плагина поиска: `mcp__plugin_search_*` →
  `mcp__plugin_jadlis-search_*` (`skills/verif/SKILL.md`, `system-prompts/fable-verifier.md`).
- Тег релиза теперь `jadlis-verif--v2.0.0`; префикс `verif--v*` больше не используется.
- CI зовёт reusable workflow `beCyborg/jadlis-hub/.github/workflows/plugin-ci.yml@main`.

## [1.0.0] — 2026-09-07

### Для человека

- Первый релиз под именем `verif`: выделен из `jadlis-research` 1.3.0 (репо на плагин, команда `/verif`).

### For agents

- Split of `jadlis-research` 1.3.0 by `tools/split-research.py` (hub). Namespaces: MCP tools `mcp__plugin_search_*`, agents `—:*`, commands `/search`, `/search:keys`, `/research`, `/science-research`, `/verif`.
