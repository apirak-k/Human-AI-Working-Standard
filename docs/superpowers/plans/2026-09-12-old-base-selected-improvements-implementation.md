# HAWS Old-Base Selected Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the next HAWS CLI from the `codex/haws-bootstrap` code and its established Windows terminal UX, then selectively adapt only verified improvements from the current recovery checkout.

**Architecture:** Preserve the old checkout and current recovery checkout as read-only references. Create a third worktree from old HEAD `71797228368959ab7a8d16b152da87e8452392b6`, keep `haws.bat` as a thin Windows entrypoint, and evolve the old monolithic `haws.sh` incrementally. Reuse or minimally refactor the old input/render engine; visible similarity from a replacement renderer is insufficient. Extract a new file only after tests show that the old shared boundary cannot carry the selected behavior clearly.

**Tech Stack:** Windows Batch, Bash 4+, Git for Windows/MSYS2, Node.js built-in test runner, shell fixture tests, Git worktrees.

**Spec:** `docs/superpowers/specs/2026-09-12-old-base-selected-improvements.md`

## Global Constraints

- Use `E:/Human-AI-Working-Standard/.worktrees/codex-haws-bootstrap` at branch `codex/haws-bootstrap`, HEAD `71797228368959ab7a8d16b152da87e8452392b6`, as the implementation base.
- Treat `E:/Human-AI-Working-Standard` at branch `recovery/clean-base`, inspected HEAD `b8752cf42c8833bb29a0d13758f2b04a2728abf0`, including its uncommitted files, as a reference only.
- Do not modify either reference checkout. Create a separate implementation worktree before changing production code.
- Preserve the old arrow/Space/Enter interaction, Single Skills/Multi-Skill Packs organization, readable progress, and Windows double-click experience.
- Treat the old checkout as the screen-by-screen UX contract. Existing labels, item order, destinations, key behavior, return behavior, and progress presentation remain unchanged unless the selection spec explicitly changes them.
- Implement only additive UX named by the selection spec. Insert each addition into the nearest existing old screen and reuse that screen's established interaction pattern; do not recreate unaffected old screens from the current implementation.
- Before implementing an added item, record its source screen, exact label, action, destination/result, and return behavior in the relevant test. If the old UX and selection spec do not determine one of these fields, stop that item as a pending UX decision instead of inventing it.
- Treat implementation method as a requirement for terminal UX: preserve the old raw-key reader, cursor hiding/restoration, relative row redraw, ANSI row clearing, and rendering path.
- Route every menu and checklist through one shared old-derived interaction engine. Do not add a parallel renderer, raw-key loop, or full-screen clear/redraw implementation.
- Apply Ponytail to every task. Reuse old code first, prefer deletion over duplication, use the fewest files, and require one focused runnable check for each non-trivial change.
- Use `gpt-5.6-luna` at `max` as implementation worker for Tasks 2A-8. Use `gpt-5.6-sol` at `high` for focused review or hard debugging. Reserve `gpt-6-astra` for final whole-branch review or unresolved architectural defects.
- Windows uses `haws.bat`; macOS/Linux use `./haws.sh`. A byte-identical cross-platform launcher is not required.
- A feature, test, `Done`, `Verified`, or `Accepted` label in existing files is evidence to inspect, not proof that runtime behavior passes.
- Never run setup, sync, install, update, repository removal, or uninstall against the user's real home/configuration during automated verification. Use disposable fixture homes and repositories.
- Preserve pre-existing uncommitted changes. Before and after every batch, compare `git status --short` in both reference checkouts and stop if either reference changed.
- Do not push. Commit only inside the separate implementation worktree after the batch tests and review gate pass; omit the commit step when the user has not authorized implementation commits.
- Do not delete or retire old/current reference code until all selected behavior is implemented, tested, and manually accepted.
- Mark physical Windows interaction, network timeout behavior, link-type behavior, and any unexecuted edge case `[Unverified]` until the named check is actually run.

## Inspected Baseline and Non-Claims

