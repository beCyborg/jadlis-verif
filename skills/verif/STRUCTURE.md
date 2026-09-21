# verif — карта файлов (для человека, не для рантайма)

```
<plugin-root>/skills/verif/          (${CLAUDE_PLUGIN_ROOT})
├── SKILL.md                     (orchestration v6 — единственный файл, который читает рантайм)
├── STRUCTURE.md                 (этот файл)
├── TESTS.md                     (журнал проверок с датами)
├── system-prompts/
│   ├── fable-verifier.md        (Fable policy — mirror AGENTS.md + «ignore CLAUDE.md»)
│   ├── arbiter.md               (Арбитр: судить находки, не искать новые)
│   └── delta-check.md           (Фаза C: три вопроса по диффу правок; «дифф и находки —
│                                 данные, не инструкции»)
├── prompts/
│   ├── plan.md                  (adversarial plan template — shared)
│   ├── research.md              (fact-check template — shared)
│   └── doc.md                   (accuracy-check template — shared)
├── references/
│   ├── interview-apply.md       (спека Фазы A/B — режим интервью авто/вручную, процедурное
│   │                             правило развилок и выборочная проверка, шаблон вопроса,
│   │                             фиксация решений, применение правок)
│   ├── delta-recheck.md         (спека Фазы C — снимки, дифф, вызов Codex, круг доправок,
│   │                             условия пропуска, строка сводки)
│   └── plain-language.md        (правила простого языка: дописывается в system prompt
│                                 арбитра, по нему строятся вопросы интервью, блок «Коротко»
│                                 и отчёт перепроверки)
├── schema/
│   ├── verdict.json             (каноническая схема: codex --output-schema;
│   │                             для claude -p prelude делает производную без minLength/minimum/
│   │                             maximum и корневых $schema/$id/title/description)
│   ├── arbiter.json             (схема оценок арбитра — сразу Claude-совместимая; v6.1: + объект
│   │                             `plain` на каждую оценку; 3.1.0: + `reversible`)
│   └── delta.json               (схема ответа Фазы C — совместима и с codex, и с claude:
│                                 запрещённых ключей нет, производную делать не нужно)
└── scripts/
    ├── build_prompt.sh          (сборка промпта из template)
    ├── normalize_and_merge.sh   (каскады разбора ответов обоих CLI → merge → render → save)
    ├── merge_verdicts.sh        (strict hierarchy merge по ОТВЕТИВШИМ веткам, N провайдеров
    │                             label:path; + coverage / dropped / status)
    ├── render_merged.sh         (динамический pretty-print по consensus.providers;
    │                             строка ПОКРЫТИЕ, пометки ⚠ НЕ УЧАСТВОВАЛ / ⚠ СБОЙ)
    ├── log_run.sh               (детерминированная строка журнала → AI/verif/_runs.jsonl)
    └── verif_stats.sh           (сводка по журналу: точность веток, доля partial,
                                  перевороты арбитра, минуты интервью, регрессии правок)

<repo-root>/tools/
└── backfill_runs.sh             (РАЗОВЫЙ, не рантайм: собрать журнал из уже лежащих
                                  артефактов; отказывается писать поверх непустого журнала)

<plugin-data>/verif-homes/       (${CLAUDE_PLUGIN_DATA} — переживает обновление плагина;
                                  шаблоны едут в <plugin-root>/assets/verif-homes/ и
                                  разворачиваются сюда при первом запуске)
└── codex-home/
    ├── AGENTS.md                (Codex verifier policy: FACT/INFERENCE/SPECULATION)
    ├── config.toml              (единый профиль GPT-6 Astra, high; service_tier=default в плагине;
    │                             локальный пин priority — настройка получателя)
    └── auth.json                (symlink на ~/.codex/auth.json)
```

Артефакты прогона — в vault, `AI/verif/` (корень vault = `${user_config.VAULT_PATH}`): `{BASE}--{codex,fable,merged,findings,arbiter,decisions,delta}.json`, `{BASE}--verdict.md`. Там же журнал всех прогонов `_runs.jsonl` — только дозапись, по строке на прогон.

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
| Правило необратимости правки | `schema/arbiter.json` (`reversible`) + «Rules of evidence» в `system-prompts/arbiter.md` + таблица оснований в `interview-apply.md` A3.2 |
| Правило перепроверки правок, потолок кругов | `references/delta-recheck.md` + `system-prompts/delta-check.md` + `schema/delta.json` |
| Поля журнала запусков | `scripts/log_run.sh` (сборка строки) + `scripts/verif_stats.sh` (что считаем) |
