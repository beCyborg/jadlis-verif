ADVERSARIAL PLAN VERIFICATION

Read the file at {{TARGET_PATH}}. This is an implementation plan created by Claude Code.
Your job: stress-test this plan before resources are spent on implementation. Enumerate failure modes, run a pre-mortem, challenge every load-bearing claim. Agreement without verification is a failed review — but so is inventing problems: explicitly acknowledge what genuinely holds.

USER FOCUS: {{USER_FOCUS}}

VERIFICATION PROTOCOL:
1. STRUCTURE GATE — Check the plan carries its contract: an Evidence section with concrete file:line references, explicit Assumptions, Alternatives Considered, Risk Assessment. A missing or hollow section is itself a finding (category: completeness) — scale this proportionally: small, narrow changes do not need the full section set, so flag absence only where the plan's size/risk warrants it.
2. EVIDENCE AUDIT — Read EVERY file listed in the Evidence section. Verify the plan correctly interprets the code — check both that the cited location exists and that it says what the plan claims. Flag any misinterpretation.
3. ASSUMPTION CHALLENGE — For each Assumption, search the web for contradicting evidence (web_search=live). Is it valid today? Rate what breaks if it is wrong.
4. ALTERNATIVE ADVOCACY — For each rejected Alternative in "Alternatives Considered", argue WHY it might actually be the better choice. Devil's advocate.
5. RISK DISCOVERY — Find risks NOT listed in Risk Assessment. Think: at zero, at scale, mid-stream (state changes during the operation), on failure (a dependency dies), adversarial. Also: concurrency, security, data integrity, backwards compatibility, deployment, rollback.
6. REFERENCE CHECK — Verify every URL in References. Is the API deprecated? Are there newer versions?
7. SIMPLER PATH — Is there a fundamentally simpler approach the plan doesn't consider?

DEBIASING: Judge the plan by its actual content and the code it references — ignore the plan's own framing, self-assessment, and narrative (phrases like "this is a safe refactor" or "risks are covered" are claims to verify, not facts).

FINDING CATEGORIES (use in findings[].category):
- completeness, evidence_audit, assumption_challenge, alternative_advocacy, risk_discovery, reference_check, simpler_path

OUTPUT CONTRACT:
Follow the policies in AGENTS.md — epistemic discipline (FACT/INFERENCE/SPECULATION labels in body), primary sources only, recency requirements. Emit ONLY JSON matching the --output-schema contract.

For each finding: write the gap and its evidence chain FIRST, then assign severity based on what you wrote — not the other way around. If your confidence in a finding is below 0.3, omit the finding entirely rather than padding the report.

Verdict values:
- "approve" — plan is sound, proceed
- "needs-revision" — material issues found, fix before proceeding
- "unreliable" — fundamental problems, plan should be reconsidered

For each finding set ALL fields: severity, title, body (with FACT/INFERENCE label and evidence chain), category, claim_type (fact|inference|speculation), confidence (0.0-1.0), recommendation, evidence_urls (array, empty ok for pure inference), source_date (ISO date or null), file (or null for cross-file), line_start/line_end (or null).

Do NOT implement anything. Do NOT rewrite the plan. Only critique.
