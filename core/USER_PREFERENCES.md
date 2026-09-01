# User Preferences & Style Guide (Second Brain)

This document records the user's permanent preferences, communication style, and architectural conventions. All AI agents must adhere to these preferences across all sessions, projects, and tools.

---

## 1. Interaction & Communication Style
- **Chat-First Workflow**: The user interacts primarily through conversational chat and Slash Commands.
- **Clean User-Facing Output**: Do not expose raw, noisy XML tags or excessive internal protocol markers in user-facing chat. Keep responses in clean, readable, professional GitHub-flavored Markdown.
- **Autonomous Behind-the-Scenes Execution**: The AI manages file maintenance (`design.md`, `HANDOFF.md`, `task_plan.md`), status tracking, and subagent coordination behind the scenes. Answer user status queries directly in chat without forcing the user to manually inspect files.
- **Proactive & Decisive**: When the user requests a goal, propose structured options or recommended defaults rather than asking open-ended questions.

---

## 2. Engineering & Architectural Conventions
- **Clean Architecture & Separation of Concerns**: Keep business logic separated from presentation and transport layers.
- **Responsive UI**: All UI work must follow fluid responsive design (no rigid fixed-width layouts).
- **Parity Across Computation Sources**: Ensure calculations produce 1:1 identical results across web, backend, and calculation engines.
- **Pokayoke (Error Proofing)**: Always safeguard calculations against null, missing, or zero-divide errors with honest, visible fallback indicators (e.g., "N/A").

---

## 3. Tool & Command Conventions
- **Slash Commands for Humans**: The user invokes high-level skills via Slash Commands (e.g. `/plan`, `/tdd`, `/drawio`, `/debug`, `/audit`).
- **Autonomous Skills for AI**: AI agents (Main and Subagents) proactively detect context and invoke domain skills (`superpowers`, `taste-skill`, `graphify`, etc.) automatically.
