# Changelog — jadlis-verif

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).
История до 1.0.0 — плагин `jadlis-research` 1.0.0–1.3.0 в репо [jadlis-start](https://github.com/beCyborg/jadlis-start) (`plugins/jadlis-research/CHANGELOG.md` до split).

## [Unreleased]

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
