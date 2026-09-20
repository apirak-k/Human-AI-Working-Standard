# Human–AI Working Standard (HAWS) v2.0

A working standard, orchestration rules, and specialized subagents for humans and AI coding assistants. Designed to work across **Google Antigravity**, **Claude Code**, **Cursor**, **ChatGPT**, and other AI tools on Windows, macOS, and Linux.

---

## What is HAWS?

HAWS sets clear **principles, boundaries, and expected results** for human-AI pair programming. Instead of letting AI guess or hallucinate, HAWS enforces verifiable testing, token discipline, and automated diagnostic checks before declaring work done.

The actual goal and required outcome always take priority over following rigid procedures.

---

## Quick Install and Setup

### Launching HAWS

- **Windows**: Double-click **`haws.bat`** in the repository root (or run `.\haws.bat` from terminal). It automatically locates Git Bash and opens the interactive HAWS interface.
- **macOS & Linux**: Run `./haws.sh` in your terminal.

#### Interactive Menu System (TUI)
- **First Launch**: Opens **HAWS Setup** to configure AI environments, skills, and settings.
- **Subsequent Launches**: Opens **HAWS Home** with direct actions:
  - **`Sync`**: Synchronizes skills, updates AI profiles, and pulls remote updates.
  - **`Health`**: Runs instant diagnostic checks across AI environments and links.
  - **`Settings`**: Configures Repositories, Skills (Enable/Disable), AI Environments, Second Brain, and Auto Update in a non-destructive draft mode (press `Apply` to save).
  - **`Uninstall`**: Safely detaches HAWS links and profiles with preview and confirmation.

#### Controls
- `Up` / `Down` (or `k` / `j`): Navigate items.
- `Enter`: Select item, open sub-menu, or toggle settings.
- `Space` / `x`: Toggle checkboxes in checklists.
- `Q`: Return to previous screen or exit without changes.

---

### Command Line Setup (All Platforms)
Run the shared command engine from Git Bash, macOS, or Linux:


```bash
# 1. Clone HAWS
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# 2. Open the first-use Setup flow
bash haws.sh setup
```

Setup edits a draft, shows a Preview, and writes state only after `Install` or `Update` confirmation. Later launches open Home, where `Sync`, `Health`, `Settings`, and `Uninstall` are explicit actions.

### Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

### Cross-Platform Setup Details

- **Windows 10 / 11**: Double-click `haws.bat`. It delegates to Git Bash and preserves the shared menu behavior. No administrator privileges are required for the launcher; Windows link capabilities depend on the host and are reported as `[Unverified]` when unavailable. Antigravity uses declarative JSON mapping (`skills.json`); Claude Code, Cursor, and Codex use their existing adapters.
- **macOS & Linux**: Run directly in your standard terminal (`zsh` or `bash`). Uses native Unix symlinks (`ln -sfn`) to link skills and configuration pointers with zero manual overhead.

---


## The 3-Tier Architecture & Cross-Device Sync

HAWS physically enforces the **3-Tier Data Separation Model**:
1. **Global Core (`core/`, `skills/`, `ai-configs/`)**: Public upstream framework tracked by Git. Safely updated anytime via `Sync`.
2. **Device-Local State (`.haws/state/`)**: Machine-specific junction registrations and toggle settings. Kept 100% out of Git.
3. **Personal DEV Overlay (`secondbrain/`)**: Optional private developer memory (`USER_PREFERENCES.md`, `ANTI_PATTERNS.md`, and `WORKFLOW.md`). Public `main` does not contain a user's personal files; a fresh checkout receives neutral starters from `templates/secondbrain/` when needed.

- `secondbrain/` can also be managed as an independent private Git repository for seamless cross-machine synchronization.

> [!IMPORTANT]
> **Privacy Invariant**: Your Second Brain repository on GitHub **MUST be created as PRIVATE**. Never connect `secondbrain/` to a public repository to ensure that your personal notes, communication preferences, and recorded anti-patterns remain strictly confidential.

### Connecting to Cloud (Two-Way Sync)
On any computer (work machine or home machine):
```bash
bash haws.sh brain connect <your-private-github-repo-url>
```
- **Empty Remote (Machine 1)**: Automatically pushes your local second brain to the cloud.
- **Populated Remote (Machine 2)**: Automatically pulls, merges, and syncs your brain history symmetrically.

### Windows actions
Use `haws.bat`, then choose the matching Home action:

- `Sync` performs explicit synchronization.
- `Settings` edits a draft and requires Preview plus final confirmation.
- `Doctor` reports executed checks without repairing or syncing.
- `Uninstall` shows a preview and removes only matching HAWS-owned items after confirmation.

---

## HAWS CLI Reference (`haws.sh`)

| Command | Purpose |
| :--- | :--- |
| `bash haws.sh setup` | First-use Setup flow with draft, Preview, and final Install/Update confirmation |
| `bash haws.sh sync` | Two-way Second Brain sync, pulls upstream framework, updates submodules, and verifies links |
| `bash haws.sh status` | Read-only current health summary and measured last-sync result |
| `bash haws.sh doctor` | Read-only evidence-based diagnostic report (`--json` supported) |
| `bash haws.sh uninstall` | Safely detach HAWS pointers, skills, and hooks without deleting user data (`--dry-run` supported) |
| `bash haws.sh kit setup` | Interactive skill kit selector (Review/prune existing packs or add new Git links) |
| `bash haws.sh kit add <url> [name]` | Add external skill pack submodule with merge protection |
| `bash haws.sh kit prune <name>` | Cleanly remove submodule, clear git cache, and delete directory |
| `bash haws.sh kit update [name]` | Update active submodules from upstream remote links |
| `bash haws.sh kit list` | List installed skill submodules and statuses |
| `bash haws.sh brain status` | Check Second Brain cloud connection and commit count (alias: `user status`) |
| `bash haws.sh brain connect <url>` | Connect Second Brain to private GitHub repository (alias: `user connect`) |
| `bash haws.sh brain disconnect` | Switch Second Brain to local-only mode (alias: `user disconnect`) |
| `bash haws.sh hook install` | Install the HAWS Git `commit-msg` hook |
| `bash haws.sh hook status` | Inspect git hook activation status |

