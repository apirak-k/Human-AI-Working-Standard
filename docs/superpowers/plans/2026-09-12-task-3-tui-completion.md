# Task 3 TUI Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete and obtain user acceptance for Task 3 by proving the HAWS interactive TUI matches the locked product contract without changing Task 1, Task 2, or later-task scope.

**Architecture:** `runtime/ui.sh` owns terminal interaction and redraw primitives. `runtime/settings.sh` owns navigation between approved draft-only Settings surfaces. Fixture tests prove deterministic behavior through `HAWS_TEST_KEYS`; real Git Bash validation proves terminal-only properties such as no accumulated frames and acceptable flicker. `spec.md` remains the behavior contract and `PROJECT_STATE.md` remains live status authority.

**Tech Stack:** Bash, Git Bash on Windows, dependency-free Bash fixture tests, Node.js only for existing adapter tests.

**Spec:** `spec.md` sections 3–19 and Task 3 in section 23; live scope in `PROJECT_STATE.md`.

## Global Constraints

- Execute Task 3 only. Do not start Task 4, 5, 6, or 7 work.
- Preserve existing user changes in `runtime/ui.sh` and `runtime/settings.sh`; do not reset, discard, or overwrite them.
- Use `40f5f5a:haws.sh` as the historical TUI mechanism reference. Reuse mechanics only, never its automatic setup/sync/Doctor product flow.
- Settings changes remain draft-only until reviewed Install or Update.
- Bare launch never auto-syncs or auto-runs Doctor.
- Do not mutate a real installation, contact remotes, merge, commit, or push without explicit user authorization.
- Run each fixture test through Git Bash. Treat test fixture state as generated, never stage it.
- Every production behavior change needs a focused failing test first. A real-terminal-only property also needs the manual protocol in Task 5.

## File Map

| File | Responsibility in this plan |
| --- | --- |
| `runtime/ui.sh` | Cursor menu, checklist, key handling, terminal redraw/clear behavior. |
| `runtime/settings.sh` | Setup, Settings, repository, skills, AI, preview, and Home navigation. |
| `tests/cli/settings_test.sh` | Deterministic cursor/checklist, Settings, repository, and draft-state regressions. |
| `tests/cli/first_install_test.sh` | First-launch Setup labels and non-mutating flow regressions. |
| `tests/cli/test_helper.sh` | Fixture entrypoint and command-log assertions; modify only if a new assertion cannot live in existing helpers. |
| `PROJECT_STATE.md` | Link this plan and record evidence after user acceptance; do not mark Task 3 accepted before user review. |

---

### Task 1: Freeze Task 3 evidence and classify current differences

**Files:**
- Modify: none unless a test helper is demonstrably missing.
- Inspect: `runtime/ui.sh`, `runtime/settings.sh`, `tests/cli/settings_test.sh`, `tests/cli/first_install_test.sh`, `40f5f5a:haws.sh`.
- Test: `tests/cli/settings_test.sh`, `tests/cli/first_install_test.sh`.

**Interfaces:**
- Consumes: current uncommitted redraw candidate and existing fixture test scripts.
- Produces: a short evidence log containing command, exit code, failing test name, and classification: contract divergence, redraw-only manual check, or unrelated.

- [ ] **Step 1: Inspect the exact historical interaction mechanism.**

Run:

```powershell
git show 40f5f5a:haws.sh > $env:TEMP\haws-40f5f5a.sh
rg -n "interactive_checklist|read -rsn1|cursor|printf.*\\033" $env:TEMP\haws-40f5f5a.sh runtime\ui.sh
```

Expected: identify exact historical cursor redraw/key-read behavior and current equivalent functions. Do not copy the old file.

