# User Preferences & Style Guide (Second Brain)

This document records the user's permanent preferences, communication style, and architectural conventions. All AI agents must adhere to these preferences across all sessions, projects, and tools.

---

## 1. Interaction & Communication Style
- **Language Preference**: Respond in concise, direct, jargon-free Thai in chat conversations. All files, codebase files, documentation, specifications, commit messages, status reports, and technical artifacts must be written strictly in 100% professional English with zero Thai text.
- **Chat-First & Conciseness**: The user interacts primarily through conversational chat and Slash Commands. Be concise, direct, and eliminate polite conversational filler.
- **Clean User-Facing Output**: Do not expose raw, noisy XML tags or excessive internal protocol markers in user-facing chat. Keep responses in clean, readable, professional GitHub-flavored Markdown.
- **Autonomous Behind-the-Scenes Execution**: The AI manages file maintenance (`DESIGN.md`, `HANDOFF.md`, `task_plan.md`), status tracking, and subagent coordination behind the scenes. Answer user status queries directly in chat without forcing the user to manually inspect files.
- **Proactive & Decisive**: When the user requests a goal, propose structured options or recommended defaults rather than asking open-ended questions.

---

## 2. Engineering & Architectural Conventions
- **Clean Architecture & Separation of Concerns**: Keep business logic separated from presentation and transport layers (e.g. React Custom Hooks separated from JSX).
- **Responsive UI & Design Tokens**: All UI work must follow fluid responsive design and adhere strictly to `DESIGN.md` tokens.
- **Parity Across Computation Sources**: Ensure calculations produce 1:1 identical results across web, backend, and calculation engines.
- **Pokayoke (Error Proofing)**: Always safeguard calculations against null, missing, or zero-divide errors with honest, visible fallback indicators (e.g., "N/A").

---

## 3. Tool & Command Conventions
- **Slash Commands for Humans**: The user invokes high-level skills via Slash Commands (e.g. `/grill-me`, `/planning-with-files`, `/boost`).
- **Autonomous Skills for AI**: AI agents proactively detect context and invoke domain skills across the 5 drawers in `SKILL_TAXONOMY.md`.
- **Cross-Platform Autonomous Self-Learning**: The AI must inherently and continuously learn on its own across all AI platforms (Claude Code, Antigravity, Cursor, ChatGPT, etc.). If a platform-specific learning command or active skill is available (e.g. `/learn`), use it; otherwise, the AI autonomously captures user corrections, feedback, and operational constraints directly into the Second Brain without being hardcoded to any single tool's slash syntax.
- **Anthropic Skill Standard for Authoring**: When creating custom in-house skills from scratch, AI agents MUST follow Anthropic's **`skill-creator`** / **`writing-skills`** specification as the official standard — enforcing YAML frontmatter with explicit trigger boundaries, multi-level progressive disclosure (`SKILL.md` + `references/`), deterministic procedural steps, and trigger benchmarking before finalizing.


