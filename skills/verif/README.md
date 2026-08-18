# verif — карта файлов (для человека, не для рантайма)

```
<plugin-root>/skills/verif/          (${CLAUDE_PLUGIN_ROOT})
├── SKILL.md                     (orchestration v6 — единственный файл, который читает рантайм)
├── README.md                    (этот файл)
├── TESTS.md                     (журнал проверок с датами)
├── system-prompts/
│   ├── fable-verifier.md        (Fable policy — mirror AGENTS.md + «ignore CLAUDE.md»)
│   └── arbiter.md               (Арбитр: судить находки, не искать новые)
├── prompts/
│   ├── plan.md                  (adversarial plan template — shared)
│   ├── research.md              (fact-check template — shared)
│   └── doc.md                   (accuracy-check template — shared)
├── references/
│   ├── normalization.md         (bash-каскады нормализации входа)
│   └── interview-apply.md       (спека Фазы A/B — интервью и применение правок)
├── schema/
│   ├── verdict.json             (каноническая схема: codex --output-schema, grok --json-schema;
│   │                             для claude -p prelude делает производную без minLength/minimum/
│   │                             maximum и корневых $schema/$id/title/description)
│   └── arbiter.json             (схема оценок арбитра — сразу Claude-совместимая)
└── scripts/
    ├── build_prompt.sh          (сборка промпта из template)
    ├── merge_verdicts.sh        (strict hierarchy merge, N провайдеров label:path)
    └── render_merged.sh         (динамический pretty-print по consensus.providers)

<plugin-data>/verif-homes/       (${CLAUDE_PLUGIN_DATA} — переживает обновление плагина;
                                  шаблоны едут в <plugin-root>/assets/verif-homes/ и
                                  разворачиваются сюда при первом запуске)
├── codex-home/
│   ├── AGENTS.md                (Codex verifier policy: FACT/INFERENCE/SPECULATION)
│   ├── config.toml              (единый профиль GPT-5.6 Sol, xhigh, standard tier)
│   └── auth.json                (symlink на ~/.codex/auth.json)
└── grok-home/
    ├── AGENTS.md                (Grok verifier policy — mirror codex AGENTS.md, tools grok)
    ├── config.toml              (grok-4.6 + high effort, memory off, compat off; CLI дописывает
    │                             runtime-состояние — норм)
    └── auth.json                (symlink на ~/.grok/auth.json)
```

Артефакты прогона — в vault, `AI/verif/` (корень vault = `${user_config.VAULT_PATH}`): `{BASE}--{codex,fable,grok,merged,findings,arbiter,decisions}.json`, `{BASE}--verdict.md`.

## Что где менять

| Что | Файл |
|---|---|
| Policy Codex | `assets/verif-homes/codex-home/AGENTS.md` (шаблон) → `${CLAUDE_PLUGIN_DATA}/verif-homes/codex-home/AGENTS.md` (рабочая копия) |
| Policy Grok | `assets/verif-homes/grok-home/AGENTS.md` (шаблон) → `${CLAUDE_PLUGIN_DATA}/verif-homes/grok-home/AGENTS.md` (рабочая копия) |
| Policy Fable | `system-prompts/fable-verifier.md` |
| Policy арбитра | `system-prompts/arbiter.md` |
| Шаблоны запроса | `prompts/*.md` |
| Схема вердикта | `schema/verdict.json` — ломает все три CLI при изменении; менять только с bump версии, помнить про производную Claude-схему в prelude |
