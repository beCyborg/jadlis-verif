# TESTS.md — verif (v6)

Живые зависимости: `codex` CLI (ChatGPT-подписка), `claude` CLI (headless), `grok` CLI (X-подписка), jq.

| Capability | State | Last run | Notes |
|---|---|---|---|
| Fable 5 headless + производная Claude-схема → structured_output | PASS | 2026-07-02 | смоук: mini + полная verdict-схема после jq-стрипа |
| Полная verdict.json БЕЗ стрипа на claude CLI | FAIL | 2026-07-02 | ожидаемо: minLength/minimum/maximum + корневые $schema/$id/title тихо отключают structured_output — поэтому prelude делает производную схему |
| Grok --json-schema (mini + полная verdict.json, union-типы) | PASS | 2026-07-10 | structured JSON в `.structuredOutput` (camelCase, top-level). Пере-смоук на grok-4.5 + `--effort high`: mini-схема, ~8s |
| Grok web_search без --sandbox (продовый allowlist) | PASS | 2026-07-10 | РОВНО `read_file,grep,list_dir,web_search,web_fetch` + `--disallowed-tools run_terminal_cmd`; одиночный `--tools web_search` ломает сборку агента. Пере-смоук на grok-4.5 + `--effort high`: полный Bash C (allowlist + verdict.json + web_search) → валидный `.structuredOutput` за ~15s |
| Изолированный GROK_HOME (config.toml + auth symlink) | PASS | 2026-07-10 | CLI дописывает marketplace-состояние в config — не чинить |
| Grok web_fetch не заблокирован deny из ~/.claude/settings.json (HOME-изоляция) | PASS | 2026-07-10 | Без `HOME=$GROK_ISO_HOME` grok наследует `permissions.deny: ["WebFetch"]` → «Denied by permission policy: deny rule on web_fetch». `--allow web_fetch` и `GROK_WEB_FETCH=1` НЕ перебивают (deny > allow). С изоляцией: Bash C дочитывает страницу, verdict валиден. `web_search` не затронут |
| merge_verdicts.sh: 3 провайдера / 2 (деградация) / битый JSON → stub / дубликаты меток | PASS | 2026-07-02 | юнит-тесты на синтетике |
| render_merged.sh: динамический рендер по providers | PASS | 2026-07-02 | 3 и 2 провайдера |
| Арбитр: arbiter.json schema + arbiter.md на Fable 5 | PASS | 2026-07-02 | синтетические находки; оба F-id покрыты; выявил stdin-warning баг → `< /dev/null` |
| big-file guard (>350 KB → claude-opus-5) | PASS | 2026-07-02 | bash-логика на 400KB файле |
| Codex e2e (gpt-5.6-sol, --output-schema, xhigh, service_tier=default) | PASS | 2026-07-10 | ВАЖНО: exec пишет лог в stdout, verdict — ПОСЛЕДНЕЙ строкой → нормализация tail -1 (источник старых codex.clean.json). Смоук на codex-cli 0.144.1: валидный verdict за ~10s |
| Полный тройной e2e: 3 верификатора → merge → render на реальном плане | PASS | 2026-07-02 | precious-strolling-hopper: 6+10+9 находок, дедуп 25→21, consensus needs-revision |
| Арбитр e2e на реальных находках (21 F-id, анонимизация A/B/C) | PASS | 2026-07-02 | 21/21 покрытие, 0 лишних id; калибровка severity вниз; 1 refuted с контр-доказательством; спор codex --search разрешён локальной перепроверкой |
| Grok-деградация: сбой детектится (exit 1, лог вместо JSON) → dual-merge без stub | PASS | 2026-07-02 | битый auth → exit 1; dual-merge codex+fable: providers=[codex,fable], grok отсутствует |
| --only grok single-рендер | PASS | 2026-07-02 | direct render без merge на e2e-артефакте |
| Fable fallback-цепочка (claude-opus-5 с производной схемой) | CODED-NOT-VERIFIED | — | opus без стрипа падал (как и Fable); со стрипом не гонялся |

## Gate

Перед объявлением v6 рабочим / изменением внешних шагов — PASS обязательны для строк:
«Полный тройной e2e», «Grok-деградация», «--only grok single-рендер», плюс все уже-PASS строки повторно при смене версий CLI (`codex`, `claude`, `grok --version`).