- [ ] **Step 2: Run current focused suites before changing source.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/first_install_test.sh
```

Expected: record complete output and exit code. Do not call a passing suite proof of Task 3 completion.

- [ ] **Step 3: Compare each observed screen string with locked vocabulary.**

Check these contract strings:

```text
HAWS Setup
Use Default Setup
Customize Settings
HAWS Settings
Apply
Reset to Defaults
Discard Changes
Preview Install / Install
Preview Update / Update
```

Expected: list every mismatch. `Recommended`, `Save`, `Apply Update`, and `Cancel Setup` are not accepted main-flow vocabulary under `spec.md`.

- [ ] **Step 4: Record the scope boundary.**

Update only the plan execution notes, not `PROJECT_STATE.md` status, with:

```text
Task 3 evidence baseline recorded. No acceptance decision made.
```

- [ ] **Step 5: Stop for review gate.**

Report baseline failures and proposed next minimal change. Do not bundle fixes from multiple categories.

### Task 2: Make cursor/checklist redraw behavior testable and preserve fixture output

**Files:**
- Modify: `tests/cli/settings_test.sh`, `runtime/ui.sh` only after a failing test.
- Test: `tests/cli/settings_test.sh`.

**Interfaces:**
- Consumes: `ui_cursor_menu`, `ui_checklist`, `ui_next_key`, `HAWS_TEST_KEYS`.
- Produces: deterministic proof that interactive navigation does not emit ANSI clear bytes in fixture/non-TTY mode and still returns stable selection IDs.

- [ ] **Step 1: Add a failing regression test for non-TTY fixture output.**

Add this test before `run_test` registrations in `tests/cli/settings_test.sh`:

```bash
test_fixture_navigation_emits_no_terminal_clear_sequence() {
  new_fixture
  export HAWS_TEST_KEYS=2,back,cancel
  run_haws settings || true
  ! LC_ALL=C grep -a $'\033[H\033[2J' "${OUTPUT_FILE}" >/dev/null 2>&1
}
```

Register it:

```bash
run_test test_fixture_navigation_emits_no_terminal_clear_sequence
```

- [ ] **Step 2: Run only the new test and verify expected failure or valid existing coverage.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: if it fails, output contains terminal clear bytes. If it already passes, record that `ui_clear` correctly protects fixture mode and continue without changing production code.

- [ ] **Step 3: Add failing navigation contract tests one behavior at a time.**

Add and register these tests, preserving current fixture style:

```bash
test_nested_skills_back_returns_to_skills_menu() {
  new_fixture
  export HAWS_TEST_KEYS=3,single,Q,Q,cancel
  run_haws settings || true
  assert_output_contains "HAWS Settings — Skills" || return 1
  assert_output_contains "HAWS Settings" || return 1
}

