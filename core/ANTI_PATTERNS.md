# Anti-Patterns & Learned Lessons (Second Brain)

This document is the permanent registry of strictly prohibited patterns, past mistakes, and lessons learned (powered by autonomous continuous learning across all AI platforms). All AI agents operating under HAWS must strictly respect these guardrails across all tools and sessions.

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

## 3. Dynamic Learning Log (Autonomous Cross-Platform Learning)
*Learning is an inherent, cross-platform objective across all AI environments (Claude Code, Antigravity, Cursor, ChatGPT, etc.). Whether triggered natively through conversational feedback, active learning skills, or tool-specific commands (such as `/learn`), the AI must autonomously capture and preserve lessons below in this format:*

- **[Learned 2026-09-01]**: `Unannounced heavy network pulls / submodule downloads` ➔ **NEVER unilaterally run heavy background clones or submodule downloads without explicit user approval and clear communication of download time/size.**
- **[Learned 2026-09-01]**: `Artificial skill renaming and prefix distortion` ➔ **ALWAYS preserve exact upstream skill names from YAML frontmatter (`name:`) or folder names without inserting artificial prefixes (e.g. keep `brainstorming`, never rename to `superpowers-brainstorming`).**
- **[Learned 2026-09-01]**: `Perspective shifting during architectural explanations` ➔ **ALWAYS clearly distinguish between "HAWS configuration mode" (editing `E:\Human-AI-Working-Standard`) vs "Project execution mode" (working in `D:\Project-A`) to avoid user confusion.**
- **[Learned 2026-09-01]**: `Multi-platform execution friction` ➔ **ALWAYS maintain a zero-friction Universal 1-Way Standard (`haws.sh`) executable across all operating systems via standard Bash/Git Bash that performs all operations (Git Pull, Submodules, Linking, Auto-Prune) in a single unified action.**
- **[Learned 2026-09-02]**: `Unilateral file deletion & assumption` ➔ **NEVER delete, prune, or discard any files without presenting an explicit candidate list to the user and waiting for direct user deletion instructions first.**
- **[Learned 2026-09-02]**: `Handoff hallucination & synthetic rule invention` ➔ **NEVER invent synthetic rules, numerical thresholds (e.g. "100-skills limit"), or tool-locked constraints in HANDOFF.md or session summaries that the user never commanded. Second Brain files (`USER_PREFERENCES.md` / `ANTI_PATTERNS.md`) are the permanent single source of truth for user intent.**
- **[Learned 2026-09-02]**: `Passive silence on junk, bloat, and redundant files` ➔ **NEVER remain silent when identifying obsolete, duplicate, or token-bloating files. Proactively inspect, present the candidate list to the user in chat, and request approval before deleting.**
- **[Learned 2026-09-02]**: `Dogmatic 5-drawer lock` ➔ **NEVER force-fit skills into an arbitrary fixed number of drawers. Empower `@organizer` to structure and adapt categories dynamically based on real practical workflows.**
- **[Learned 2026-09-02]**: `Performative skill tagging without actual protocol execution` ➔ **NEVER use hollow cosmetic tags (e.g. `[Auto-Skill: ...]`). Execute the actual rigorous workflow of the skill and transparently state the active Slash Command.**
- **[Learned 2026-09-02]**: `Unchecked heavy remote pulls in routine commands` ➔ **NEVER trigger slow network pulls (e.g. `git submodule update`) blindly during routine status/update checks. ALWAYS perform a sub-second local check first (`bash haws.sh status`); if the local environment is already 100% healthy and in sync with no new commits, EXIT IMMEDIATELY (< 0.3s) without wasting user time.**
- **[Learned 2026-09-02]**: `Ad-hoc authoring of skills without invoking skill standards` ➔ **NEVER bypass official skill-authoring standards to write ad-hoc 10-line stubs. ALWAYS ground custom skills in Anthropic's `skill-creator` / `writing-skills` guidelines — defining explicit trigger boundaries, progressive disclosure, deterministic multi-platform commands, and test verification.**
- **[Learned 2026-09-02]**: `Unbridged custom skills missing Slash Command integration` ➔ **NEVER leave custom in-house skills (`skills/custom/`) isolated from chat autocomplete. ALWAYS auto-generate the corresponding Slash Command wrappers (`~/.claude/commands/<name>.md` and Antigravity workspace `.agents/skills` / `.agents/workflows`) so users can immediately invoke them via `/<name>`.**
- **[Learned 2026-09-03]**: `Unilateral Git Push to Remote Repository` ➔ **NEVER run `git push` to GitHub or any remote repository autonomously without explicit user confirmation in chat. Local git commits and working tree edits are permitted, but publishing to remote is strictly reserved for human authorization.**
- **[Learned 2026-09-03]**: `Antigravity Windows NTFS Junction Incompatibility` ➔ **NEVER rely on Windows NTFS Directory Junctions (`mklink /J`) for Google Antigravity skill discovery in `~/.gemini/config/skills/`. Antigravity's language server skips Reparse Points / Junctions, causing 0 skills to load and dropping slash commands. ALWAYS use Antigravity's official native `~/.gemini/config/skills.json` declarative configuration, which provides true 100% Zero Duplication, requires zero Administrator privileges, and traverses cleanly across drives.**
- **[Learned 2026-09-03]**: `Unexplained Token Thresholds in Status` ➔ **NEVER display arbitrary numerical budget caps (e.g. 20,000 tokens) in status outputs without transparently explaining their origin and rationale. The 20,000 token limit is the lowest common denominator safety ceiling (derived from Antigravity/Claude prompt customization truncations) to prevent skills from being silently dropped across any AI platform.**
- **[Learned 2026-09-03]**: `Destructive Testing on Live User Configurations` ➔ **NEVER execute destructive or modifying commands (such as `sync --clean`, file purges, or link removals) directly against user production directories during QA/tester runs. ALWAYS enforce `--dry-run` or test within isolated temporary sandboxes (`mktemp -d`) to protect user environments from unintended side-effects.**
- **[Learned 2026-09-04]**: `Uncommitted .env Secrets & Missing Schema Validation` ➔ **NEVER commit `.env` or sensitive credentials to Git. ALWAYS ignore `.env*` in `.gitignore`, provide `.env.example` with safe placeholder values, and enforce fail-fast startup schema validation (Zod/Pydantic) before application boot.**
- **[Learned 2026-09-04]**: `CRLF Line Ending Pollution on Windows` ➔ **NEVER commit text or code files with CRLF line endings. ALWAYS enforce LF via `.gitattributes` and verify line endings with `haws.sh doctor` to prevent phantom Git diffs.**
- **[Learned 2026-09-04]**: `Silent Test Suppressions & Artificial Green Builds` ➔ **NEVER silence lint or compiler errors (`@ts-ignore`, `eslint-disable`) or skip/delete tests to make a build look green. True completion requires 100% genuine pass with exit code 0.**
- **[Learned 2026-09-04]**: `Unbounded Trial-and-Error Repair Loops` ➔ **NEVER loop indefinitely when attempting automated bug fixes. Limit autonomous attempts to a maximum of 3 bounded iterations; if still failing, halt immediately, report diagnostic evidence, and consult the human engineer.**
- **[Learned 2026-09-04]**: `Unannounced Skill Invocation & Silent Subagents` ➔ **NEVER execute skills without top-line transparency. ALWAYS declare `Applying /<skill-name> (<reason>)...` on the first output line, and ensure all subagents include invoked skills in their `<task_report>`.**


