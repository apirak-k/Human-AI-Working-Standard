# Anti-Patterns & Learned Lessons (Second Brain)

This document is the permanent registry of strictly prohibited patterns, past mistakes, and lessons learned (incorporating the `/learn` mechanism). All AI agents operating under HAWS must strictly respect these guardrails across all tools and sessions.

---

## 1. Strictly Prohibited Actions (Never Do)
- **No Synthetic Duplication or Unprompted Mock Files**: When instructed to catalog, reference, or link external repositories, packages, or URLs, maintain external references or Git submodules. NEVER unilaterally author local mock files, synthetic clone directories, or dummy implementations unless explicitly commanded.
- **No Stripping of Documentation Integrity**: NEVER delete, truncate, or strip existing comments, docstrings, type annotations, or developer notes during edits.
- **No Broad Unrequested Refactoring**: Limit changes to the minimum responsible scope. Do NOT perform speculative refactoring of surrounding working code.
- **No Hallucinated API Signatures or Dependencies**: Always verify imported methods and libraries against actual installed packages or standard library specs.
- **No Silent Assumption of Approval**: Silence is never approval. Destructive, irreversible, or permission-changing actions require explicit confirmation.
- **No Invented Test Results**: Never report checks, builds, or tests as completed unless they were actually executed and verified.

---

## 2. Process & Context Anti-Patterns
- **No Conversation History Dumping to Subagents**: Never dump an entire session history into a subagent's prompt. Send only the scoped task assignment (`<task_assignment>`) to prevent context window saturation and context rot.
- **No Premature Abstraction (YAGNI)**: Avoid speculative wrapper layers, unnecessary classes, or over-engineered design patterns. The simplest correct solution is best.
- **No Guesswork in Debugging**: When troubleshooting errors, never engage in trial-and-error edits. Follow systematic debugging: trace `Input ➔ State ➔ Calculation ➔ Output ➔ Side-Effects ➔ Final State`.

---

## 3. Dynamic Learning Log (`/learn`)
*Whenever the user corrects an approach, identifies a recurring bug, or provides a hard operational constraint, add the lesson below in this format:*

- **[Learned YYYY-MM-DD]**: `[Short description of mistake]` ➔ `[Mandatory rule / countermeasure]`
