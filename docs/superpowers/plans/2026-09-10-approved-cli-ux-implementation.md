# Approved CLI UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved keyboard-first HAWS terminal UX without regressing Task 1–9 safety guarantees.

**Architecture:** Keep `runtime/state.sh`, `runtime/catalog.sh`, `runtime/integrations.sh`, and ownership-aware operations as the system of record. Introduce focused UI primitives for cursor menus, draft prompts, conditional reviews, and truthful progress; `runtime/settings.sh` orchestrates draft screens while `runtime/operations.sh` exposes per-target Sync results for Home to render.

**Tech Stack:** Bash; Git Bash-compatible terminal I/O; isolated fixture HOME/repository tests in `tests/cli/`.

**Spec:** `docs/superpowers/specs/2026-09-10-approved-cli-ux-design.md`

## Global Constraints

- Preserve draft-before-Apply and never mutate a real user installation in automated tests.
- Keep Status and Doctor local and read-only; only Sync may contact a remote.
- Do not restore `.bat` launchers, legacy cleanup, direct `.gitmodules` editing, or legacy manifest deletion.
- Use source and skill IDs from the current catalog; do not add a dependency.
- Preserve existing dirty worktree changes unless they are deliberately superseded by an approved UX task.

---

### Task 1: Freeze the approved terminal screens and navigation contract

**Files:**
- Modify: `runtime/ui.sh`
- Modify: `tests/cli/settings_test.sh`
- Modify: `tests/cli/first_install_test.sh`

**Interfaces:**
- Produces `ui_cursor_menu TITLE ITEM...` with `UI_MENU_RESULT` equal to the selected stable item ID.
- Produces `ui_checklist` rendering a visible `Select All` row and returning stable IDs in `UI_CHECKLIST_RESULT`.

- [ ] **Step 1: Add failing fixture assertions for the approved labels and help text.**

  Assert that first install contains `Repositories`, `sources`, `Second Brain Remote`, `Preview Install`, and `Restore Recommended Defaults`; assert that a checklist contains `Select All`, `Space Toggle`, and `Enter Select`.

- [ ] **Step 2: Run the focused tests to prove the current numeric/text UI fails the new assertions.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: failure on the new cursor-menu wording or labels, before implementation changes.

- [ ] **Step 3: Implement cursor-menu rendering and test-seam key handling in `runtime/ui.sh`.**

  Use records shaped `id<TAB>label<TAB>detail`. Render `>` at the cursor. Map arrow keys (and test aliases `up`, `down`, `enter`) to a selected ID. Keep `/dev/tty` as production input and `HAWS_TEST_KEYS` only as the fixture seam.

- [ ] **Step 4: Update `ui_checklist` wording and preserve its current no-write behavior.**

  Render `Select All` rather than a hidden bulk command, preserve `[ ]`, `[-]`, `[x]`, Space, Enter, and Q, and return no result on cancel.

- [ ] **Step 5: Run focused tests and commit the independent UI primitive change.**

  Run: `bash tests/cli/settings_test.sh`

  Expected: exit 0.

  Commit: `git add runtime/ui.sh tests/cli/settings_test.sh tests/cli/first_install_test.sh && git commit -m "feat(cli): add cursor menu primitives"`

### Task 2: Implement Settings, Repositories, Skills, AI, and toggles as draft-only cursor flows

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `runtime/state.sh`
- Modify: `tests/cli/settings_test.sh`
- Modify: `tests/cli/first_install_test.sh`

**Interfaces:**
- Consumes `ui_cursor_menu`, `ui_checklist`, `settings_load`, catalog rows, and existing draft variables.
- Produces `HAWS_DRAFT_ADDED_REPOSITORIES`, draft removals, `HAWS_DRAFT_SECOND_BRAIN`, `HAWS_DRAFT_SECOND_BRAIN_REMOTE`, and `HAWS_DRAFT_AUTO_UPDATE` without persistent writes.

- [ ] **Step 1: Write failing tests for the First Install and installed Settings rows.**

  Cover `Repositories N sources`, Skills active count, selected AI count, both toggles, Preview Install/Update, default reset, cancel, and installed-only Uninstall. Assert cancel leaves state and integration paths absent.

