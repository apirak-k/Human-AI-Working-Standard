# Human–AI Working Standard (HAWS) v2.0

A working standard, orchestration rules, and specialized subagents for humans and AI coding assistants. Designed to work across **Google Antigravity**, **Claude Code**, **OpenAI Codex**, **ChatGPT**, and other AI tools on Windows, macOS, and Linux.

---

## What is HAWS?

HAWS sets clear **principles, boundaries, and expected results** for human-AI pair programming. Instead of letting AI guess or hallucinate, HAWS enforces verifiable testing, token discipline, and automated diagnostic checks before declaring work done.

The actual goal and required outcome always take priority over following rigid procedures.

---

## Quick Install and Setup

### Launching HAWS

- **Windows**: If you have not cloned HAWS yet, run `git clone --recursive https://github.com/apirak-k/Human-AI-Working-Standard.git` in PowerShell, then `cd Human-AI-Working-Standard`. Double-click **`haws.bat`** (or run `.\haws.bat` from terminal). It automatically locates Git Bash and opens the interactive HAWS interface.
- **macOS & Linux**: Run `./haws.sh` in your terminal with Bash 4.2 or newer. macOS includes Bash 3.2; install a newer Bash with `brew install bash`, then run `"$(brew --prefix)/bin/bash" ./haws.sh`.

#### Interactive Menu System (TUI)
- **First Launch**: Opens **HAWS Setup** to configure AI environments, skills, and settings.
- **Subsequent Launches**: Opens **HAWS Home** with direct actions:
  - **`Sync`**: Verifies and reconciles skill links; refreshes skill sources and a connected Second Brain when their Auto Update settings are enabled.
  - **`Doctor`**: Runs read-only diagnostics and reports the checks and findings.
  - **`Settings`**: Configures Repositories, Skills (Enable/Disable), AI Environments, Second Brain, and Auto Update in a non-destructive draft mode. `Apply` accepts the draft for Preview; `Install` or `Update` confirmation saves it.
  - **`Uninstall`**: Safely detaches HAWS links and profiles with preview and confirmation.

#### Controls
- `Up` / `Down` (or `k` / `j`): Navigate items.
- `Enter`: Select item, open sub-menu, or toggle settings.
- `Space` / `x`: Toggle checkboxes in checklists.
- `Q`: Return to previous screen or exit without changes.
- In an interactive terminal, long lists show the visible item range and keep the selected item on screen while you move.

---

### Command Line Setup (All Platforms)
Run the shared command engine from Git Bash, macOS, or Linux:


```bash
# 1. Clone HAWS with all skill packs
git clone --recursive https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard

# 2. Open the first-use Setup flow
bash haws.sh setup
```

Setup edits a draft, shows a Preview, and writes state only after `Install` or `Update` confirmation. Later launches open Home, where `Sync`, `Doctor`, `Settings`, and `Uninstall` are explicit actions.

On macOS, use Bash 4.2 or newer for this command. The system Bash is 3.2; after installing Homebrew Bash, run `"$(brew --prefix)/bin/bash" haws.sh setup`.

### Prerequisites

HAWS core requires Git and Bash. Node.js and Python are needed only for the integrations that use them; individual skills may have their own requirements.

| Tool | Minimum Version | When it is needed |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Required to clone and update HAWS and its skill repositories |
| **Bash** | 4.2+ / Git Bash | Required to run the command engine (`haws.sh`); Git for Windows provides Git Bash |
| **Node.js** | 20+ | For native Codex agent profiles and Antigravity `skills.json` integration |
| **Python** | 3.10+ | For merging Second Brain documents during cloud sync |

### Cross-Platform Setup Details

- **Windows 10 / 11**: Double-click `haws.bat`. It delegates to Git Bash and preserves the shared menu behavior. No administrator privileges are required for the launcher; Windows link capabilities depend on the host and are reported as `[Unverified]` when unavailable. Antigravity uses declarative JSON mapping (`skills.json`); Claude Code and Codex use their existing adapters.
- **macOS & Linux**: Run directly in your standard terminal (`zsh` or `bash`) using Bash 4.2 or newer. The bundled macOS Bash 3.2 is rejected with an install command. Uses native Unix symlinks (`ln -sfn`) to link skills and configuration pointers with zero manual overhead.

---


## The 3-Tier Architecture & Cross-Device Sync

HAWS physically enforces the **3-Tier Data Separation Model**:
1. **Global Core (`core/`, `skills/`, `ai-configs/`)**: Public upstream framework tracked by Git. Safely updated anytime via `Sync`.
2. **Device-Local State (`.haws/state/`, `${HAWS_STATE_DIR}/skill-sources/`, and `${HOME}/.haws/skills-ownership.tsv`)**: Machine-specific junction registrations, toggle settings, external skill runtime checkouts, and HAWS link-ownership records. Kept 100% out of Git.
3. **Second Brain Documents (`secondbrain/`)**: Neutral starter documents for preferences, safeguards, and workflow. Keep these tracked public defaults neutral; put personal material in `secondbrain/notes/` or outside the public HAWS checkout.

> [!IMPORTANT]
> **Second Brain privacy:** The HAWS root repository ignores `secondbrain/notes/`, so those files are not included in HAWS commits. Connecting or syncing Second Brain can still commit and push files from that folder to its configured remote. Before connecting, verify that the remote is the intended repository and is **Private**. HAWS cannot verify repository visibility. Keep passwords, tokens, and credentials out of Second Brain files, including private ones.

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