- Old `SETUP.bat` and `1-CLICK-SYNC.bat` contain the known Bash discovery and visible terminal wrapper patterns; the replacement must consolidate navigation without copying unconditional success claims.
- Old `haws.sh` contains `interactive_checklist`, direct raw-key handling, repository management, Single Skills/Multi-Skill Packs, Second Brain, status, Doctor, and uninstall code. Their presence is not a safety or completion claim.
- Current `haws.bat`, `runtime/*.sh`, `tests/cli/*.sh`, `tests/windows_launcher_execution.test.mjs`, and `spec.md` are selection sources. Current working-tree edits must be inspected as files, not copied wholesale or treated as accepted.
- Current screens and wording are not UX defaults. Use them only as evidence for additions explicitly selected in the spec; all unaffected UX comes from the old checkout.
- Static inspection identified known gaps in current update application, timeout enforcement, candidate fallback, repository-only Apply, partial Apply, unconditional health labels, and repository removal. The plan below tests the repaired outcome instead of preserving those claims.

## Target File Map

- `haws.bat` — thin Windows launcher: locate Bash, set the working directory, forward arguments, preserve the child exit code, and keep the terminal readable.
- `haws.sh` — old menu, state, catalog, lifecycle, operation, health, and ownership implementation. Extend existing functions in place and extract only when measured complexity requires it.
- `tests/cli/test_helper.sh` — isolated fixture home/repository setup, command capture, and assertions shared by shell tests.
- `tests/cli/launcher_menu_test.sh` — old-style entry/menu behavior and non-mutating launch tests.
- `tests/windows_launcher_execution.test.mjs` — real `cmd.exe /c haws.bat` execution and argument/exit-code tests on Windows.
- `tests/cli/state_test.sh` — local settings compatibility, exact-byte preservation, ownership record, and lock tests.
- `tests/cli/settings_flow_test.sh` — Setup/Home/draft/Preview/Back/Cancel/no-change/partial-failure lifecycle tests.
- `tests/cli/catalog_test.sh` — source-aware catalog, lazy loading, duplicate name, and destination collision tests.
- `tests/cli/repository_skill_test.sh` — repository draft/application and old Single/Pack interaction tests.
- `tests/cli/sync_test.sh` — dirty source, divergence, bounded fetch, candidate validation, and per-target result tests.
- `tests/cli/status_doctor_test.sh` — read-only diagnostics and evidence-based labels.
- `tests/cli/uninstall_test.sh` — ownership, modified-file, unrelated-file, and Windows link-type removal tests.
- `tests/cli/adapters_test.sh` — aggregate runner for existing per-adapter tests selected in Batch 7.
- `tests/cli/run.sh` — ordered aggregate runner; each new suite is added only with the batch that makes it pass.
- `spec.md`, `README.md`, and `HANDOFF.md` — update only after runtime behavior is proven; record executed evidence and remaining `[Unverified]` items without declaring human acceptance.

---

### Task 1: Establish the Isolated Old-Base Worktree

**Files:**
- Create: `.worktrees/codex-haws-old-base-selected/` through Git worktree machinery
- Verify only: `.worktrees/codex-haws-bootstrap/`
- Verify only: repository root recovery checkout

**Interfaces:**
- Consumes: old commit `71797228368959ab7a8d16b152da87e8452392b6`
- Produces: isolated branch `codex/old-base-selected-improvements` with no changes to either reference checkout

- [ ] **Step 1: Capture reference status without changing either checkout**

Run from `E:/Human-AI-Working-Standard`:

```powershell
git status --short --branch
git rev-parse HEAD
git -C .worktrees/codex-haws-bootstrap status --short --branch
git -C .worktrees/codex-haws-bootstrap rev-parse HEAD
```

Expected: recovery checkout still reports its pre-existing edits; old checkout reports `codex/haws-bootstrap` at `7179722...` with no worktree changes. Save the full output in the implementation session log, not in either reference checkout.

- [ ] **Step 2: Create the implementation worktree from the exact old commit**

Run using `superpowers:using-git-worktrees`:

```powershell
git worktree add .worktrees/codex-haws-old-base-selected -b codex/old-base-selected-improvements 71797228368959ab7a8d16b152da87e8452392b6
```

Expected: the new worktree is on `codex/old-base-selected-improvements`; both reference checkouts remain byte-for-byte untouched.

- [ ] **Step 3: Record the three-way identity check**

