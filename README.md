# Human–AI Working Standard (HAWS) v2.0

A working standard, orchestration rules, and specialized subagents for humans and AI coding assistants. Designed to work across **Google Antigravity**, **Claude Code**, **Cursor**, **ChatGPT**, and other AI tools on Windows, macOS, and Linux.

---

## What is HAWS?

HAWS sets clear **principles, boundaries, and expected results** for human-AI pair programming. Instead of letting AI guess or hallucinate, HAWS enforces verifiable testing, token discipline, and automated diagnostic checks before declaring work done.

The actual goal and required outcome always take priority over following rigid procedures.

---

## Quick Install and Setup

### Windows launcher
Double-click **`haws.bat`** in the HAWS repository root. It locates Git Bash and opens the shared old-style HAWS menu.

- First launch opens **HAWS Setup**.
- After installation, launch opens **HAWS Home**.
- Use `Up`/`Down` to move, `Enter` to select, `Space` for checklist items, and `Q` to leave a menu.
- Setup, Sync, Doctor, and Uninstall run only after the matching menu action. Launch does not auto-sync or auto-run Doctor.
- Selectable rows include a short action description, and actions report when
  they start and complete.
- Skills and AI Environments show an explicit loading/result state. If the
  Skills draft has not been loaded, Settings shows `all active (default)`.

The main-menu Skills category and pack selectors use the same Up/Down/Enter
controls as the other interactive menus. Numeric shortcuts remain accepted for
compatibility.

`haws.bat` is the Windows launcher. macOS and Linux use `./haws.sh`; the shared shell engine keeps behavior and state semantics aligned without requiring one launcher file for every OS.

The physical Explorer launch and full Windows menu walkthrough remain
`[Unverified]` at this final automated checkpoint. Automated launcher coverage
and CLI results are recorded below.

### Old-base verification checkpoint

Executed on 2026-09-14 in the old-base worktree with Git Bash 5.3.15 and Node.js
v22.14.0:

```bash
bash -n haws.sh && bash tests/cli/run.sh && node --test \
  ai-configs/codex/agents.test.mjs tests/windows_launcher_execution.test.mjs \
  && git diff --check
```

- CLI aggregate: 101/101 passed; the command exited 0 (14 + 14 + 27 + 6 +
  10 + 12 + 8 + 10).
- Node aggregate: 26 passed and 1 skipped; the command exited 0. The skipped
  case requires Windows file-symlink privilege and remains `[Unverified]`.
- Status/Doctor now reports overall health, Skills `active / total`, Second
  Brain, Auto Update, and `Last sync: Never` when no sync state exists. Home
  `Status Details` invokes the detailed status mode.
- The current working-tree Windows test includes two pre-existing local tests;
  they were executed but were not included in the code checkpoint commit.
- The code checkpoint is `500b59e`; the branch is one commit ahead of its
  tracking remote because no push or merge was performed.
- Settings-flow coverage includes the actionable AI Environments selector and
  verifies that opening Skills without edits does not show a false discard
  prompt.
- `ai-configs/codex/skills.test.mjs` is not present, so no unmeasured adapter
  coverage is claimed.

These automated results do not constitute physical Windows verification or
human acceptance.

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

Setup edits a draft, shows a Preview, and writes state only after `Install` or `Update` confirmation. Later launches open Home, where `Sync`, `Settings`, `Doctor`, `Status Details`, and `Uninstall` are explicit actions.

### Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

### Cross-Platform Setup Details

- **Windows 10 / 11**: Double-click `haws.bat`. It delegates to Git Bash and preserves the shared menu behavior. No administrator privileges are required for the launcher; Windows link capabilities depend on the host and are reported as `[Unverified]` when unavailable. Antigravity uses declarative JSON mapping (`skills.json`); Claude Code, Cursor, Copilot, and Codex use their existing adapters.
- **macOS & Linux**: Run directly in your standard terminal (`zsh` or `bash`). Uses native Unix symlinks (`ln -sfn`) to link skills and configuration pointers with zero manual overhead.

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
| `bash haws.sh hook install` | Install hardware git hooks (`pre-commit` and `pre-push`) |
| `bash haws.sh hook status` | Inspect git hook activation status |

### Managing Skills (Add & Remove)

HAWS organizes skills into two main tiers:

1. **External Git Submodules (Multi-Skill Packs & Standalone Skills)**:
   - **Interactive CLI Wizard**: Run `bash haws.sh kit setup` (or choose `2) Setup` during initial `bash haws.sh setup`). The CLI lists all current packs with their Git URLs, allows entering numbers to cleanly remove (prune), and prompts for Git URLs to add new packs or standalone skills.
   - **Direct CLI Commands**:
     - Add repository: `bash haws.sh kit add <git-url> [name]`
     - Remove repository: `bash haws.sh kit prune <name>`
     - List active submodules: `bash haws.sh kit list`
     - Update from remotes: `bash haws.sh kit update [name]`

2. **In-House Custom Skills (`skills/custom/`)**:
   - **To Add**: Create a folder under `skills/custom/<skill-name>/` containing a valid `SKILL.md`. Then run `bash haws.sh sync`.
   - **To Remove**: Delete the folder under `skills/custom/<skill-name>/` and run `bash haws.sh sync --clean`.
   - Local custom skills have top linking priority and are never overwritten by upstream framework updates.

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
├── templates/                           # Documentation & governance blueprints
│   └── docs/                            # SOT blueprints (PROJECT, ARCHITECTURE, CONSTRAINTS, etc.)
├── ai-configs/                          # Multi-AI environment adapters (Gemini, Claude, Cursor, Copilot, Codex)
├── containers/                          # Container & DevContainer blueprints (Dockerfile, compose, devcontainer)
├── skills.disabled                      # Disabled skills configuration (root level)
├── skills/                              # Curated Skill Repository (3 Clean Categories)
│   ├── custom/                          # In-house proprietary skills (highest linking priority)
│   │   └── keyboard-layout-fixer/       # Bidirectional Thai/EN & CapsLock inversion converter
│   ├── packs/                           # Multi-skill submodule packs (agent-skills, superpowers, ponytail, etc.)
│   └── standalone/                      # Single-purpose standalone skills (drawio, taste-skill, etc.)
├── haws.sh                              # Shared CLI command engine
├── haws.bat                             # Windows launcher for the shared engine
├── 1-CLICK-SYNC.bat                     # Legacy convenience launcher
├── 2nd-BRAIN-TOGGLE.bat                 # Legacy convenience launcher
└── UNINSTALL.bat                        # Legacy convenience launcher
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
- Focused keyboard-layout-fixer test: `node skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`

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
  -d "text=HAWS automated verification completed; review the recorded evidence." \
  -d "parse_mode=Markdown"
```

**ntfy.sh (Zero-Account / One-Liner)**:
```bash
curl -H "Title: HAWS Task Complete" \
     -H "Priority: high" \
     -H "Tags: white_check_mark,rocket" \
     -d "Automated checks completed; review the current evidence checkpoint." \
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