### Sync safety and ownership

`Sync` keeps shared repository state, device-local installation state, and
personal user data separate:

- **Root safety:** Ordinary tracked, staged, or untracked root changes block
  Sync so HAWS does not overwrite work in progress. Worktree-only changes
  inside an initialized Git submodule are treated as device-local drift;
  staged gitlink changes still block Sync.
- **External skill updates:** Indexed external skill sources are refreshed in
  the ignored device-local cache under `${HAWS_STATE_DIR}/skill-sources/`.
  The parent repository's gitlink is not changed by this refresh, and HAWS
  does not automatically stage, commit, or push the root repository.
- **Link ownership:** A stale link is re-bound only when its recorded link
  type and target verify. For a pre-v2 five-field skill record, Sync checks the
  exact link path, link type, and current target before repairing it, then
  writes a schema-v2 ownership record. If no ownership record verifies, HAWS
  re-binds the link only when the previous HAWS manifest lists that skill and
  it points to the same relative skill path in another registered worktree of
  this repository. Links that meet neither rule are preserved.
- **Local-ahead safety:** If the local HAWS checkout is already ahead of the
  fetched remote candidate, Sync reports it as up to date and preserves the
  local HEAD; it does not reset or move the checkout backwards.
- **Second Brain boundary:** Second Brain is local-only unless a remote is
  explicitly connected. When connected, stage, commit, fetch, and push
  failures are reported as failures rather than a false success.

When a checkout or HAWS version changes, run `bash haws.sh doctor` and then
`bash haws.sh sync`. Do not delete links manually to repair a stale skill
target; HAWS can re-bind a verified owned link, including one recorded by a
pre-v2 five-field ownership row, or a manifest-listed skill link from another
registered worktree. Links that do not meet either rule are preserved.

---

## HAWS CLI Reference (`haws.sh`)

| Command | Purpose |
| :--- | :--- |
| `bash haws.sh setup` | First-use Setup flow with draft, Preview, and final Install/Update confirmation |
| `bash haws.sh sync` or `bash haws.sh update` | Both run the same all-in-one flow: refresh remote sources and connected Second Brain when their respective Auto Update settings are enabled, then detect environments and verify/reconcile skill links. Step 4 still runs when Auto Update is off. |
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
| `bash haws.sh hook install` | Install the HAWS advisory Git `commit-msg` hook |
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

Skill enable/disable choices are device-local. The tracked `skills/skills.disabled`
file is only the repository baseline for a fresh checkout; the Settings menu
writes user changes to `.haws/state/skills.disabled` so changing Skills does not
dirty the HAWS root or block Sync. Older tracked menu state is migrated on the
first state initialization when it is safe to do so. `Reset Settings to Defaults`
restores the Skill draft from that tracked baseline and enables all detected AI
environments in the draft; `Apply` is still required to persist the reset.

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
├── secondbrain/                          # Neutral public defaults; personalized DEV versions stay in DEV
│   ├── USER_PREFERENCES.md
│   ├── ANTI_PATTERNS.md
│   └── WORKFLOW.md
├── skills/                              # Curated capability repository (3 clean categories)
│   ├── custom/                          # In-house proprietary skills (highest linking priority)
│   ├── packs/                           # Repositories that provide multiple related capabilities
│   ├── standalone/                      # Single-purpose external repositories
│   └── skills.disabled                  # Tracked default Skill blacklist (filter gate)
├── ai-configs/                          # Multi-AI environment adapters (Gemini, Claude, Codex)
└── templates/                           # Public project/document blueprints only
    ├── AGENTS.md
    ├── ARCHITECTURE.md
    ├── CONSTRAINTS.md
    ├── DESIGN.md
    ├── HANDOFF.md
    └── PROJECT.md
```


---

## Core Engineering Safeguards

1. **Empirical Grounding (`core/HAWS.md:Sec 3.1`)**: Claims of code completion require actual execution proof (commands run, exit codes, and test assertions). Never claim a feature works without running it. Unverified items must be explicitly labeled `[Unverified]`.
2. **Minimalist Engineering (YAGNI & Simplicity First)**: Question whether new code needs to exist at all. Prefer standard libraries, native platform features, and existing utilities over adding external dependencies or boilerplate.
3. **Bounded Self-Correction Loop**: Capped at a maximum of **3 autonomous repair iterations**; if still failing, halt immediately, report diagnostic logs, and request human guidance. Never silence linters (`@ts-ignore`) or skip tests to fake green builds.
4. **Package & Dependency Invariant**: Lockfiles (`package-lock.json`, `poetry.lock`, `Cargo.lock`) must always be committed. Dependency vulnerability audits (`npm audit`, `pip-audit`) must pass with zero High/Critical vulnerabilities.
5. **Git Remote Push Protection**: AI agents must **NEVER** run `git push` to GitHub or any remote repository autonomously without explicit user confirmation in chat.

---

---

## Priority Hierarchy

When instructions or information conflict, always resolve in this order:

1. **Safety, privacy, legal, authorization, security, and irreversible action constraints**
2. **The user's latest clear intent and instruction**
3. **HAWS (`core/HAWS.md`)**
4. **Confirmed Project Specific requirements**
5. **Applicable Work Instructions (`core/WORK_INSTRUCTIONS.md`)**
6. **Active task context or project handoff** (when continuing existing work)