```powershell
git rev-parse HEAD
git -C .worktrees/codex-haws-bootstrap rev-parse HEAD
git -C .worktrees/codex-haws-old-base-selected rev-parse HEAD
git status --short
git -C .worktrees/codex-haws-bootstrap status --short
git -C .worktrees/codex-haws-old-base-selected status --short
```

Expected: current and old references match the Step 1 snapshot; the new worktree begins clean at the old commit.

### Task 2: Batch 1 — Open `haws.bat` and Use the Old Menu Before Adding Any System

**Files:**
- Create: `haws.bat`
- Modify: `haws.sh`
- Create: `tests/cli/test_helper.sh`
- Create: `tests/cli/launcher_menu_test.sh`
- Create: `tests/windows_launcher_execution.test.mjs`
- Create: `tests/cli/run.sh`

**Interfaces:**
- Consumes: old `interactive_checklist(title, "name|detail|state"...)`, `run_configure_skills()`, and public command functions already in old `haws.sh`
- Produces: `run_main_menu() -> exit status`, bare `haws.sh` interactive dispatch, and `haws.bat [args...]` forwarding

- [ ] **Step 1: Write failing static and fixture tests for the narrow Batch 1 contract**

Add tests that assert:

```bash
test -f "${PROJECT_ROOT}/haws.bat"
grep -F 'haws.sh' "${PROJECT_ROOT}/haws.bat" >/dev/null
! grep -iE 'run_sync|run_setup|run_doctor|git submodule' "${PROJECT_ROOT}/haws.bat" >/dev/null

HAWS_TEST_KEYS='q' HOME="${FIXTURE_HOME}" bash "${PROJECT_ROOT}/haws.sh" >"${OUTPUT_FILE}" 2>&1
assert_output_contains 'HAWS'
assert_output_contains 'Skills'
assert_output_contains 'Status'
assert_output_contains 'Doctor'
assert_output_contains 'Exit'
assert_file_not_exists "${FIXTURE_HOME}/.haws_manifest"
```

Also invoke the old Skills menu with fixture skills and assert `Single Skills`, `Multi-Skill Packs`, `Space`, and `Enter` remain visible. Do not assert ANSI byte-for-byte rendering.

- [ ] **Step 2: Run the Batch 1 tests and confirm the missing launcher/menu failure**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/launcher_menu_test.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: shell suite fails because the old base has no unified bare-entry menu; Windows suite fails because `haws.bat` does not exist.

- [ ] **Step 3: Implement only the thin Windows launcher**

Create `haws.bat` from the old Bash-discovery sequence, with these required semantics:

```bat
@echo off
setlocal
set "HAWS_DIR=%~dp0"
set "HAWS_SCRIPT=%HAWS_DIR%haws.sh"
rem Locate bash from PATH and the same established Git-for-Windows locations.
cd /d "%HAWS_DIR%"
if "%~1"=="" (
  "%BASH_CMD%" "%HAWS_SCRIPT%" menu
) else (
  "%BASH_CMD%" "%HAWS_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
```

Retain explicit missing-Bash/missing-script errors. Use `pause` only for a double-click error/success path where a terminal is attached; `HAWS_NO_PAUSE=1` must keep automation non-blocking. Do not put lifecycle, sync, setup, or Doctor decisions in Batch 1.

- [ ] **Step 4: Add the old-style main menu to `haws.sh`**

Implement `run_main_menu()` with the old visual framing and raw-key/menu conventions. The first menu contains only navigation to already-existing commands:

```text
HAWS — Main Menu
  Skills
  Repositories
  Second Brain
  Sync
  Status
  Doctor
  Uninstall
  Exit
Controls: Up/Down Move | Enter Select | Q Exit
```

`q/Q` and `Exit` return without setup, sync, hooks, Doctor, or filesystem changes. Selecting Skills reaches the existing Single Skills/Multi-Skill Packs UI; do not introduce Settings, Setup/Home lifecycle, draft state, or the current renderer in this batch.

### Task 2A: Correct Batch 1 to Reuse the Old Interaction Engine

**Files:**
- Modify: `haws.sh`
- Modify: `tests/cli/launcher_menu_test.sh`
- Modify: `tests/windows_launcher_execution.test.mjs`
- Modify: `IMPLEMENTATION_PROGRESS.md`

