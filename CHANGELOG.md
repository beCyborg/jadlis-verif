# Changelog — jadlis-verif

Формат: [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/), версии — [SemVer](https://semver.org/lang/ru/).
История до 1.0.0 — плагин `jadlis-research` 1.0.0–1.3.0 в репо [jadlis-start](https://github.com/beCyborg/jadlis-start) (`plugins/jadlis-research/CHANGELOG.md` до split).

## [Unreleased]

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
