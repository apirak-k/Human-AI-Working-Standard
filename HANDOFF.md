# HAWS Recovery Checkpoint & Handoff Dossier

**Date**: 2026-09-11  
**Branch**: `recovery/clean-base`  
**Base Commit / Head**: `f538225` (prior to this checkpoint commit)  
**Corpus / Repo**: `Human-AI-Working-Standard`  
**Authoritative Contract**: `spec.md` (English, strictly sequential)  

---

## 1. Task Execution Status

| Task | Title | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Task 1** | Loop Fix Only | **Complete** | Resolved pre-commit hang, `run_doctor` recursion, and protected with regression tests. |
| **Task 2** | Approved UX Improvements Only | **Complete** | Restored approved UX feedback, Skills hierarchy (single/packs), vertical preview flows, draft-first settings, and lazy catalog loading. |
| **Task 3** | Known-Good TUI Behavior Only | **DEFERRED, NOT Approved** | Automated tests passed, but manual acceptance still found known Settings/TUI bugs. The user intentionally chose to continue instead of manually debugging Task 3 now. A checkpoint does NOT mean Task 3 is complete or approved. |
| **Task 4** | Clean Base Validation Only | **In Progress** | Broad validation across Tasks 1–3, automated tests, PTY/terminal simulation, draft/state, Skills, Home, Status, and Doctor. |
| **Task 5** | Windows `.bat` Entry Only | **Not Started** | Deferred until Task 4 validation is complete and approved. |
| **Task 6** | Cross-Platform Parity | **Not Started** | Deferred. |
| **Task 7** | Documentation + Final Validation | **Not Started** | Deferred. |

---

## 2. Changed Files in Recovery (`recovery/clean-base`)

The following files have been modified or added during the recovery process:
- `haws.sh`: Entrypoint runtime loading, non-interactive bare launch detection, doctor/sync integration dispatch, interactive terminal detection (`[ -t 0 ]`).
- `runtime/ui.sh`: In-place TUI cursor menu (`ui_cursor_menu`), multi-select checklist (`ui_checklist`), dynamic `Q` context labeling (Back / Cancel / Exit), terminal key reading via interactive stdin (`[ -t 0 ]`), ANSI cursor rewind and redraw without frame accumulation.
- `runtime/settings.sh`: Settings draft lifecycle, repository add/remove plan integration, URL determinism (`_settings_repo_path_from_url`), collision checks, lazy skills loading, preview update/install generation.
- `runtime/integrations.sh`: Integration plan generator with source add (`add-source`) and source removal (`remove-source`), owned skill link pruning on detach.
- `runtime/health.sh`: Doctor recursion guard, read-only diagnostic checks.
- `tests/cli/settings_test.sh`: 34 regression tests covering cursor menu, checklist, select all, lazy skills loading, draft isolation, preview review, and uninstall visibility.
- `tests/cli/first_install_test.sh`: 9 tests verifying clean machine first install, draft defaults, and non-mutating preview.
- `tests/cli/cross_platform_test.sh`: 3 tests verifying command surface consistency.
- `tests/cli/status_doctor_test.sh`: 6 tests verifying read-only status and doctor behavior.
- `tests/cli/catalog_test.sh`: 6 tests verifying source and skill discovery rules.
- `tests/cli/state_test.sh`: 12 tests verifying atomic writes, settings defaults, and lock safety.
- `tests/cli/sync_test.sh`: 8 tests verifying sync lock, dirty source blocking, and network guard.
- `tests/cli/uninstall_test.sh`: 7 tests verifying exact preview and owned file unlinking.

---

## 3. Test Results at Checkpoint

All 8 CLI regression test suites pass cleanly on Git Bash:
- `catalog_test.sh`: 6 passed, 0 failed
- `cross_platform_test.sh`: 3 passed, 0 failed
- `first_install_test.sh`: 9 passed, 0 failed
- `settings_test.sh`: 34 passed, 0 failed
- `state_test.sh`: 12 passed, 0 failed
- `status_doctor_test.sh`: 6 passed, 0 failed
- `sync_test.sh`: 8 passed, 0 failed
- `uninstall_test.sh`: 7 passed, 0 failed
**Total**: 85 passed, 0 failed across all unit suites.

---

## 4. Known Limitations & Deferred Task 3 Defects

1. **Terminal TUI Interaction Subtleties**:
   - In manual testing, certain terminal configurations (such as mintty vs conhost) may handle Escape timeouts or arrow key sequences differently.
   - Fast repeated keystrokes or terminal resizing during active redraw can cause minor cursor positioning shifts.
2. **Settings Lifecycle Wording vs `spec.md`**:
   - `spec.md` (Sections 5 & 6) specifies a lifecycle-neutral `HAWS Settings` title with `Use Default Setup` on the Setup landing page.
   - Current implementation uses `HAWS Settings — First Install` when uninstalled, which will be reconciled during Task 4/future clean base alignment.
3. **Repository Multi-Select Removal**:
   - Submodule deinit/rm requires Git index operations during apply; edge cases with uncommitted parent repo state must be safeguarded.
4. **Deferred Status**:
   - The user intentionally chose to defer manual debugging of Task 3 at this checkpoint to proceed with Task 4 Clean Base Validation. Task 3 remains unapproved and open for final acceptance after validation.