**Interfaces:**
- Consumes: old `interactive_checklist()` raw-key, cursor, relative redraw, and row-rendering mechanism
- Produces: one shared old-derived `interactive_menu()` core used by both simple menus and checklists

- [ ] **Step 1: Add failing method-fidelity tests**

Assert that `run_main_menu()` does not contain its own `read -rsn1`, `\033[H\033[2J`, or independent render loop. Exercise arrow movement in a PTY-capable Windows test and assert output uses cursor hide, relative row movement, per-row clear, and cursor restore sequences.

- [ ] **Step 2: Run focused tests and confirm the committed Batch 1 fails**

Run the launcher/menu shell suite and Windows launcher suite. Expected: failure because commit `941f8e8` contains a separate main-menu input/render loop and full-screen redraw.

- [ ] **Step 3: Refactor the old engine once**

Extract the smallest shared cursor/input/redraw core from `interactive_checklist()`. Keep its `read -rsn1`, `\033[?25l`, relative `\033[<rows>A`, `\033[2K\r`, and `\033[?25h` behavior. Add simple-menu selection as a mode of that same core. Remove the parallel `render_main_menu()` input/redraw implementation.

- [ ] **Step 4: Verify behavior and method**

Run Bash syntax, launcher/menu tests, Windows launcher tests, and the existing Codex-agent regression. Expected: all pass; cursor restoration is covered for Enter, Q, EOF, and child-action failure.

- [ ] **Step 5: Review and commit correction**

Use Ponytail review: confirm code deletion/centralization, no third renderer, no new dependency, and no full-screen redraw. Commit after independent review:

```powershell
git add haws.sh tests/cli/launcher_menu_test.sh tests/windows_launcher_execution.test.mjs IMPLEMENTATION_PROGRESS.md
git commit -m "fix: reuse old HAWS terminal interaction engine"
```

- [ ] **Step 5: Run the Batch 1 automated gate**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash -n haws.sh && bash tests/cli/launcher_menu_test.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: all assertions pass, bare non-TTY execution exits without mutation, arguments propagate, and the child exit code is preserved.

- [ ] **Step 6: Perform the mandatory physical Windows checkpoint**

Double-click `haws.bat` in Explorer and verify manually:

1. A visible terminal remains available long enough to read errors/results.
2. Up/Down moves exactly one row; Enter opens the selected page; `q/Q` returns/exits.
3. Skills opens the old Single Skills/Multi-Skill Packs screens.
4. Space toggles a fixture selection and Enter confirms it.
5. Exit does not begin setup, sync, Doctor, or modify the real HAWS/user configuration.

Expected: user explicitly accepts the old-style launcher/menu baseline. Stop here if physical interaction is not accepted; do not start Batch 2.

- [ ] **Step 7: Commit Batch 1 only after authorization and acceptance**

```powershell
git add haws.bat haws.sh tests/cli/test_helper.sh tests/cli/launcher_menu_test.sh tests/windows_launcher_execution.test.mjs tests/cli/run.sh
git commit -m "feat: restore old-style HAWS Windows menu"
```

### Task 3: Batch 2 — Add Compatible Local State Without Changing the Accepted Menu

**Files:**
- Modify: `haws.sh`
- Create: `tests/cli/state_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: `SCRIPT_DIR`, detected environments, old `skills.disabled`
- Produces within `haws.sh`: `settings_load()`, `settings_save()`, `disabled_environments_load()`, `disabled_environments_save_if_changed()`, `ownership_record()`, `ownership_list()`, `sync_lock_acquire()`, and `sync_lock_release()`

- [ ] **Step 1: Write failing state compatibility tests**

Cover exact behavior with disposable files:

```bash
: > "${FIXTURE_REPO}/ai-configs/environments.disabled"
disabled_environments_load
assert_equals '' "${DISABLED_ENVIRONMENTS[*]}"

printf 'cursor\r\ncodex\r\n' > "${FIXTURE_REPO}/ai-configs/environments.disabled"
before="$(_haws_sha256 "${FIXTURE_REPO}/ai-configs/environments.disabled")"
settings_save auto_update off
after="$(_haws_sha256 "${FIXTURE_REPO}/ai-configs/environments.disabled")"
assert_equals "${before}" "${after}"
```

Add round-trip tests for paths containing spaces, live-lock refusal, stale-lock reporting/recovery, and settings file replacement that leaves no truncated/half-written file after an injected pre-rename failure.

- [ ] **Step 2: Run tests and verify the APIs are absent**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/state_test.sh'
```

