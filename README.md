# Human–AI Working Standard (HAWS) v2.0

A working standard, orchestration rules, and specialized subagents for humans and AI coding assistants. Designed to work across **Google Antigravity**, **Claude Code**, **Cursor**, **ChatGPT**, and other AI tools on Windows, macOS, and Linux.

---

## What is HAWS?

HAWS sets clear **principles, boundaries, and expected results** for human-AI pair programming. Instead of letting AI guess or hallucinate, HAWS enforces verifiable testing, token discipline, and automated diagnostic checks before declaring work done.

The actual goal and required outcome always take priority over following rigid procedures.

---

## Quick Install and Setup

### 🪟 Windows 1-Click Launchers (Zero Terminal Needed)
If you are on Windows, you don't even need to open a terminal or type any commands:
* **`1-CLICK-SYNC.bat`** (or **`haws.bat`**) : **Double-click in Windows File Explorer** to pull latest HAWS updates, sync all 104 skills into Antigravity & Claude Code, auto-sync your Second Brain with GitHub, and run system diagnostics in 1 click!
* **`brain-online.bat`** : **Double-click in Windows File Explorer** to connect or toggle your Second Brain cloud sync between Local-Only and Cloud mode.

---

### Command Line Setup (All Platforms)
Install and sync HAWS across your detected AI environments (**Google Antigravity** and **Claude Code**) with a single command:

```bash
# 1. Clone HAWS
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# 2. Run setup (initializes Second Brain, submodules, links skills, installs git hooks, runs diagnostics)
bash haws.sh setup
```

The automated `setup` script executes 5 steps in under 60 seconds:
1. **Initializes Second Brain**: Creates an independent `secondbrain/` Git repository to keep personal notes separate from the public framework.
2. **Initializes Submodules**: Clones external skill packs (`superpowers`, `agent-skills`, `anthropics-skills`, `mattpocock-skills`) and tool submodules (`ponytail`).
3. **Links Skills**: Connects skills into Google Antigravity (`~/.gemini/config/skills.json`) and Claude Code (`~/.claude/skills/`).
4. **Installs Hardware Git Hooks**: Sets up `.githooks/pre-commit` and `.githooks/pre-push` to block unverified code, secret leaks, and accidental remote pushes.
5. **Runs Diagnostics**: Executes the 10-axis doctor suite (38 verification checks) to confirm everything is set up correctly.

### Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

### Cross-Platform Setup Details

- **Windows 10 / 11**: Double-click `1-CLICK-SYNC.bat` or run inside **Git Bash** (`C:\Program Files\Git\bin\bash.exe`). No administrator privileges required (HAWS uses declarative mapping for Antigravity and NTFS Junctions for Claude Code). Use `brain-online.bat` for 1-click cloud sync in File Explorer.
- **macOS & Linux**: Run directly in your standard terminal (`zsh` or `bash`). Uses native Unix symlinks to link skills into `~/.claude/skills/`.

---

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

### Windows 1-Click Launcher (`brain-online.bat`)
Double-click `brain-online.bat` in Windows File Explorer:
- If offline: prompts for your private GitHub URL and connects.
- If online: displays a safety guard prompt before returning to Local-Only mode.

---

## HAWS CLI Reference (`haws.sh`)

| Command | Purpose |
| :--- | :--- |
| `bash haws.sh setup` | First-time setup: initializes Second Brain, submodules, skill links, git hooks, and doctor check |
| `bash haws.sh sync` | Two-way Second Brain sync, pulls upstream framework, updates submodules, and verifies links |
| `bash haws.sh status` | Instant skill count, token budget, and sync health check (< 0.2s) |
| `bash haws.sh doctor` | Comprehensive 10-axis system diagnostic suite (37 verification checks) |
| `bash haws.sh kit add --skill <url>` | Add external skill pack submodule with merge protection |
| `bash haws.sh kit add --tool <url>` | Add external non-skill tool into `plugins/` |
| `bash haws.sh kit prune <name>` | Cleanly remove submodule, clear git cache, and delete directory |
| `bash haws.sh brain status` | Check Second Brain cloud connection and commit count (alias: `user status`) |
| `bash haws.sh brain connect <url>` | Connect Second Brain to private GitHub repository (alias: `user connect`) |
| `bash haws.sh brain disconnect` | Switch Second Brain to local-only mode (alias: `user disconnect`) |
| `bash haws.sh hook install` | Install hardware git hooks (`pre-commit` and `pre-push`) |
| `bash haws.sh hook status` | Inspect git hook activation status |

