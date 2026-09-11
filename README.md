# Human–AI Working Standard (HAWS) v2.0

A working standard, orchestration rules, and specialized subagents for humans and AI coding assistants. Designed to work across **Google Antigravity**, **Claude Code**, **Cursor**, **ChatGPT**, and other AI tools on Windows, macOS, and Linux.

---

## What is HAWS?

HAWS sets clear **principles, boundaries, and expected results** for human-AI pair programming. Instead of letting AI guess or hallucinate, HAWS enforces verifiable testing, token discipline, and automated diagnostic checks before declaring work done.

The actual goal and required outcome always take priority over following rigid procedures.

---

## Quick Install and Setup

HAWS provides a shared, interactive command core with platform-native launchers. A bare launch opens **HAWS Setup** on a first install and **HAWS Home** after installation. No network operation starts until you choose **Apply & Install** or explicit **Sync**.

```bash
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# On Windows (CMD, PowerShell, or double-click haws.bat in Explorer):
haws.bat settings

# On macOS & Linux:
./haws.sh settings
```

Review and adjust your settings in the interactive TUI. Choose **Preview Install** (or **Preview Update**) to inspect all pending file links and configurations before confirming. Use **Sync** later for explicit remote synchronization. **Status** and **Doctor** are strictly read-only.

### Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

### Cross-Platform Launchers

- **Windows 10 / 11**: Use `haws.bat`. It automatically locates Git Bash / MSYS2 in standard locations (`ProgramFiles`, `scoop`, `chocolatey`, or `PATH`) and invokes the shared HAWS core. You can run it directly from Command Prompt, PowerShell, or by double-clicking `haws.bat` in Windows Explorer. No manual Git Bash path setup is required.
- **macOS & Linux**: Use `./haws.sh` directly in your terminal (`bash` or `zsh`). Uses native Unix symlinks (`ln -sfn`) to link skills and configuration pointers with zero manual overhead.

---


## Codex skills and subagents

HAWS sync links skills into `~/.agents/skills` and adds a HAWS pointer to the
effective global Codex instruction file (`AGENTS.override.md` when nonempty,
otherwise an existing `AGENTS.md`). The five canonical roles in `agents/`
are exposed as native TOML profiles under `~/.codex/agents/` (or
`$CODEX_HOME/agents/`). Their instructions refer back to the canonical Markdown
roles and inherit the parent's model and reasoning settings.

For an existing HAWS setup with skills already linked, install just the missing
Codex profiles without running a framework or Second Brain network sync:

```bash
bash haws.sh codex-agents install --dry-run
bash haws.sh codex-agents install
bash haws.sh codex-agents check
```

Start a fresh Codex session after installation so its agent catalog can refresh.
Ask the main agent to delegate a bounded investigation to `researcher` and a
verification task to `tester`, having each read the applicable installed skill
and return evidence. On interfaces that expose generic subagent dispatch, the
main agent supplies the canonical role path in the assignment.

The profile command preserves conflicting files, including manually edited
generated profiles, and exits with a path-specific error before writing.
An ownership record (`~/.codex/haws-agents.json`) stores the last installed hashes
so unchanged generated profiles can upgrade when their canonical descriptions change.
`codex-agents uninstall --dry-run` previews removal; only exact generated files
or files matching their recorded installed hashes are removable. Skill counts alone do not establish successful skill execution.

Native format reference: [OpenAI custom subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).

Focused regression checks: `node --test ai-configs/codex/agents.test.mjs`.

During Codex reconciliation, HAWS also prepares Graphify's upstream
Codex-specific skill file and references in `~/.haws/codex-skills/graphify`.
This adapter is necessary because the upstream repository stores its generic
entrypoint as lowercase `skill.md`, while Codex discovers exact `SKILL.md` files.

## Cross-Device Sync (Work and Home)

HAWS physically decouples the **upstream framework (`core/`)** from your **personal Second Brain (`secondbrain/`)**:
- `secondbrain/` is **gitignored** from the upstream HAWS repository, guaranteeing that upstream framework pulls never overwrite, conflict with, or erase your personal notes.
- `secondbrain/` is managed as an independent local Git repository.

> [!IMPORTANT]
> **Privacy Invariant**: Your Second Brain repository on GitHub **MUST be created as PRIVATE**. Never connect `secondbrain/` to a public repository to ensure that your personal notes, communication preferences, and recorded anti-patterns remain strictly confidential.

