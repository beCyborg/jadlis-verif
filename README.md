Русский · [English](README.en.md)

# Три модели рвут твой план порознь до того, как ты в него вложился

Плагин `verif` для Claude Code. Команда — `/verif`.

## Было → стало

Раздел заполняется по контракту README 2026-09 (фаза 3 плана «GitHub beCyborg как витрина Jadlis»).

## Как это работает

Codex, Fable и Grok порознь рвут план или документ, арбитр сводит находки, батч-интервью, правки. Автономен: нужны Codex CLI (подписка ChatGPT) и Grok CLI; веб-проверка первоисточников — через плагин search, если он установлен.

## Установка и первый запуск

```bash
claude plugin marketplace add https://github.com/beCyborg/jadlis-start.git
claude plugin install verif@jadlis
```

## Границы, стоимость, обновление

```bash
claude plugin marketplace update jadlis
claude plugin update verif@jadlis
claude plugin list
```

Переустановка: `claude plugin uninstall verif@jadlis --keep-data && claude plugin install verif@jadlis`.