### Managing Skills (Add & Remove)

HAWS organizes skills into three explicit categories:

1. **Custom Skills (`skills/custom/`)**: HAWS-owned local skills with the highest linking priority. Add a folder containing a valid `SKILL.md`, then run `bash haws.sh sync`.
2. **Single Skills (`skills/standalone/`)**: One-purpose external skill repositories.
3. **Multi-Skill Packs (`skills/packs/`)**: External repositories that provide multiple related skills.

For Single Skills and Multi-Skill Packs:
   - **Interactive CLI Wizard**: Run `bash haws.sh kit setup` (or choose `2) Setup` during initial `bash haws.sh setup`). The CLI lists configured sources with their Git URLs and lets you add or prune them.
   - **Direct CLI Commands**:
     - Add repository: `bash haws.sh kit add <git-url> [name]`
     - Remove repository: `bash haws.sh kit prune <name>`
     - List active submodules: `bash haws.sh kit list`
     - Update from remotes: `bash haws.sh kit update [name]`

Custom skills can be removed by deleting the folder and running `bash haws.sh sync --clean`.

---

## Repository Structure

```text
├── haws.bat                             # Windows launcher & interactive menu (Single Entrypoint)
├── haws.sh                              # Universal CLI command engine (Linux / macOS / Git Bash)
├── README.md                            # Quickstart guide & operating instructions
├── core/                                # Universal Standard Specifications (Universal for any AI)
│   ├── HAWS.md                          # Core principles, empirical grounding, Ponytail ladder & safeguards
│   └── WORK_INSTRUCTIONS.md             # Context loading, context discipline, Git protocols & SWE rules
├── agents/                              # Unified Subagent Source (Harness-Enforced)
│   ├── organizer.md                     # Skill inventory health, workspace hygiene & adaptive workflow habits
│   ├── frontend-engineer.md             # UI components, client state, styling, responsive design & a11y
│   ├── backend-engineer.md              # REST/GraphQL APIs, domain logic, DB schemas, auth & security
│   ├── tester.md                        # Automated test suites, edge cases, regression & boundary testing
│   └── researcher.md                    # Codebase reconnaissance, doc lookup & dependency verification
├── skills/                              # Curated Skill Repository (3 Clean Categories)
│   ├── custom/                          # In-house proprietary skills (highest linking priority)
│   │   └── keyboard-layout-fixer/       # Bidirectional Thai/EN & CapsLock inversion converter
│   ├── packs/                           # Multi-skill submodule packs (agent-skills, superpowers, ponytail, etc.)
│   ├── standalone/                      # Single-purpose standalone skills (archify, drawio, taste-skill, etc.)
│   └── skills.disabled                  # Disabled skills blacklist (filter gate)
├── ai-configs/                          # Multi-AI environment adapters (Gemini, Claude, Cursor, Codex)
└── templates/                           # Public blueprints, including neutral Second Brain starters
    └── secondbrain/                      # Generic defaults; personal DEV data is not stored here
```


---

## Core Engineering Safeguards

1. **Empirical Grounding (`core/HAWS.md:Sec 3.1`)**: Claims of code completion require actual execution proof (commands run, exit codes, and test assertions). Never claim a feature works without running it. Unverified items must be explicitly labeled `[Unverified]`.
2. **Minimalist Engineering (YAGNI & Simplicity First)**: Question whether new code needs to exist at all. Prefer standard libraries, native platform features, and existing utilities over adding external dependencies or boilerplate.
3. **Bounded Self-Correction Loop**: Capped at a maximum of **3 autonomous repair iterations**; if still failing, halt immediately, report diagnostic logs, and request human guidance. Never silence linters (`@ts-ignore`) or skip tests to fake green builds.
4. **Package & Dependency Invariant**: Lockfiles (`package-lock.json`, `poetry.lock`, `Cargo.lock`) must always be committed. Dependency vulnerability audits (`npm audit`, `pip-audit`) must pass with zero High/Critical vulnerabilities.
5. **Git Remote Push Protection**: AI agents must **NEVER** run `git push` to GitHub or any remote repository autonomously without explicit user confirmation in chat.
6. **Hardware Git Hooks (`.githooks/`)**:
   - `commit-msg`: Enforces Conventional Commits syntax and the English/ASCII invariant.

---

## Built-in Custom Skill: keyboard-layout-fixer

Located at `skills/custom/keyboard-layout-fixer/`:
- **Case 1 (Thai on English Layout)**: `fdfd` -> `ดกดก`, `grnhv` -> `เพื้อ`
- **Case 2 (English on Thai Layout)**: `ดกดก` -> `fdfd`
- **Case 3 (Inverted CapsLock English)**: `hELLO wORLD` -> `Hello World`
- **Case 4 (CapsLock Active on EN Layout typing Thai)**: `FDFD` -> `ดกดก`, `GRNHV` -> `เพื้อ` (without shifted vowel/tone mark distortion)
- **Safety Guard (Acronym Bypass)**: Common English acronyms (`API`, `SQL`, `HTML`, `README`, `JSON`, `URL`, etc.) are detected and preserved without conversion.

---

## Priority Hierarchy

When instructions or information conflict, always resolve in this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS (`core/HAWS.md`)**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions (`core/WORK_INSTRUCTIONS.md`)**
6. **Active task context or project handoff** (when continuing existing work)