### Connecting to Cloud (Two-Way Sync)
On any computer (work machine or home machine):
```bash
bash haws.sh brain connect <your-private-github-repo-url>
```
- **Empty Remote (Machine 1)**: Automatically pushes your local second brain to the cloud.
- **Populated Remote (Machine 2)**: Automatically pulls, merges, and syncs your brain history symmetrically.

## HAWS CLI Reference (`haws.bat` & `./haws.sh`)

HAWS guarantees 100% feature and behavioral parity across platforms through platform-appropriate launchers:

| Windows | macOS / Linux | Purpose |
| :--- | :--- | :--- |
| `haws.bat` | `./haws.sh` | Opens **HAWS Setup** on first install, otherwise **HAWS Home** |
| `haws.bat settings` | `./haws.sh settings` | Edit Settings draft (Space toggle, multi-select repo removal, dirty draft guard) |
| `haws.bat sync` | `./haws.sh sync` | Run explicit, guarded remote sync with lock protection |
| `haws.bat status [--details]` | `./haws.sh status [--details]` | Read local health and configuration overview (strictly read-only) |
| `haws.bat doctor` | `./haws.sh doctor` | Run read-only diagnostics without mutation or recursive loops |
| `haws.bat uninstall` | `./haws.sh uninstall` | Preview and remove only HAWS-owned files; user data preserved |

### Settings & Draft Model

- **Draft-First Safety**: Changes in Settings modify a local working draft. No persistent files are written until you select **Apply Selection** and confirm via **Preview Install** or **Preview Update**.
- **Accidental Exit Protection**: Pressing `q` or `Q` with unsaved modifications prompts `Discard Changes?` confirmation before exiting.
- **In-Place Space Toggle**: Press `Space` directly in the Settings menu to toggle booleans (`Second Brain`, `Auto Update`) without opening submenus.
- **Repositories & Multi-Select**: In **Settings → Repositories**, remove multiple configured repositories simultaneously with live skill counts. Removing an installed repository detaches the submodule and cleanly prunes HAWS-owned symlinks.
- **Skills Hierarchy**: Browse **Single Skills** individually or configure **Multi-Skill Packs** with accurate `x/n active` counts and tri-state `Select All` support (`[ ]`, `[x]`, `[-]`).

---

## Repository Structure

```text
├── core/                                # Universal Standard Specifications (Copy-pasteable for any AI)
│   ├── HAWS.md                          # Core principles, empirical grounding, Ponytail ladder & safeguards
│   ├── WORK_INSTRUCTIONS.md             # Context loading, context discipline, Git protocols & SWE rules
│   └── WORKFLOW.md                      # 6-phase engineering lifecycle & deterministic skill mapping
├── secondbrain/                         # Personal Second Brain (Decoupled local Git repository)
│   ├── USER_PREFERENCES.md              # Personal habits, communication style & architectural preferences
│   └── ANTI_PATTERNS.md                 # Learned safeguards, forbidden libraries & operational constraints
├── agents/                              # Unified Subagent Source (Harness-Enforced)
│   ├── organizer.md                     # Skill inventory health, workspace hygiene & learning ledger
│   ├── frontend-engineer.md             # UI components, client state, styling, responsive design & a11y
│   ├── backend-engineer.md              # REST/GraphQL APIs, domain logic, DB schemas, auth & security
│   ├── tester.md                        # Automated test suites, edge cases, regression & boundary testing
│   └── researcher.md                    # Codebase reconnaissance, doc lookup & dependency verification
├── templates/                           # Documentation & governance blueprints (pure Markdown)
├── ai-configs/                          # Multi-AI environment adapters (Gemini, Claude, Cursor, Copilot, Codex)
│   └── environments.disabled            # Disabled AI environments blacklist (filter gate)
├── containers/                          # Container & DevContainer blueprints (Dockerfile, compose, devcontainer)
├── skills/                              # Curated Skill Repository (3 Clean Categories)
│   ├── skills.disabled                  # Disabled skills blacklist (filter gate)
│   ├── custom/                          # In-house proprietary skills (highest linking priority)
│   │   └── keyboard-layout-fixer/       # Bidirectional Thai/EN & CapsLock inversion converter
│   ├── packs/                           # Multi-skill submodule packs (agent-skills, superpowers, ponytail, etc.)
│   └── standalone/                      # Single-purpose standalone skills (drawio, taste-skill, etc.)
├── haws.bat                             # Windows native thin launcher (auto-locates Git Bash runtime)
└── haws.sh                              # Shared HAWS Core CLI: Setup, Home, Settings, Sync, Doctor
```

