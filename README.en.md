English · [Русский](README.md)

# Your plan gets checked by the person who wrote it — and by the same model that wrote it

Two models from two different vendors tear into it separately, neither of them seeing the other's
answer, and an arbiter merges the findings into one list — before you have put anything into the plan.

```
claude plugin marketplace add https://github.com/beCyborg/jadlis-hub
claude plugin install jadlis-verif@jadlis
```

No keys needed — this is the only one in the line that does not need Brave and Firecrawl. What it
does need is one subscription of your own: ChatGPT — for Codex CLI.

![Columns of findings from the verifying models and the arbiter's merged common list](docs/img/hero-jadlis-verif.webp)

In words: separate readings of the same plan on the left and the arbiter's common list on the
right, where every finding carries an "accept / reject / rewrite" fork.

This is my workbench published as it is, not a product: whatever I stopped using, I removed.

## Before → after

| By hand | With an AI chat | With this plugin |
|---|---|---|
| **Who looks for the hole.** The plan is re-read by whoever wrote it — and finds typos instead of holes. | It is checked by the same model that wrote the plan. | Codex and Fable read the plan separately and do not see each other's answers. |
| **Whose frame the reviewer uses.** One head, one angle. | Your own frame, retold back to you: whatever you did not ask about is not there. | The two frames differ — so you also see what you never asked about. |
| **What to do with a heap of findings.** The list sits in your notes and goes stale. | You get one more long list, and half of the edits you roll back later. | The arbiter merges the findings into one list: what several found weighs more than what one wrote beautifully. |
| **How a finding becomes an edit.** By hand, if you ever get round to it. | Discussed and forgotten. | A batch interview over every finding: accept, reject or rewrite — and only then the edits. |
| **Who checks the edits themselves.** Nobody: made and forgotten. | The same model that made them — and it agrees with itself. | A different model re-reads the edits: is the finding closed, did anything next to it break. |
| **When the hole opens up.** During execution, when the money and the month are already in. | Same place. | Before. |

## How it works

![One plan goes to the verifying models separately, the arbiter merges the findings, you answer on each one, then the edits](docs/img/how-jadlis-verif.webp)

Going in — your plan as a single file.
Inside — Codex and Fable take it apart in parallel and do not see each other's answers; the
arbiter merges the findings into one list and raises whatever the readings agreed on.
Coming out — a walk through the findings: accept, reject or rewrite, and only what you accepted goes
into the edits. You pick how it goes: **auto** — the plugin applies the arbiter's calls itself and
asks only about the strong forks, at most four questions; **manual** — one question per finding.
The edits themselves are then re-read by a different model than the one that made them: is the
finding closed, did anything next to it break, was more rewritten than asked; if something turns
up, one round of corrections, and if it still does not settle, it tells you what is left.
If one of the two readings never happened, the plugin retries it once and then writes "coverage
partial" in the header and withholds "go ahead" — an incomplete check is never final.

In words: the plan → two readings separately → the arbiter merges them into one list → you choose
"auto" or "manual" → edits in the plan → a re-check of the edits.

<details>
<summary>If people did this · How it differs from Perplexity and ChatGPT Deep Research · An example</summary>

### If people did this

| Role | How many people | What the plugin does here |
|---|---|---|
| Independent reviewer | two, each with their own frame, seated in separate rooms | takes the plan apart with two models separately, with each one's answer hidden from the other |
| Arbiter | a separate person who merges both readings and removes duplicates | collects the findings into one list and raises what both agreed on |
| Review facilitator | a separate person who walks the list with you and records the decision | the findings walk-through: in auto mode it asks only about the strong forks, in manual mode about every finding |
| Editor | a separate person who puts what was accepted into the document | makes the edits after your decisions |

Nothing is said about money here, deliberately: I have not collected sources on what this kind of
work costs.

### How it differs from Perplexity and ChatGPT Deep Research

A comparison of mechanisms only — not of who deserves your trust.

| Mechanism | This plugin | Perplexity | ChatGPT Deep Research |
|---|---|---|---|
| Do several models take the text apart separately, without seeing each other's answers | yes, two models from two vendors | yes, in Model Council mode: three models in parallel | not documented |
| Are the divergences between the readings merged into one list | yes, by an arbiter | yes, a separate synthesiser model in Model Council | not documented |
| Is what is disputed marked apart from what was agreed | yes, agreed and single-voice findings are kept apart | yes, it shows where the models converged and where they diverged | not documented |
| Does a list of findings with your decision on each one survive | yes, after the batch interview | partly: findings along the way, no decision on them | partly: the plan is edited before the run, not the findings |
| Are primary sources checked on the web | switched on if `jadlis-search` is installed | yes | yes |

The plugin column was checked on 2026-09-07. The other columns were assembled the same day
from official documentation: [Model Council](https://www.perplexity.ai/hub/blog/introducing-model-council)
and [the Perplexity help centre](https://www.perplexity.ai/help-center/en/articles/13600190-what-s-new-in-advanced-deep-research),
[the OpenAI Deep Research help page](https://help.openai.com/en/articles/10500283-deep-research-faq).
"Not documented" means exactly that, and not "no". The first three Perplexity rows are about
Model Council mode, not about Deep Research: on its own it claims no multi-model review with an
arbiter.

### An example

You have a renovation plan: the order of the works, what you do yourself, where you economise, when
you move in. Two models read it separately. Codex picks at the order of the works: the screed and
its drying time come earlier than the delivery assumes. Fable finds something else: there is no
acceptance check after a stage anywhere in the plan, the rework will surface at the end — and it asks
about what is not in the plan at all, what happens if the contractor disappears for a week. The
arbiter merges this into one list and shows where both of them landed on the same thing. You walk the
list and on every finding you say: accept, reject, rewrite. Only what was accepted goes into the plan
— before the materials arrive.

</details>

## Installing and the first run

**a) Text to paste to an agent.** Copy the whole thing into a Claude Code chat:

```
You are the installer. Install the plugin jadlis-verif from the jadlis marketplace on this Mac.
First check that Claude Code is installed and the subscription is active, and that Codex CLI is
on the machine. Tell me "present" or "absent" for each — never print tokens or the
contents of config files.
If Codex CLI is missing — stop and tell me: it does not work without it.
Then run exactly these commands, verbatim, shortening nothing:
1. claude plugin marketplace add https://github.com/beCyborg/jadlis-hub
2. claude plugin install jadlis-verif@jadlis
3. claude plugin list — show me the line about jadlis-verif and its version.
Do not ask me for API keys: this plugin does not need them, and write no keys into any config.
Before each command show it to me in full and wait for "yes". If I say "no", do not run it.
If a command returns an error, stop, show me the output, and do not move to the next one.
```

**b) Commands by hand.**

```
claude plugin marketplace add https://github.com/beCyborg/jadlis-hub
claude plugin install jadlis-verif@jadlis
claude plugin list
```

The first command installs nothing — it adds the marketplace. Only the second one installs, and one
line removes it: `claude plugin uninstall jadlis-verif@jadlis --keep-data`.

**c) The short command.** Open Claude Code in the folder where the plan lives and type:

```
/verif <path to the file with the plan>
```

If it is not found, check the name with `claude plugin list`. Make the first review a plan you have
not put anything into yet: the point is for the hole to open up before the money, not after.

## Limits, cost, updating

**What it does not do.** It does not write the plan for you — it only tears into the one written. It
does not make the decisions on the findings: accept, reject or rewrite is yours to say, and only what
was accepted goes into the edits. It does not check primary sources on the web by itself: the web
check switches on additionally if you have `jadlis-search` installed. And the main thing: two readings
agreeing is two readings agreeing, not proof. The arbiter shows where both of them converged and
where one voice was left against the other; the decision is still yours.

**What you need.** No keys — this is the only one in the line that does not need Brave and Firecrawl.
What it does need is one subscription of your own: ChatGPT — for Codex CLI. Checked on Codex CLI
0.153.4 (2026-09-07); below that version I have not tested it.

**How tokens get spent.** A heavy run — dozens of subagents out of your own quota; several runs back
to back do not fit into one window. Part of the work goes into your ChatGPT subscription,
part into the Claude Code quota. Plan a review as its own task for a session, not as a quick question
on the side. What it costs in money I have not measured and will not name a figure.

**Verified where I work:** my Mac, my subscriptions. I have not tested it on anyone else's machine —
if it did not install for you, open an issue in the repository.

**Terms of use.** There is no license: all rights reserved by the author. You may read it and use it
personally. Commercial use, republishing and bundling it into your own products — by arrangement
with me.

**Updating.** With a third-party marketplace, auto-update is off on your side: until you run the
first command you keep the version you installed.

```
claude plugin marketplace update jadlis
claude plugin update jadlis-verif@jadlis
claude plugin list
```

Reinstall, if something ended up crooked:

```
claude plugin uninstall jadlis-verif@jadlis --keep-data && claude plugin install jadlis-verif@jadlis
```