Expected: fail on missing state APIs in the old `haws.sh` path.

- [ ] **Step 3: Adapt the smallest state helpers**

Extend the old `haws.sh` state boundary. Implement complete-file replacement as `write temporary file -> flush/close -> mv over destination`; preserve an unchanged disabled-environment file byte-for-byte. Keep `skills.disabled` compatibility until an explicit migration test proves replacement safe. Do not create `runtime/state.sh` unless a reviewer documents that the old file has become unsafe to understand.

- [ ] **Step 4: Run Batch 1 and Batch 2 gates**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash -n haws.sh && bash tests/cli/launcher_menu_test.sh && bash tests/cli/state_test.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: state tests pass and the accepted old menu output/controls still pass.

- [ ] **Step 5: Commit the independently reviewed state boundary**

```powershell
git add haws.sh tests/cli/state_test.sh tests/cli/run.sh
git commit -m "feat: add compatible HAWS local state"
```

### Task 4: Batch 3 — Introduce Setup/Home and Draft-to-Preview Lifecycle

**Files:**
- Modify: `haws.sh`
- Create: `tests/cli/settings_flow_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: state APIs from Batch 2 and accepted old menu primitives from Batch 1
- Produces: `install_is_complete()`, `settings_draft_load()`, `settings_draft_discard()`, `settings_plan_build()`, `settings_preview()`, `settings_apply_final()`, `setup_run()`, and `home_run()`

- [ ] **Step 1: Write lifecycle tests before changing the menu**

Use `HAWS_TEST_KEYS` and fixture state to assert:

```text
no install marker -> Setup
Use Default Setup -> Preview Install
Customize Settings -> HAWS Settings
Settings Apply -> Preview Install or Preview Update
Preview Back to Settings -> same draft values
Preview Cancel -> discard draft and return to Setup/Home by lifecycle
unchanged Preview Update -> Back to Settings and Back to Home only
completed install -> Home
```

Snapshot fixture state hashes before draft editing; assert they stay unchanged until final `Install`/`Update`. Inject failure after settings persistence but before integration completion and assert the result says `Partial failure` with exact completed/remaining actions; do not claim atomicity.

- [ ] **Step 2: Run tests and confirm the lifecycle is absent**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/settings_flow_test.sh'
```

Expected: fail on missing Setup/Home/draft functions.

- [ ] **Step 3: Implement lifecycle screens using old menu rendering**

Add lifecycle selection at the bare entrypoint only after Batch 1 acceptance:

```bash
if install_is_complete; then
  home_run
else
  setup_run
fi
```

Keep approved vocabulary exactly: `Apply` accepts a draft for preview; final actions are `Install` and `Update`; `Back to Settings` preserves the draft; `Cancel` discards it. Do not show `Apply Update`. Home reads persistent state and renders once.

- [ ] **Step 4: Make final Apply dispatch every non-empty plan type**

Dispatch based on parsed action records, not a regex limited to initialize/pointer/skill-link. Explicitly include `add-source` and `remove-source`. Record per-action status so recovery after partial failure is honest and repeatable.

- [ ] **Step 5: Run lifecycle and regression gates**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash -n haws.sh && bash tests/cli/launcher_menu_test.sh && bash tests/cli/state_test.sh && bash tests/cli/settings_flow_test.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: all pass; fixture hashes prove draft-only editing and Home is not duplicated.

- [ ] **Step 6: Repeat the physical Windows lifecycle check**

Run first-install and installed fixture homes from `haws.bat`; verify visible Setup/Home, old keyboard feel, Back draft preservation, Cancel discard, no-change Preview, and readable partial-failure output. Keep real user paths out of the fixture environment.

- [ ] **Step 7: Commit Batch 3 after the test and human gates**

```powershell
git add haws.sh tests/cli/settings_flow_test.sh tests/cli/run.sh
git commit -m "feat: add old-style HAWS setup and preview flow"
```

### Task 5: Batch 4 — Add Repository Drafts and Source-Aware Skills to the Old Single/Pack UI