---

## Core Engineering Safeguards

1. **Empirical Grounding (`core/HAWS.md:Sec 3.1`)**: Claims of code completion require actual execution proof (commands run, exit codes, and test assertions). Never claim a feature works without running it. Unverified items must be explicitly labeled `[Unverified]`.
2. **Minimalist Engineering (The Ponytail Lazy Dev Ladder)**: Stop at the first rung:
   1. *Does this need to exist?* -> 2. *Already in this codebase?* -> 3. *Stdlib does it?* -> 4. *Native platform feature?* -> 5. *Installed dependency?* -> 6. *Can it be one line?* -> 7. *Only then write code.*
3. **Bounded Self-Correction Loop**: Capped at a maximum of **3 autonomous repair iterations**; if still failing, halt immediately, report diagnostic logs, and request human guidance. Never silence linters (`@ts-ignore`) or skip tests to fake green builds.
4. **Package & Dependency Invariant**: Lockfiles (`package-lock.json`, `poetry.lock`, `Cargo.lock`) must always be committed. Dependency vulnerability audits (`npm audit`, `pip-audit`) must pass with zero High/Critical vulnerabilities.
5. **Git Remote Push Protection**: AI agents must **NEVER** run `git push` to GitHub or any remote repository autonomously without explicit user confirmation in chat.
6. **Hardware Git Hooks (`.githooks/`)**:
   - `pre-commit`: Scans staged diffs for `.env*` secrets, plaintext credentials, verifies LF normalization, and runs fast CLI regression tests.
   - `pre-push`: Hardware-level blocker preventing unauthorized remote pushes.

---

## Built-in Custom Skill: keyboard-layout-fixer

Located at `skills/custom/keyboard-layout-fixer/`:
- **Case 1 (Thai on English Layout)**: `fdfd` -> `ดกดก`, `grnhv` -> `เพื้อ`
- **Case 2 (English on Thai Layout)**: `ดกดก` -> `fdfd`
- **Case 3 (Inverted CapsLock English)**: `hELLO wORLD` -> `Hello World`
- **Case 4 (CapsLock Active on EN Layout typing Thai)**: `FDFD` -> `ดกดก`, `GRNHV` -> `เพื้อ` (without shifted vowel/tone mark distortion)
- **Safety Guard (Acronym Bypass)**: Common English acronyms (`API`, `SQL`, `HTML`, `README`, `JSON`, `URL`, etc.) are detected and preserved without conversion.
- Automated tests pass 100%: `node skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`

---

## Remote Notifications for Long-Running Tasks

During long-running autonomous workflows (`/goal`, deep refactoring, comprehensive test suites), developers can receive instant mobile notifications and decision checkpoints via phone:

| Service / Protocol | Setup Time | Push (iOS/Android) | Interactive (Two-Way) | Recommended Use Case |
| :--- | :---: | :--- | :--- | :--- |
| **Telegram Bot API** | 2 mins | Instant | Inline Buttons | Pair programming and decision checkpoints |
| **ntfy.sh** | 30s | Native App | Action Links | Lightweight alerts (zero-account / privacy-first) |
| **Discord Webhooks** | 1 min | Channel Push | One-Way Only | Shared team notification channels |

### Instant Notification Snippets

**Telegram Bot**:
```bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=*[HAWS TASK COMPLETE]* All 37 diagnostics passed (100% green)." \
  -d "parse_mode=Markdown"
```

**ntfy.sh (Zero-Account / One-Liner)**:
```bash
curl -H "Title: HAWS Task Complete" \
     -H "Priority: high" \
     -H "Tags: white_check_mark,rocket" \
     -d "Diagnostics passed 100%. Ready for your review." \
     https://ntfy.sh/<your-secret-topic>
```

---

## Priority Hierarchy

When instructions or information conflict, always resolve in this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS (`core/HAWS.md`)**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions (`core/WORK_INSTRUCTIONS.md`)**
6. **[Second Brain HANDOFF](secondbrain/PROJECT/HANDOFF.md)** as a description of current work state
