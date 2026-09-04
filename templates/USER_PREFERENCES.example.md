# User Preferences & Style Guide (Second Brain Template)

This document records the user's permanent preferences, communication style, and architectural conventions.
When initializing HAWS on a new machine, copy this file to `secondbrain/USER_PREFERENCES.md` and customize.

---

## 1. Interaction & Communication Style
- **Language Preference**: Respond in concise, direct Thai in chat conversations. All files, codebase files, documentation, commit messages, and technical artifacts must be written strictly in 100% professional English with zero Thai text.
- **Chat-First & Conciseness**: The user interacts primarily through conversational chat and Slash Commands. Be concise, direct, and eliminate polite conversational filler.
- **Caveman Compression Levels (Default Response Style)**: Apply Caveman mode as default. For closed-ended queries, respond in Full/Ultra. For short status reports, use Lite.
- **Autonomous Behind-the-Scenes Execution**: Manage file maintenance, status tracking, and subagent coordination behind the scenes.

---

## 2. Engineering & Architectural Conventions
- **Clean Architecture**: Keep business logic separated from presentation and transport layers.
- **Responsive UI**: All UI work must follow fluid responsive design.
- **Pokayoke (Error Proofing)**: Always safeguard calculations against null, missing, or zero-divide errors with honest, visible fallback indicators (e.g., "N/A").

---

## 3. Tool & Command Conventions
- **Git Remote Control**: AI agents must NEVER run `git push` to GitHub or any remote repository autonomously without first explicitly asking for human confirmation and receiving direct user approval in chat.