**Files:**
- Modify: `haws.sh`
- Create: `tests/cli/catalog_test.sh`
- Create: `tests/cli/repository_skill_test.sh`
- Modify: `tests/cli/settings_flow_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: draft/plan APIs, old `run_configure_skills()`, `.gitmodules`, and `skills/{custom,packs,standalone}`
- Produces: `catalog_sources()`, `catalog_skills()`, `catalog_validate_url()`, `catalog_validate_destination()`, and draft actions `add-source`/`remove-source`

- [ ] **Step 1: Write catalog and collision tests**

Fixtures must contain two sources with the same skill name and two URLs resolving to the same destination basename. Assert catalog rows retain source identity, skill lists load only when Skills/Preview needs them, duplicate URL is rejected, duplicate destination is rejected, and rejected input does not mutate the draft.

- [ ] **Step 2: Write real filesystem outcome tests for repository-only plans**

Create local bare Git remotes and disposable working repositories. Assert final Apply of an add-only plan creates the expected submodule/worktree entry, remove-only Apply actually removes only the HAWS-owned fixture source, dirty source removal is blocked, and Cancel/Back performs no repository mutation.

- [ ] **Step 3: Run both suites and observe the missing boundaries**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/catalog_test.sh && bash tests/cli/repository_skill_test.sh'
```

Expected: fail before implementation; no real network is required.

- [ ] **Step 4: Adapt catalog helpers, then connect them to the old UI**

Keep discovery pure/read-only. Preserve `Single Skills` and `Multi-Skill Packs`; annotate duplicate names with source labels instead of collapsing them. Apply skill selections to the Settings draft, and write persistence only on final Install/Update.

- [ ] **Step 5: Run Batch 1–4 aggregate gates**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/run.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: all suites pass with local-only fixtures, including repository-only Apply and dirty-repository refusal.

- [ ] **Step 6: Commit repository/catalog behavior**

```powershell
git add haws.sh tests/cli/catalog_test.sh tests/cli/repository_skill_test.sh tests/cli/settings_flow_test.sh tests/cli/run.sh
git commit -m "feat: add safe source-aware skill drafts"
```

### Task 6: Batch 5 — Repair Explicit Sync/Update With Bounded and Truthful Results

**Files:**
- Modify: `haws.sh`
- Create: `tests/cli/sync_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: `catalog_sources()`, sync lock, Auto Update setting, and explicit Home `Sync`
- Produces: `run_with_deadline(seconds, command...)`, `source_preflight()`, `source_candidate_validate()`, `sync_target()`, `sync_result_write()`, and `sync_run()`

- [ ] **Step 1: Write local remote-divergence and timeout tests**

Use local bare remotes to assert: a clean behind source advances to the selected remote revision; a dirty or untracked source is blocked while other targets continue; a missing candidate entrypoint fails validation instead of falling back to old content; a command exceeding the configured deadline returns `timeout`; lock release occurs on success, failure, and interrupt; Auto Update Off skips remote update work but explicit local synchronization remains clear.

- [ ] **Step 2: Run the suite and confirm current old behavior cannot satisfy it**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/sync_test.sh'
```

Expected: fail before the bounded operation APIs exist.

- [ ] **Step 3: Implement the minimum repaired operation layer**

Fetch into a candidate ref/worktree, validate required HAWS entrypoints from candidate content only, then advance the target explicitly. Compare final HEAD to the intended revision before writing `updated`; write `up-to-date` only when equality was measured. Use an actual deadline mechanism available in Git Bash/MSYS2 and return a distinct timeout status.

- [ ] **Step 4: Run sync, lifecycle, and launcher regression suites**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/sync_test.sh && bash tests/cli/settings_flow_test.sh && bash tests/cli/launcher_menu_test.sh'
```

Expected: all pass; result records identify every target as updated/up-to-date/skipped/blocked/failed/timeout based on executed evidence.

- [ ] **Step 5: Commit bounded sync behavior**

```powershell
git add haws.sh tests/cli/sync_test.sh tests/cli/run.sh
git commit -m "fix: make HAWS sync bounded and truthful"
```

### Task 7: Batch 6 — Separate Read-Only Health and Ownership-Aware Uninstall

**Files:**
- Modify: `haws.sh`
- Create: `tests/cli/status_doctor_test.sh`
- Create: `tests/cli/uninstall_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: catalog/state/ownership records and old status/Doctor/uninstall checks
- Produces: `status_run()`, `doctor_run()`, `uninstall_plan()`, `uninstall_preview()`, and `uninstall_apply()`