- [ ] **Step 2: Run the focused Settings tests and confirm they fail before behavior changes.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: failure because current Settings uses numbered text input and reports repositories as selected.

- [ ] **Step 3: Replace `_settings_render`/`settings_edit` dispatch with stable cursor-menu IDs.**

  Keep `settings_draft_defaults` as the only default reset API. The first-install title chooses Preview Install; installed mode chooses Preview Update. `Cancel Setup`/`Cancel Update` returns without state writes.

- [ ] **Step 4: Replace the repository submenu with draft Add/Remove/Back.**

  Add URL input validation that accepts only a nonempty URL-shaped draft value; record additions and removals separately. Remove uses `ui_checklist` over existing source IDs. Delete the current `Git Submodule` presentation branch and do not edit `.gitmodules` before confirmed Apply.

- [ ] **Step 5: Make Skills category-first and AI selection descriptive.**

  Retain the catalog as the only source of skill records. Render Single Skills and Multi-Skill Packs, then apply checklist output to the draft only. Render every supported AI adapter with `Detected` or `Not detected`, preserving the user’s ability to select either.

- [ ] **Step 6: Add a draft-only Second Brain Remote setup flow.**

  If toggled On and no remote is presently configured, collect a URL, run a bounded read-only connection test, show its result, and store the URL/test result in draft variables. Extend `settings_save` only to persist approved remote metadata after review; do not create or change the Git remote before Apply.

