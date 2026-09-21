# verif — карта файлов (для человека, не для рантайма)

```
<plugin-root>/skills/verif/          (${CLAUDE_PLUGIN_ROOT})
├── SKILL.md                     (orchestration v6 — единственный файл, который читает рантайм)
├── STRUCTURE.md                 (этот файл)
├── TESTS.md                     (журнал проверок с датами)
├── system-prompts/
│   ├── fable-verifier.md        (Fable policy — mirror AGENTS.md + «ignore CLAUDE.md»)
│   └── arbiter.md               (Арбитр: судить находки, не искать новые)
├── prompts/
│   ├── plan.md                  (adversarial plan template — shared)
│   ├── research.md              (fact-check template — shared)
│   └── doc.md                   (accuracy-check template — shared)
├── references/
│   ├── interview-apply.md       (спека Фазы A/B — режим интервью авто/вручную, шаблон вопроса,
│   │                             фиксация решений, применение правок)
│   └── plain-language.md        (правила простого языка: дописывается в system prompt
│                                 арбитра, по нему строятся вопросы интервью и блок «Коротко»)
├── schema/
│   ├── verdict.json             (каноническая схема: codex --output-schema;
│   │                             для claude -p prelude делает производную без minLength/minimum/
│   │                             maximum и корневых $schema/$id/title/description)
│   └── arbiter.json             (схема оценок арбитра — сразу Claude-совместимая; v6.1: + объект
│                                 `plain` на каждую оценку — слой для человека)
└── scripts/
    ├── build_prompt.sh          (сборка промпта из template)
    ├── normalize_and_merge.sh   (каскады разбора ответов обоих CLI → merge → render → save)
    ├── merge_verdicts.sh        (strict hierarchy merge, N провайдеров label:path)
    └── render_merged.sh         (динамический pretty-print по consensus.providers;
                                  помечает ⚠ НЕ УЧАСТВОВАЛ / ⚠ СБОЙ)

<plugin-data>/verif-homes/       (${CLAUDE_PLUGIN_DATA} — переживает обновление плагина;
                                  шаблоны едут в <plugin-root>/assets/verif-homes/ и
                                  разворачиваются сюда при первом запуске)
└── codex-home/
    ├── AGENTS.md                (Codex verifier policy: FACT/INFERENCE/SPECULATION)
    ├── config.toml              (единый профиль GPT-6 Astra, high; service_tier=default в плагине;
    │                             локальный пин priority — настройка получателя)
    └── auth.json                (symlink на ~/.codex/auth.json)
```

Артефакты прогона — в vault, `AI/verif/` (корень vault = `${user_config.VAULT_PATH}`): `{BASE}--{codex,fable,merged,findings,arbiter,decisions}.json`, `{BASE}--verdict.md`.

## Что где менять

| Что | Файл |
|---|---|
| Policy Codex | `assets/verif-homes/codex-home/AGENTS.md` (шаблон) → `${CLAUDE_PLUGIN_DATA}/verif-homes/codex-home/AGENTS.md` (рабочая копия) |
| Policy Fable | `system-prompts/fable-verifier.md` |
| Policy арбитра | `system-prompts/arbiter.md` |
| Шаблоны запроса | `prompts/*.md` |
| Схема вердикта | `schema/verdict.json` — ломает обе ветки при изменении; менять только с bump версии, помнить про производную Claude-схему в prelude |
| Язык и формат вопросов интервью, режимы авто/вручную | `references/plain-language.md` (правила) + `references/interview-apply.md` (развилка A3.0, шаблон вопроса A3.1, авто-режим A3.2) |
| Поля `plain.*` арбитра | `schema/arbiter.json` + секция «Plain-language layer» в `system-prompts/arbiter.md` |