- [ ] **Step 1: Write read-only evidence tests**

Hash every fixture file before and after status/Doctor. Assert identical hashes and Git status, label each check from its executed result, and inject a failed check to prove output is not fixed `Ready`. Do not run Doctor on the real checkout during this test.

- [ ] **Step 2: Write ownership removal tests**

Record owned generated files and links, modify one after recording, and add unrelated files beside them. Assert dry-run is non-mutating, unchanged owned items are removable after final confirmation, modified items are preserved/reported, unrelated items remain, dirty owned repositories are blocked, and an interrupted apply leaves a recoverable per-item result.

- [ ] **Step 3: Add Windows link-type execution cases**

In `tests/windows_launcher_execution.test.mjs`, create only link types supported by the host (junction, symlink when permitted, generated file) in a temporary directory. Run uninstall planning/application and assert exact target preservation/removal. Report unsupported privilege-dependent types as `[Unverified]`, not pass.

- [ ] **Step 4: Implement separated health and ownership modules**

Keep status/Doctor free of repair, setup, fetch, sync, hooks installation, and writes. Make uninstall operate only on ownership records whose current fingerprint/type still matches; require preview and explicit final confirmation.

- [ ] **Step 5: Run the complete safety gate**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/run.sh'
node --test tests/windows_launcher_execution.test.mjs
```

Expected: all assertions pass; read-only hashes remain equal; Windows test output names any skipped link type explicitly.

- [ ] **Step 6: Commit health and uninstall safeguards**

```powershell
git add haws.sh tests/cli/status_doctor_test.sh tests/cli/uninstall_test.sh tests/cli/run.sh tests/windows_launcher_execution.test.mjs
git commit -m "feat: add evidence-based health and owned uninstall"
```

### Task 8: Batch 7 — Select Adapter Fixes Independently of the TUI

**Files:**
- Compare/modify selectively: `ai-configs/codex/agents.mjs`
- Compare/create selectively: `ai-configs/codex/skills.mjs`
- Compare/modify selectively: `ai-configs/codex/agents.test.mjs`
- Compare/create selectively: `ai-configs/codex/skills.test.mjs`
- Compare/modify selectively: `ai-configs/*/*.template`
- Create: `tests/cli/adapters_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: detected-environment selection and final Install/Update actions
- Produces: tested per-adapter install/check/uninstall contracts without changing the accepted old renderer

- [ ] **Step 1: Build an adapter-by-adapter diff inventory**

For each current adapter hunk, record: user-visible bug/requirement, old behavior, current code, existing test, destination file, and keep/rewrite/reject decision. Reject changes that only support the discarded renderer or overwrite project standards wholesale.

- [ ] **Step 2: Port failing tests before implementation**

Copy and adapt only tests whose expected outcome is still selected: pointer idempotence, project-standard preservation, selected-environment application, path-with-spaces support, and uninstall ownership. Run each Node test directly and record its expected failure against the old-based worktree.

- [ ] **Step 3: Implement one adapter at a time**

Make the minimum code/template change for one failing test, rerun that adapter's test, then run `tests/cli/adapters_test.sh`. Do not batch-copy `ai-configs/` from the recovery checkout.

- [ ] **Step 4: Run aggregate adapter and CLI gates**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/adapters_test.sh && bash tests/cli/run.sh'
node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs tests/windows_launcher_execution.test.mjs
```

Expected: all selected adapter tests and all earlier CLI gates pass.

- [ ] **Step 5: Commit selected adapters**

```powershell
git add ai-configs tests/cli/adapters_test.sh tests/cli/run.sh
git commit -m "fix: port selected HAWS adapter safeguards"
```

### Task 9: Batch 8 — Align Product Documentation and Complete Acceptance

**Files:**
- Modify: `spec.md`
- Modify: `README.md`
- Modify: `HANDOFF.md`
- Verify: `docs/superpowers/specs/2026-09-12-old-base-selected-improvements.md`
- Verify: `docs/superpowers/plans/2026-09-12-old-base-selected-improvements-implementation.md`

**Interfaces:**
- Consumes: executed Batch 1–7 results and human decisions
- Produces: current product specification, manual-use documentation, and an evidence-based resume checkpoint

- [ ] **Step 1: Run final automated verification from a clean implementation worktree**

```powershell
git status --short
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash -n haws.sh && bash tests/cli/run.sh'
node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs tests/windows_launcher_execution.test.mjs
```

Expected: clean pre-test status, zero exit codes, and test-created artifacts confined to disposable directories. Record exact commands, exit codes, pass/fail counts, skipped Windows capabilities, and environment details.

- [ ] **Step 2: Perform end-to-end Windows acceptance with disposable repositories**

From Explorer, launch `haws.bat` and exercise: first Setup, Customize Settings, repository add/remove draft, Single Skills, Multi-Skill Packs, AI environments, Second Brain Remote draft, Auto Update toggle, Apply, Preview, Back, Cancel, Install, Home, Sync, Status, Doctor, and uninstall dry-run/final confirmation. Verify actual fixture filesystem and Git outcomes after every final action.

Expected: the user records acceptance or precise rejected observations. Automated green output alone is not human acceptance.

- [ ] **Step 3: Update `spec.md` to the implemented old-base architecture**

Remove recovery-base/task-number/identical-launcher assumptions. Preserve only behavior proven or still required; mark platform behavior not executed `[Unverified]`. State explicitly that Windows uses `haws.bat` and macOS/Linux use `./haws.sh` with equivalent commands/semantics, not identical launcher source.

- [ ] **Step 4: Update `README.md` with the tested manual entry path**

Document `double-click haws.bat`, the old-style controls, first-install Setup versus later Home, explicit Sync, and failure recovery. Do not write `100% Green`, `Ready`, or `Up to date` unless the immediately preceding documented command measured that result.

- [ ] **Step 5: Update `HANDOFF.md` with evidence categories kept separate**

Record:

```text
Confirmed decisions
Implemented changes
Executed automated verification
Executed physical Windows verification
Human acceptance
Unverified areas
Preserved reference checkouts
Remaining risks and exact resume point
```

- [ ] **Step 6: Recheck both reference checkouts and review the final diff**

```powershell
git -C E:/Human-AI-Working-Standard status --short --branch
git -C E:/Human-AI-Working-Standard/.worktrees/codex-haws-bootstrap status --short --branch
git status --short
git diff --check
git diff --stat 71797228368959ab7a8d16b152da87e8452392b6..HEAD
```

Expected: both reference snapshots are unchanged; implementation diff contains only selected work; no whitespace errors.

- [ ] **Step 7: Commit documentation only after results and acceptance wording are accurate**

```powershell
git add spec.md README.md HANDOFF.md
git commit -m "docs: record old-base HAWS behavior and evidence"
```

Do not merge or push. Keep the old, current, and implementation checkouts until the user separately authorizes retirement or integration.

## Self-Review Results

- **Spec coverage:** Every selected improvement is assigned to a batch: launcher/old UX (Batch 1), local state/environments/toggles (Batch 2–3), Setup/Home/draft/Preview (Batch 3), repositories/catalog/skills (Batch 4), sync safeguards (Batch 5), diagnostics/uninstall ownership (Batch 6), adapters (Batch 7), and spec/docs/acceptance (Batch 8).
- **Known static gaps:** Remote advancement, actual deadline enforcement, candidate-only validation, repository-only Apply, partial failure, dirty repository removal, and truthful health labels each have a named failing test before implementation.
- **Ordering:** Task 2A removes the parallel renderer committed in `941f8e8`. No new state or lifecycle work begins until method-fidelity tests pass. Physical Windows acceptance remains the final user gate for unattended execution.
- **Ponytail:** New functionality first extends the old `haws.sh`; new runtime files require measured need and reviewer justification.
- **Reference preservation:** Both source checkouts remain read-only references throughout; all implementation changes occur in a third worktree.
- **Completeness scan:** Every implementation action names its intended behavior, target files, verification command, and expected result.
- **Acceptance discipline:** Code presence, existing tests, automated results, physical Windows verification, and human acceptance remain separate evidence categories.
