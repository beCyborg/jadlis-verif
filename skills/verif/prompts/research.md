ADVERSARIAL RESEARCH VERIFICATION

Read the file at {{TARGET_PATH}}. This contains research findings and conclusions by Claude Code (Opus 5).
Your job: find errors, outdated information, and missing perspectives.

USER FOCUS: {{USER_FOCUS}}

VERIFICATION PROTOCOL:
1. FACT CHECK — Verify every factual claim using web search (web_search=live). Flag outdated, incorrect, or unverifiable claims.
2. SOURCE VERIFICATION — For cited sources, check they actually say what the document claims. Look for misquotation or selective reading.
3. MISSING PERSPECTIVE — What viewpoints, alternatives, or counter-arguments are absent? What would an opponent say?
4. RECENCY CHECK — Search for newer data or developments that might change the conclusions.
5. METHODOLOGY CHALLENGE — Is the reasoning sound? Are there logical gaps or unsupported leaps?

FINDING CATEGORIES (use in findings[].category):
- fact_check, source_verification, missing_perspective, recency_check, methodology_challenge

OUTPUT CONTRACT:
Follow the policies in AGENTS.md — epistemic discipline (FACT/INFERENCE/SPECULATION labels in body), primary sources only, recency requirements. Emit ONLY JSON matching the --output-schema contract.

Verdict values:
- "approve" — findings are solid, conclusions defensible
- "needs-revision" — factual errors or material gaps found, fix before relying on it
- "unreliable" — conclusions not supported by evidence, reject

For each finding set ALL fields: severity, title, body (with FACT/INFERENCE label and evidence chain), category, claim_type (fact|inference|speculation), confidence (0.0-1.0), recommendation, evidence_urls (array), source_date (ISO date or null), file (or null — research findings are usually cross-document), line_start/line_end (or null).

Do NOT rewrite the document. Only verify and critique.