- [ ] **Step 7: Run focused tests and commit.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh && bash tests/cli/state_test.sh`

  Expected: exit 0 with fixture-only state writes after confirmed Apply.

  Commit: `git add runtime/settings.sh runtime/state.sh tests/cli/first_install_test.sh tests/cli/settings_test.sh && git commit -m "feat(cli): implement approved settings flow"`

### Task 3: Render complete Preview Install/Update and apply only reviewed changes

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `runtime/ui.sh`
- Modify: `tests/cli/first_install_test.sh`
- Modify: `tests/cli/settings_test.sh`

**Interfaces:**
- Consumes the complete draft and current persisted settings.
- Produces a structured review with `current -> draft` differences and an explicit Apply/Back/Cancel result.

- [ ] **Step 1: Add failing tests for Preview Install, Preview Update, and no-change Update.**

  Assert Install review contains summary, changes, not-changed safeguards, `Install HAWS`, Back, and Cancel. Assert installed review says `Preview Update`/`Apply Update` and a no-diff review has no Apply action.

- [ ] **Step 2: Run the review tests to establish the current raw plan output is insufficient.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: failure on missing human-readable comparison and action labels.

- [ ] **Step 3: Build a renderer from existing settings/integration plan records.**

  Group added/removed sources, skill changes, environment changes, Remote setting and connection status, and Auto Update setting. Include explicit `Not changed` safeguards. Do not make a remote request while rendering Preview.

- [ ] **Step 4: Implement Apply/Back/Cancel decisions around the existing apply path.**

  Apply persists only reviewed draft values, then calls existing integration/ownership operations. Back returns to Settings with draft intact. Cancel discards draft. For a newly approved remote, configure the remote only after the review confirmation and report success/failure.

- [ ] **Step 5: Render action-specific Apply progress and test it.**

  Print only actual actions with a final Done, Skipped, Blocked, or Failed state. Do not label an unchanged component as installed or updated.

- [ ] **Step 6: Run focused suites and commit.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: exit 0.

  Commit: `git add runtime/settings.sh runtime/ui.sh tests/cli/first_install_test.sh tests/cli/settings_test.sh && git commit -m "feat(cli): add reviewed install and update previews"`

### Task 4: Implement cursor Home and conditional Sync progress without weakening safeguards

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `runtime/operations.sh`
- Modify: `runtime/health.sh`
- Modify: `tests/cli/settings_test.sh`
- Modify: `tests/cli/sync_test.sh`
- Modify: `tests/cli/status_doctor_test.sh`

**Interfaces:**
- Consumes `sync_run`, `sync_result_write`, local settings, and recorded sync state.
- Produces Home cursor selection; conditional Sync progress; local-only status details; read-only Doctor.

- [ ] **Step 1: Add failing Home tests for cursor rows and read-only details/Doctor.**

  Assert Home presents Sync Now, Settings, Doctor, Status Details, Exit; assert Status Details and Doctor do not call fetch/pull; assert their labels identify the operation as read-only.

- [ ] **Step 2: Add failing Sync matrix tests.**

  Cover four combinations of Second Brain Remote and Auto Update. Assert manual Sync always attempts the HAWS update check, Auto Update Off skips source update checks, and Remote Off never contacts the Second Brain remote.

- [ ] **Step 3: Run targeted tests to record the intentional change from Task 1–9 Sync behavior.**

  Run: `bash tests/cli/sync_test.sh && bash tests/cli/status_doctor_test.sh && bash tests/cli/settings_test.sh`

  Expected: existing `both off makes no network request` test fails and is replaced by the approved manual-HAWS-check expectation.

- [ ] **Step 4: Replace text-command Home with `ui_cursor_menu`.**

  Render the approved summary from recorded local state. Map Sync Now to `sync_run`, Settings to `settings_run`, Doctor to `doctor_run`, Status Details to `status_run --details`, and Exit to return.

- [ ] **Step 5: Make `sync_run` expose truthful conditional progress.**

  Keep locking, per-source isolation, local-change blocks, candidate validation, and no automatic dependency install. Always run the HAWS target on manual Sync; run sources only when Auto Update is On; run Second Brain only when its Remote toggle is On. Render each actual target’s result and explicit skipped reasons.

- [ ] **Step 6: Keep Status Details and Doctor local-only.**

  Refine text only; do not route either through `sync_run` or Git remote commands.

- [ ] **Step 7: Run targeted tests and commit.**

  Run: `bash tests/cli/sync_test.sh && bash tests/cli/status_doctor_test.sh && bash tests/cli/settings_test.sh`

  Expected: exit 0.

  Commit: `git add runtime/settings.sh runtime/operations.sh runtime/health.sh tests/cli/settings_test.sh tests/cli/sync_test.sh tests/cli/status_doctor_test.sh && git commit -m "feat(cli): add approved home and sync experience"`

### Task 5: Run the complete regression and fixture UX acceptance pass

**Files:**
- Modify only if a failing test identifies a scoped defect: `runtime/ui.sh`, `runtime/settings.sh`, `runtime/operations.sh`, `runtime/health.sh`, and their CLI tests.

**Interfaces:**
- Consumes the completed cursor UX and all CLI fixture suites.
- Produces evidence that the approved flows preserve the Task 1–9 safety model.

- [ ] **Step 1: Run shell syntax validation.**

  Run: `bash -n haws.sh runtime/*.sh tests/cli/*.sh`

  Expected: exit 0.

- [ ] **Step 2: Run the full fixture suite.**

  Run: `bash tests/cli/run.sh`

  Expected: exit 0; record every suite count.

- [ ] **Step 3: Run adapter tests.**

  Run: `node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs`

  Expected: exit 0.

- [ ] **Step 4: Exercise the accepted flow in fixture mode and capture a transcript.**

  Use fixture HOME/repository only: first install -> Skills category -> AI checklist -> Remote toggle with a stubbed connection -> Preview Install -> Apply -> Home -> Status Details -> Doctor -> Sync. Verify cancelled drafts created no state and no remote call.

- [ ] **Step 5: Run whitespace and working-tree checks, then commit only UX-owned files.**

  Run: `git diff --check && git status --short`

  Expected: no whitespace errors; do not stage pre-existing unrelated changes.

  Commit: `git add <only files changed for discovered scoped defects> && git commit -m "test(cli): verify approved UX flows"`

## Out of Scope

- Choosing or restoring a Windows `.bat` launcher.
- Live installation, real remote connection tests, push, or changes to the user’s Codex home.
- Reopening the Task 1–9 architecture, AI-config architecture, skills architecture, root structure, or the 66-item agenda.
