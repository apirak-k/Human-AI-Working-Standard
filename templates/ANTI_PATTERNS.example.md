# Permanent Anti-Patterns & Operational Safeguards (Template)

This document records strictly prohibited patterns and past mistakes.
When initializing HAWS on a new machine, copy this file to `secondbrain/ANTI_PATTERNS.md` and add learned constraints.

---

## 1. Foundational Anti-Patterns & Prohibitions

- **[Standard Invariant]**: `Uncommitted Environment Secrets (.env)` ➔ **NEVER commit `.env` or files containing plaintext credentials to git. Always use `.env.example`.**
- **[Standard Invariant]**: `Windows CRLF Line Ending Drift` ➔ **NEVER commit CRLF line endings. All text files must be normalized to LF.**
- **[Standard Invariant]**: `Silent Test Suppressions & Artificial Green Builds` ➔ **NEVER silence lint/compiler errors (`@ts-ignore`, `eslint-disable`) or skip/delete tests to make a build look green.**
- **[Standard Invariant]**: `Unbounded Trial-and-Error Repair Loops` ➔ **NEVER loop indefinitely when attempting automated bug fixes. Limit autonomous attempts to a maximum of 3 bounded iterations.**
- **[Standard Invariant]**: `Unannounced Skill Invocation` ➔ **NEVER execute skills without top-line transparency. ALWAYS declare `Applying /<skill-name> (<reason>)...` on line 1.**
- **[Standard Invariant]**: `Hallucinating Skill Names` ➔ **NEVER invent non-existent skill names or pretend to execute skills.**