# verif — Фаза C (перепроверка правок)

Читается после Фазы B, когда в ней что-то реально применено. Правки проверяет **другое
семейство моделей**, чем то, что их вносило: субагенты-исправители — Claude, перепроверяет
Codex. Причина в ресёрче «Состязательная верификация»: самопроверка возвращается
«подавляюще подтверждающей, а не исправляющей», а агент-автор соглашается с ревьюером даже
когда его просят спорить.

Один ограниченный проход, не петля: `MAX_FIX_ROUNDS = 2` (первый проход + один круг доправок
с повторной проверкой). Не сошлось на втором — отчёт человеку, третьего круга нет.

## Когда шаг пропускается

Молча, одной строкой в сводке («Перепроверка правок: пропущена — {причина}»):

- нет принятых находок (все решения `skipped`) или Фаза B ничего не применила;
- `--report-only`, `--json`, `--only codex|fable` — эти режимы до Фазы B не доходят вовсе;
- новый флаг `--no-recheck`;
- нет ни `codex`, ни рабочей Fable-ветки (см. «Деградация»).

## C0 (в Фазе B, ДО запуска субагентов): снимки целевых файлов

Цели обычно лежат вне git (vault), поэтому дифф строим сами — по снимку, а не по индексу.
Один foreground Bash перед fan-out субагентов, по списку целевых файлов Фазы B:

```bash
SNAP_DIR=$(mktemp -d -t verif-snap.XXXXXX)
for f in {список целевых файлов Фазы B}; do
  cp "$f" "$SNAP_DIR/$(printf '%s' "$f" | shasum -a 256 | cut -c1-16).snap"
done
echo "SNAP_DIR=$SNAP_DIR"
```

Имя снимка — первые 16 символов sha256 от абсолютного пути: короткое, без коллизий на
практике и вычисляется одинаково до и после правок. Файл, которого в C0 ещё не было
(субагент создаёт его) — снимка нет, в C1 он пойдёт как целиком новый.

## C1: дифф и замороженный список

```bash
DELTA_DIFF=$(mktemp -t verif-delta-diff.XXXXXX.diff)
for f in {те же файлы}; do
  SNAP="$SNAP_DIR/$(printf '%s' "$f" | shasum -a 256 | cut -c1-16).snap"
  [[ -e "$SNAP" ]] || SNAP=/dev/null
  diff -u --label "$f (до правок)" --label "$f" "$SNAP" "$f" >> "$DELTA_DIFF" || true
done
wc -l "$DELTA_DIFF"
```

`diff` возвращает 1 при различиях — это норма, поэтому `|| true`. Заголовки — через `--label`,
а не `sed`: у BSD sed нет `\|`, замена молча не срабатывала бы и в диффе стояли бы имена снимков. Дифф пуст → правок не было,
шаг пропускается.

Замороженный список — принятые находки, как их решили, без последующих переформулировок:

```bash
DELTA_FROZEN=$(mktemp -t verif-delta-frozen.XXXXXX.json)
jq -n --slurpfile d "$DECISIONS_OUT" --slurpfile f "$FINDINGS_OUT" '
  ($f[0] | map({key: .id, value: .}) | from_entries) as $byid
  | $d[0] | map(select(.decision == "applied" or .decision == "custom"))
  | map({id, title, file,
         instruction: (if .decision == "custom" then .custom_instruction
                       else ($byid[.id].recommendation // "") end)})' > "$DELTA_FROZEN"
```

## C2: вызов перепроверяющего

Промпт собирается Write во временный файл `DELTA_PROMPT_FILE`
(`mktemp -t verif-delta-prompt.XXXXXX`): содержимое `system-prompts/delta-check.md`, затем
блок данных. Схема — `schema/delta.json` (она сразу совместима и с `--output-schema` Codex, и с
`--json-schema` claude: запрещённых ключей нет, производную делать не нужно).

```
EDITED FILES:
{абсолютные пути, по строке}

FROZEN ACCEPTED FINDINGS (id, title, file, instruction):
{содержимое $DELTA_FROZEN}

DIFF OF THE APPLIED EDITS (unified, snapshot → current):
{содержимое $DELTA_DIFF}

Answer the three questions per your role instructions. Return one `closed` entry per id above.
```

Запуск — тот же шаблон Bash A, что у Codex-ветки (Шаг 5 SKILL.md), `run_in_background: true`,
timeout 600000, песочница только на чтение:

