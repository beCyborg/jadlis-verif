[Русский](README.md) · English

# verif — Claude Code plugin

Command: `/verif`.

## Было → стало

To be written (README contract 2026-09, phase 3).

## Как это работает

Codex, Fable и Grok порознь рвут план или документ, арбитр сводит находки, батч-интервью, правки. Автономен: нужны Codex CLI (подписка ChatGPT) и Grok CLI; веб-проверка первоисточников — через плагин search, если он установлен.

Web checks inside the Fable verifier use the `search` plugin tools (Brave, Firecrawl) when it is installed; without it verif runs on Codex and Grok only.

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
