# Human–AI Working Standard (HAWS) v2.0

A production-grade working standard, autonomous orchestration rules, and specialized subagents for collaboration between humans and AI agents — built for seamless cross-tool and cross-machine portability across **Google Antigravity**, **Claude Code**, **Cursor**, **ChatGPT**, and any AI coding assistant.

---

## What is HAWS?

HAWS defines the **principles, responsibilities, safeguards, and expected outcomes** that govern human-AI collaboration. It transitions AI coding from a chaotic, hallucination-prone guessing game into an **empirically grounded, token-disciplined, self-diagnosing, and harness-enforced multi-agent engineering workflow**.

The goal and required outcome are always prioritized over blindly following a rigid procedure.

---

## 🚀 Quick Install & Zero-Friction Setup

Install and sync HAWS globally across your detected AI environments (**Google Antigravity** and **Claude Code**) with a single command:

```bash
# 1. Clone HAWS
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# 2. Run All-in-One Setup (Bootstraps Second Brain, submodules, links skills, installs git hooks, runs diagnostics)
bash haws.sh setup
```

The automated `setup` bootstrapper executes 5 phases in under 60 seconds:
1. **Bootstraps Second Brain**: Initializes an independent `secondbrain/` Git repository with zero-leak protection.
2. **Initializes Submodules**: Fetches all external curated skill packs (`superpowers`, `agent-skills`, `anthropics-skills`, `mattpocock-skills`) and plugins (`ponytail`).
3. **Configures Skill Junctions**: Integrates skills into Google Antigravity (`~/.gemini/config/skills.json`) and Claude Code (`~/.claude/skills/`).
4. **Installs Hardware Git Hooks**: Sets up `.githooks/pre-commit` and `.githooks/pre-push` to block unverified code and unauthorized remote pushes.
5. **Runs Diagnostic Verification**: Executes the 10-axis doctor suite (37 verification checks) to confirm 100% green status.

### 📋 Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

### 💻 Cross-Platform Setup Details

- **Windows 10 / 11**: Run all commands inside **Git Bash** (`C:\Program Files\Git\bin\bash.exe`). No administrator privileges required (HAWS leverages declarative mapping for Antigravity and NTFS Junctions for Claude Code). Use `brain-online.bat` for 1-click cloud sync in File Explorer.
- **macOS & Linux**: Run directly in standard terminal (`zsh` or `bash`). Uses native Unix symlinks to link skills into `~/.claude/skills/`.

---

## 🧠 Symmetrical Cross-Device Sync (Work $\leftrightarrow$ Home)

HAWS physically decouples the **upstream framework (`core/`)** from your **personal Second Brain (`secondbrain/`)**:
- `secondbrain/` is **gitignored** from the upstream HAWS repository, guaranteeing that upstream framework pulls never overwrite, conflict, or wipe your personal data.
- `secondbrain/` is managed as an independent local Git repository.

### Connecting to Cloud (1-Click Symmetrical Sync)
On any computer (machine 1 or machine 2):
```bash
bash haws.sh user connect <your-private-github-repo-url>
```
- **Empty Remote (Machine 1)**: Automatically pushes your local second brain to the cloud.
- **Populated Remote (Machine 2)**: Automatically pulls, merges, and syncs your brain history symmetrically.

### Windows 1-Click Launcher (`brain-online.bat`)
Double-click `brain-online.bat` in Windows File Explorer:
- If offline: prompts for your private GitHub URL and connects.
- If online: displays a safety guard prompt before returning to Local-Only mode.

---

## 🧰 The HAWS CLI Engine (`haws.sh`)

| Command | Purpose |
| :--- | :--- |
| `bash haws.sh setup` | Frictionless first-time setup: secondbrain + submodules + sync + hooks + 10-axis doctor |
| `bash haws.sh sync` | Two-way Second Brain sync + upstream pull + submodules update + fast status |
| `bash haws.sh status` | Instant sub-second skill count and token budget telemetry (< 0.2s) |
| `bash haws.sh doctor` | Comprehensive 10-axis system diagnostic suite (37/37 checks) |
| `bash haws.sh kit add --skill <url>` | Add external skill pack submodule with merge protection |
| `bash haws.sh kit add --tool <url>` | Add external non-skill tool into `plugins/` |
| `bash haws.sh kit prune <name>` | Cleanly deinit, purge cache in `.git/modules/`, and delete folder (zero ghost files) |
| `bash haws.sh user status` | Inspect Second Brain cloud connection and commit count |
| `bash haws.sh user connect <url>` | Connect Second Brain to private GitHub repository |
| `bash haws.sh user disconnect` | Switch to Local-Only mode with safety confirmation |

---

## 📁 Repository Structure

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
├── templates/                           # Standalone Project Blueprints & SWE Quality Gates
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

## 🛡️ Core Engineering Safeguards

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

## ⌨️ Built-in Custom Skill: `keyboard-layout-fixer`

Located at `skills/custom/keyboard-layout-fixer/`:
- **Case 1 (Thai on English Layout)**: `fdfd` -> `ดกดก`, `grnhv` -> `เพื้อ`
- **Case 2 (English on Thai Layout)**: `ดกดก` -> `fdfd`
- **Case 3 (Inverted CapsLock English)**: `hELLO wORLD` -> `Hello World`
- **Case 4 (CapsLock Active on EN Layout typing Thai)**: `FDFD` -> `ดกดก`, `GRNHV` -> `เพื้อ` (without shifted vowel/tone mark distortion)
- **Safety Guard (Acronym Bypass)**: Common English acronyms (`API`, `SQL`, `HTML`, `README`, `JSON`, `URL`, etc.) are detected and preserved without conversion.
- Automated tests pass 100%: `node skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`

---

## 📱 Remote Notifications (AFK & Long-Running Tasks)

During long-running autonomous workflows (`/goal`, deep refactoring, comprehensive test suites), developers can receive instant mobile notifications and decision checkpoints via phone:

| Service / Protocol | Setup | Push (iOS/Android) | Interactive (Two-Way) | Recommended Use Case |
| :--- | :---: | :---: | :---: | :--- |
| **Telegram Bot API** | 2 mins | 🟢 Instant | 🟢 Inline Buttons | 🏆 **Top Pick (Pair Programming & Checkpoints)** |
| **ntfy.sh** | 30s | 🟢 Native App | 🟡 Action Links | 🥈 **Top Pick (Zero-Signup / Privacy-First)** |
| **Discord Webhooks** | 1 min | 🟡 Channel Push | 🔴 One-Way Only | 🥉 **Great for Shared Team Channels** |

### Instant Notification Snippets

**Telegram Bot**:
```bash
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=🚀 *[HAWS TASK COMPLETE]* All 37 diagnostics passed (100% green)." \
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
6. **Handoff (`HANDOFF.md`)** as a description of current work state