```bash
CODEX_HOME="{CODEX_HOME_DIR}" codex exec \
  -m "{CODEX_MODEL}" \
  --sandbox read-only \
  --skip-git-repo-check \
  --output-schema "{DELTA_SCHEMA_PATH}" \
  -c model_reasoning_effort="{EFFORT_CODEX}" \
  -c service_tier="default" \
  - < "{DELTA_PROMPT_FILE}" > "{DELTA_OUT}.raw" 2>&1
```

Нормализация ответа — тот же каскад, что у основной ветки: `bash
"${CLAUDE_PLUGIN_ROOT}/skills/verif/scripts/normalize_and_merge.sh"` сюда не годится (он про
verdict-схему), поэтому короткий разбор на месте — питоновская третья ступень нужна и здесь,
потому что Astra печатает финальный JSON многострочным блоком после лога:

```bash
python3 - "{DELTA_OUT}.raw" "{DELTA_OUT}" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
dec = json.JSONDecoder()
for i in range(len(raw) - 1, -1, -1):
    if raw[i] != "{":
        continue
    try:
        obj, _ = dec.raw_decode(raw[i:])
    except Exception:
        continue
    if isinstance(obj, dict) and obj.get("status"):
        json.dump(obj, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
        sys.exit(0)
sys.exit(1)
PY
```

Разбор удался — `rm -f "{DELTA_OUT}.raw"`; не удался — сырой вывод остаётся для диагностики.

### Деградация

Codex упал / не дал разбираемого JSON → **один** откат на Fable headless тем же промптом
(`delta_by: fable` в журнале; то же семейство, что у исправителя, — это осознанно худший, но
живой вариант):

```bash
claude -p "$(cat "{DELTA_PROMPT_FILE}")" \
  --model "{FABLE_MODEL}" \
  --effort {EFFORT_FABLE} \
  --output-format json \
  --json-schema "$(cat "{DELTA_SCHEMA_PATH}")" \
  --allowedTools "Read,Grep,Glob" \
  < /dev/null > "{DELTA_OUT}.raw" 2>&1
```

Извлечение — `.structured_output` из `sed -n '/^{/,$p'`, как в Arb-3. Упал и он →
`delta_by: none`, в сводке строка «Перепроверка правок: не выполнена ({что видел})».
Прогон на этом не блокируется: правки уже применены, человек просто знает, что их никто не
перечитал.

## C3: круг доправок

- `status: clean` и обе таблицы пусты → конец, в сводке «Перепроверка правок: чисто».
- Иначе — **один** круг: те же субагенты по тем же файлам (один файл = один субагент, как в
  Фазе B), в промпте только список проблем из `$DELTA_OUT` (`closed` со значением `no`/`partial`,
  `regressions`, `scope_creep`) с цитатами; правки минимальные, новых улучшений не вносить.
  Новый снимок НЕ делается: дифф второго прохода строится от тех же снимков C0, чтобы
  перепроверяющий видел весь путь от исходного файла.
- Перед повторным C2 сохранить итог первого прохода: `cp "$DELTA_OUT" "${DELTA_OUT%.json}.round1.json"` —
  журнал считает `fix_regressions` по первому проходу, а `fix_regressions_left` по последнему.
- После круга — повторный C2 (`FIX_ROUND=2`). Что осталось после него — в отчёт человеку,
  простым языком по `references/plain-language.md`, по строке на проблему. Третьего круга нет.

`scope_creep` сам по себе круг доправок не запускает, если `closed` везде `yes` и регрессий
нет: лишний абзац — повод сказать человеку, а не повод снова править файл. Решает это правило,
а не модель.

## Артефакт и сводка

`$DELTA_OUT` = `AI/verif/{BASE}--delta.json` — итог ПОСЛЕДНЕГО прохода C2. Одна строка в
финальной сводке, после строк интервью и применения:

```
Перепроверка правок: чисто
Перепроверка правок: 3 проблемы, доправлено 2 — осталось 1
Перепроверка правок: пропущена — нечего перепроверять
Перепроверка правок: не выполнена (Codex и Fable не ответили)
```

Числа берутся из `$DELTA_OUT` детерминированно: проблемы = `closed[] | select(.closed != "yes")`
плюс `regressions` плюс `scope_creep`; «осталось» — то же самое после второго прохода.