---

## Repository Structure

```text
├── core/                                # Universal Standard Specifications (Copy-pasteable for any AI)
│   ├── HAWS.md                          # Core principles, empirical grounding, Ponytail ladder & safeguards
│   ├── WORK_INSTRUCTIONS.md             # Context loading, context discipline, Git protocols & SWE rules
│   ├── WORKFLOW.md                      # 6-phase engineering lifecycle & deterministic skill mapping
│   ├── USER_PREFERENCES.md              # Pointer to secondbrain/USER_PREFERENCES.md
│   ├── ANTI_PATTERNS.md                 # Pointer to secondbrain/ANTI_PATTERNS.md
│   └── SKILL_TAXONOMY.md                # Dynamic skill catalog & router (@organizer)
├── secondbrain/                         # Personal Second Brain (Gitignored from upstream HAWS)
│   ├── USER_PREFERENCES.md              # Personal habits, communication style & architectural preferences
│   └── ANTI_PATTERNS.md                 # Learned safeguards, forbidden libraries & operational constraints
├── plugins/                             # External Non-Skill Tools & Starred Repos (Submodules)
├── agents/                              # Unified Subagent Source (Harness-Enforced)
│   ├── organizer.md                     # Skill inventory health, workspace hygiene & learning ledger
│   ├── frontend-engineer.md             # UI components, client state, styling, responsive design & a11y
│   ├── backend-engineer.md              # REST/GraphQL APIs, domain logic, DB schemas, auth & security
│   ├── tester.md                        # Automated test suites, edge cases, regression & boundary testing
│   └── researcher.md                    # Codebase reconnaissance, doc lookup & dependency verification
├── templates/                           # 14 Project blueprints and templates (see templates/README.md for usage guide)
│   ├── SOT.md                           # Single Source of Truth architecture & schema blueprint
│   ├── AGENTS.md                        # Agent matrix and authorization governance
│   ├── CONSTRAINTS.md                   # Non-negotiable quality gates, linters, coverage, and dependency contracts
│   ├── ARCHITECTURE.md                  # System architecture, Mermaid topology & Archify JSON IR
│   ├── PROJECT.md                       # Project scope and delivery roadmap
│   ├── DESIGN.md                        # Design tokens & anti-slop guidelines
│   ├── HANDOFF.md                       # Session checkpoint & resume point
│   ├── USER_PREFERENCES.example.md      # Scaffolding template for new environments
│   ├── ANTI_PATTERNS.example.md         # Scaffolding template for new environments
│   ├── Dockerfile.template              # Multi-stage production build with non-root user
│   ├── .dockerignore.template           # Strict leak-proof container ignore file
│   ├── docker-compose.yml.template      # Local microservices stack (PostgreSQL, Redis, App)
│   ├── vite.config.ts.template          # Vite dev server with linter checker integration
│   └── .devcontainer/devcontainer.json  # Dev Container for zero-setup cross-device parity
├── skills/                              # Curated Skill Repository (3 Clean Categories)
│   ├── custom/                          # In-house proprietary skills (highest linking priority)
│   │   └── keyboard-layout-fixer/       # Bidirectional Thai/EN & CapsLock inversion converter
│   ├── packs/                           # Multi-skill submodule packs (agent-skills, superpowers, etc.)
│   └── standalone/                      # Single-purpose standalone skills (drawio, taste-skill, etc.)
├── haws.sh                              # Standalone Universal CLI Engine (10-axis diagnostics)
└── brain-online.bat                     # Windows 1-Click File Explorer Cloud Toggle
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
   - `pre-commit`: Scans staged diffs for `.env*` secrets, verifies LF normalization, and runs `haws.sh doctor`.
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
6. **[HANDOFF.md](HANDOFF.md)** as a description of current work state