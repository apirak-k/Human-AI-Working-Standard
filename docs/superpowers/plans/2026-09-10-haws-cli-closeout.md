# HAWS CLI Closeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the HAWS CLI redesign so a user can configure and use HAWS skills, including Codex, through a verified interactive CLI.

**Architecture:** Preserve the modular runtime boundary: `runtime/settings.sh` owns interactive local configuration; `runtime/operations.sh` owns guarded mutations; `runtime/health.sh` owns read-only health reporting; and `ai-configs/codex/` owns Codex-specific linking. Treat the current uncommitted Settings changes as intentional candidate work and verify them before changing behavior.

**Tech Stack:** Bash (Git Bash on Windows), Git, Node.js test runner for the Codex adapter, dependency-free Bash CLI integration tests.

**Spec:** `f72501d:docs/superpowers/specs/2026-09-09-haws-cli-design.md` (historic design revision; it was centralized out of this worktree in `9c51f07`).

## Global Constraints

- Do not reset, discard, or overwrite existing changes in `haws.sh`, `runtime/settings.sh`, or `tests/cli/settings_test.sh`.
- `status` and `doctor` remain read-only and must not make remote requests.
- A bare CLI launch and Settings cancellation must not sync, install, or mutate persistent state.
- `Save & Apply` is the only Settings action that persists the draft or invokes selected integrations.
- Preserve device-local files `/.haws/state/`, `skills/skills.disabled`, and `ai-configs/environments.disabled`.
- Do not push or merge without explicit user approval.

---

### Task 1: Establish a repeatable Git Bash verification baseline

**Files:**
- Modify: `tests/cli/.haws/` only as generated test state; do not add it to Git
- Test: `tests/cli/run.sh`, `ai-configs/codex/agents.test.mjs`, `ai-configs/codex/skills.test.mjs`

**Interfaces:**
- Consumes: `tests/cli/run.sh` aggregate exit code and Node's built-in test runner.
- Produces: a recorded pass/fail baseline that determines whether a code fix is necessary.

- [ ] **Step 1: Locate Git Bash without changing PATH**

Run:

```powershell
Get-Command bash -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Program Files\Git\bin\bash.exe','C:\Program Files (x86)\Git\bin\bash.exe' -ErrorAction SilentlyContinue
```

Expected: one executable path, normally `C:\Program Files\Git\bin\bash.exe`.

- [ ] **Step 2: Run the aggregate CLI suite**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/run.sh
```

Expected: exit code `0`; every `*_test.sh` prints only its defined `PASS` lines.

- [ ] **Step 3: Run Codex adapter tests**

Run:

```powershell
node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs
```

Expected: exit code `0`; no failed subtests.

- [ ] **Step 4: Record failures before changing code**

Use the exact failing test name and first assertion message as the input to the smallest responsible fix. If all commands exit `0`, make no behavior change in this task.

### Task 2: Verify and complete the Settings entrypoint and repository menu

**Files:**
- Modify: `haws.sh:3019-3024` only if the `setup` alias differs from the `settings` flow
- Modify: `runtime/settings.sh:80-119,180-191` only if menu behavior differs from acceptance tests
- Modify: `tests/cli/settings_test.sh:122-132` only to encode an agreed visible menu contract

**Interfaces:**
- Consumes: `settings_run MODE` from `runtime/settings.sh` and `HAWS_TEST_KEYS` from `tests/cli/test_helper.sh`.
- Produces: `./haws.sh`, `./haws.sh setup`, and `./haws.sh settings` all reach the safe Settings flow; repository controls expose Git Submodule, Add Repository, Remove Repository, and Back.

- [ ] **Step 1: Run the focused Settings test before editing**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: exit code `0`. If it fails, capture the failing test name.

- [ ] **Step 2: Make the smallest correction only when a focused assertion fails**

Keep the public dispatch shape:

```bash
setup|bootstrap)
  shift || true
  settings_run "${1:-settings}"
  ;;
settings|configure)
  shift || true
  settings_run "${1:-settings}"
  ;;
```

Keep repository menu choices as Git Submodule, Add Repository, Remove Repository, and Back; do not edit `.gitmodules` merely by opening the menu.

- [ ] **Step 3: Re-run the focused Settings test**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: exit code `0` with repository-menu and environment-preservation tests passing.

### Task 3: Align public documentation with the delivered CLI

**Files:**
- Modify: `README.md:15-170`

**Interfaces:**
- Consumes: public commands in `haws.sh:3003-3056` and Codex adapter commands exposed by `ai-configs/codex/agents.mjs` and `ai-configs/codex/skills.mjs`.
- Produces: accurate Windows and cross-platform onboarding that names interactive `haws.sh`, safe Settings behavior, and Codex integration without referring to retired launchers.

- [ ] **Step 1: Update the README to the actual command surface**

Document this minimal first-use path:

```bash
./haws.sh
# or, from Git Bash on Windows:
bash haws.sh settings
```

Describe Sync as the explicit remote operation, Status and Doctor as read-only, and Save & Apply as the only setting-persistence action. Keep Codex guidance limited to skill discovery, HAWS pointer installation, and optional role-profile installation.

- [ ] **Step 2: Review every documented command against the dispatch table**

Compare each public command in `README.md` with `haws.sh:3003-3056`; remove retired launcher instructions and commands that are not part of the public CLI surface. Human-facing prose is reviewed against the running command surface rather than tested by source-text assertions.

Expected: all onboarding commands resolve to supported `haws.sh` commands and no active instructions mention retired batch launchers.

### Task 4: Run complete closeout verification and report evidence

**Files:**
- Modify: none unless an observed failing test requires a minimal fix
- Test: `tests/cli/run.sh`, `ai-configs/codex/agents.test.mjs`, `ai-configs/codex/skills.test.mjs`, `git diff --check`

**Interfaces:**
- Consumes: all runtime modules and public adapters.
- Produces: evidence that the branch is ready for user acceptance; no merge or push is performed.

- [ ] **Step 1: Run whitespace validation**

Run:

```powershell
git diff --check
```

Expected: exit code `0` and no output.

- [ ] **Step 2: Run all Bash CLI tests**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/run.sh
```

Expected: exit code `0`.

- [ ] **Step 3: Run all Codex adapter tests**

Run:

```powershell
node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs
```

Expected: exit code `0`.

- [ ] **Step 4: Inspect final change set**

Run:

```powershell
git status --short
git diff --stat
git diff --check
```

Expected: only intentional source, test, README, and plan changes; generated `tests/cli/.haws/` remains untracked and excluded from staging.

- [ ] **Step 5: Ask for merge and push authorization separately**

Report exact commands, exit codes, changed files, and any `[Unverified]` platform path. Do not merge into `main` or push unless the user explicitly authorizes each action.

## Plan Self-Review

- **Spec coverage:** Tasks 1–2 cover safe first use and Settings; Task 3 covers onboarding and Codex integration explanation; Task 4 covers Sync, Status, Doctor, and Uninstall through the aggregate suite and adapter tests.
- **Placeholder scan:** No unresolved markers remain; each task includes commands and expected outcomes.
- **Interface consistency:** Public dispatch remains `settings_run`, integration tests use `HAWS_TEST_KEYS`, and Codex verification uses the two existing Node test files.