test_uppercase_q_discards_dirty_draft_only_after_confirmation() {
  new_fixture
  export HAWS_TEST_KEYS=auto_update=off,Q,discard
  run_haws settings || true
  assert_output_contains "Discard Changes?" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ]
}
```

- [ ] **Step 4: Implement smallest TUI-only correction.**

Allowed production edits:

```bash
# runtime/ui.sh
# Keep ui_clear a no-op when HAWS_TEST_KEYS is set or stdout/stderr is not a TTY.
[ -n "${HAWS_TEST_KEYS:-}" ] && return 0
[ -t 0 ] || return 0
```

Use `ui_clear` only at a transition where old frame must disappear. Do not add `clear`, `tput`, sleep loops, or a second TUI engine.

- [ ] **Step 5: Re-run focused tests.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: all registered settings tests pass. Record exact count.

- [ ] **Step 6: Stop for review gate.**

Report changed lines, tests, and any TTY property that fixtures cannot prove.

### Task 3: Align Setup and Settings labels with locked lifecycle vocabulary

**Files:**
- Modify: `tests/cli/first_install_test.sh`, `tests/cli/settings_test.sh`, `runtime/settings.sh` only after failing tests.
- Test: `tests/cli/first_install_test.sh`, `tests/cli/settings_test.sh`.

**Interfaces:**
- Consumes: `_settings_menu_records`, `_settings_reset_to_defaults`, `settings_edit`, `ui_review`.
- Produces: approved Setup/Settings/Preview vocabulary without changing draft persistence, preview, or Install/Update semantics.

- [ ] **Step 1: Replace obsolete label assertions with failing locked-contract assertions.**

Replace only relevant assertions. Required first-install examples:

```bash
assert_output_contains "HAWS Setup" || return 1
assert_output_contains "Use Default Setup" || return 1
assert_output_contains "Customize Settings" || return 1
! grep -F "Use Recommended Defaults" "${OUTPUT_FILE}" >/dev/null 2>&1
```

Required Settings examples:

```bash
assert_output_contains "Apply" || return 1
assert_output_contains "Reset to Defaults" || return 1
assert_output_contains "Discard Changes" || return 1
! grep -F "Restore Recommended Defaults" "${OUTPUT_FILE}" >/dev/null 2>&1
! grep -F "Apply Update" "${OUTPUT_FILE}" >/dev/null 2>&1
```

- [ ] **Step 2: Run the affected suites and verify they fail for obsolete vocabulary.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/first_install_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: failures name old labels, not fixture setup errors.

- [ ] **Step 3: Make minimal label-only implementation changes.**

In `runtime/settings.sh`, update displayed labels and reset confirmation text. In `runtime/ui.sh`, ensure review actions show `Install` for first install and `Update` for installed changed drafts. Keep command IDs and state behavior unchanged unless a test proves a required interface change.

- [ ] **Step 4: Add no-regression assertions for draft safety.**

Keep or add these assertions beside modified tests:

```bash
[ ! -d "${FIXTURE_REPO}/.haws/state" ]
[ ! -s "${CALL_LOG}" ]
```

They prove opening/cancelling Settings does not persist or contact Git.

- [ ] **Step 5: Re-run both suites.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/first_install_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: exit code `0`; record counts and every changed expectation.

- [ ] **Step 6: Stop for review gate.**

Report the vocabulary mapping and verify no Settings action persists before final Install/Update.

### Task 4: Verify repository and AI selection contracts without scope expansion

**Files:**
- Modify: `tests/cli/settings_test.sh`, `runtime/settings.sh` only after a failing test.
- Inspect: `runtime/catalog.sh`, `runtime/integrations.sh` if a test shows the defect crosses Settings boundary.
- Test: `tests/cli/settings_test.sh`.

**Interfaces:**
- Consumes: `repositories_menu`, `_settings_remove_repositories_menu`, `_settings_choose_list`, draft repository variables, detected adapter paths.
- Produces: valid GitHub-only repository drafts, readable multi-select removal, and detected-only active AI choices.

- [ ] **Step 1: Add failing URL boundary tests.**

Add cases for all allowed and rejected forms:

```bash
test_add_repository_rejects_github_url_without_owner_or_repo() {
  new_fixture
  export HAWS_TEST_KEYS=2,add,https://github.com/owner,back,cancel
  run_haws settings || true
  assert_output_contains "Invalid GitHub repository URL: https://github.com/owner" || return 1
  ! grep -F "Repository added to draft:" "${OUTPUT_FILE}" >/dev/null 2>&1
}

test_add_repository_rejects_duplicate_url_in_draft() {
  new_fixture
  export HAWS_TEST_KEYS=2,add,https://github.com/owner/repo.git,add,https://github.com/owner/repo.git,back,Q,discard
  run_haws settings || true
  assert_output_contains "Repository already exists in draft" || return 1
}
```

- [ ] **Step 2: Run settings tests and verify expected failures.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: failures identify missing URL validation or duplicate protection. Do not alter `.gitmodules` during these tests.

- [ ] **Step 3: Implement minimal repository validation in draft path only.**

Accept only `https://github.com/<owner>/<repo>` with optional `.git`. Reject missing owner/repo, wrong host, duplicate URL, and destination collision. Leave clone, submodule creation, removal/prune, and remote work for reviewed Install/Update only.

- [ ] **Step 4: Add failing detected-only AI test.**

Use existing fixture adapter directories:

```bash
test_not_detected_ai_cannot_enter_active_draft() {
  new_fixture
  mkdir -p "${FIXTURE_HOME}/.claude"
  export HAWS_TEST_KEYS=envs=gemini,cancel
  run_haws settings || true
  assert_output_contains "Gemini" || return 1
  assert_output_contains "Not detected" || return 1
  [ ! -d "${FIXTURE_REPO}/.haws/state" ]
}
```

If current fixture key format cannot express disabled selection, first add a deterministic `HAWS_TEST_KEYS` path that exercises the real checklist selection. Do not test a mock variable disconnected from `ui_checklist`.

- [ ] **Step 5: Implement only proven selection guard.**

Keep unavailable adapters visible as `Not detected`. Prevent them from entering `HAWS_SELECTED_ENVIRONMENTS` or integration plans. Do not install tools or alter adapter discovery architecture.

- [ ] **Step 6: Re-run settings suite.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
```

Expected: exit code `0`; URL, removal, and detection tests pass with no `.gitmodules` or persistent-state mutation during cancellation.

- [ ] **Step 7: Stop for review gate.**

Report any multi-provider skill identity limitation separately. Do not invent provider selection logic in Task 3.

### Task 5: Execute real-terminal acceptance and prepare Task 3 decision package

**Files:**
- Modify: `PROJECT_STATE.md` only after evidence exists.
- Test: `tests/cli/settings_test.sh`, `tests/cli/first_install_test.sh`, `tests/cli/state_test.sh`, `tests/cli/run.sh`, `git diff --check`.

**Interfaces:**
- Consumes: completed fixture evidence and Git Bash terminal.
- Produces: user-reviewable transcript/checklist; no merge, push, or Task 4 work.

- [ ] **Step 1: Run complete fixture verification.**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/settings_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/first_install_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/state_test.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/cli/run.sh
git diff --check
```

Expected: all commands exit `0`. Record each suite count and any test excluded from aggregate execution.

- [ ] **Step 2: Run manual Git Bash protocol in a fixture-only environment.**

Use fixture `HOME` and `HAWS_REPO_DIR`, never the real user home. Confirm each item:

```text
[ ] First launch shows HAWS Setup; no automatic sync or Doctor.
[ ] Use Default Setup and Customize Settings preserve draft-only behavior.
[ ] Arrow navigation, Enter, Space, q, and Q work.
[ ] Nested Skills/Repositories/AI pages return without stacked old frames.
[ ] Dirty Settings q/Q requests discard confirmation.
[ ] Repository removal supports multiple selection and only changes draft.
[ ] Invalid and duplicate GitHub URLs are rejected.
[ ] Not-detected AI remains visible but cannot become active.
[ ] Preview Back preserves draft; Cancel discards it.
[ ] Installed Home has explicit Sync, Settings, Doctor, Status Details, Exit.
[ ] No obvious flicker or duplicated frame accumulation appears.
```

- [ ] **Step 3: Capture concise transcript evidence.**

Record command, fixture paths, terminal type, and outcome for every manual checklist item. Do not claim direct macOS/Linux verification from Windows/Git Bash evidence.

- [ ] **Step 4: Update live state without claiming acceptance.**

In `PROJECT_STATE.md`, replace Task 3 acceptance text only with one of:

```text
Awaiting user UX review. Evidence: <commands and date>.
```

or, if a failure remains:

```text
Blocked by <exact failing behavior>. Task 4–7 remain out of scope.
```

- [ ] **Step 5: Present acceptance package and stop.**

Report changed files, test commands/results, manual findings, known limitations, and a direct request for user Task 3 UX acceptance. Do not commit, merge, push, or begin Task 4 without that decision.

## Plan Self-Review

- **Spec coverage:** Tasks 2–5 cover Task 3 requirements for cursor controls, same-surface TUI, no accumulating frames, draft safety, repository removal, skills/AI selection, Setup/Settings/Preview/Home integration, tests, and manual acceptance.
- **Scope coverage:** Task 1 freezes evidence. Tasks 2–4 use one defect category per task. Task 5 only verifies and hands off; it does not begin Task 4 validation or later launcher/parity/documentation work.
- **TDD coverage:** Every production behavior change starts with a focused fixture test and an observed failure. Terminal-only redraw quality remains explicitly manual because non-TTY fixtures cannot honestly prove it.
- **Placeholder scan:** No unresolved placeholders. Each task defines files, interfaces, test command, expected result, and stop gate.
- **Known limitation:** Multi-provider skill identity is reported if still unresolved; it is not redesigned in this plan.

## Execution Handoff

Run this plan with `gpt-5.6-luna` using `superpowers:executing-plans`. Execute one numbered task at a time. Stop after each task and report evidence. Do not use a passing test as user UX acceptance.
