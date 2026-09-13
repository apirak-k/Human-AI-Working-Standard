# HAWS Current Project State

**Status authority:** This is the single source of truth for the current HAWS recovery state.
**Product contract:** [spec.md](spec.md) defines the approved product behavior.
**Last inspected:** 2026-09-13 (Asia/Bangkok), current recovery continuation validation.

## Current Git State

- Working branch: `recovery/clean-base`
- Recovery checkpoint base: `1a4430f` — `chore(checkpoint): save verified recovery state before performance optimization`
- The current continuation preserves the existing performance changes in `runtime/catalog.sh`, `runtime/health.sh`, `runtime/integrations.sh`, and `runtime/settings.sh`, and adds only the targeted help/settings fixes plus their regression coverage and this evidence update.
- `CODEX_HANDOFF.md` was inspected and remains preserved as an untracked handoff artifact; it is outside the requested commit scope.
- No merge to `main` and no push is authorized by this state document.

## Recovery Tasks 1–7

| Task | Scope | Implementation state | Acceptance state |
| --- | --- | --- | --- |
| 1 | Loop fixes | Complete | Preserve; reopen only for a demonstrated regression. |
| 2 | Approved UX improvements | Complete | Preserve; do not redesign during Task 3. |
| 3 | Known-good TUI behavior | Implemented in committed recovery work; candidate redraw fix remains uncommitted | **Current task.** Automated and real-terminal checks plus user UX review are still required. |
| 4 | Clean-base validation | Full isolated regression suite and shell syntax check passed; direct real-repository status/doctor invocation hung without output and was stopped | User-accepted on 2026-09-12. |
| 5 | Windows `.bat` entry | Existing thin launcher verified; minimal login-shell initialization fix applied and covered by launcher tests | User-accepted on 2026-09-12. |
| 6 | Cross-platform parity | Windows launcher and shared-core parity checks passed; macOS/Linux execution is not available in this workspace | User-accepted on 2026-09-12. |
| 7 | Documentation and final validation | README and live state documentation aligned with final behavior; final available regression suite passed | **Current task.** Awaiting user review of final validation report; acceptance not claimed. |

## Current Decisions

- Windows may use `haws.bat` as a first-class **thin launcher**; it must forward to the shared HAWS behavior and must not duplicate Settings, Sync, Doctor, or state logic.
- `haws.sh` remains the shared core entrypoint for macOS/Linux and the launcher target on Windows.
- Settings remain draft-only until the reviewed Install/Update action.
- Bare launch must not auto-sync or auto-run Doctor.
- Do not merge or push without the user's explicit authorization.

## Current AGY Handoff Continuation (2026-09-13)

Scope is limited to `recovery/clean-base` recovery only. No reset, merge, push,
worktree switch, or old-base Batch 7/8 work was performed or started.

Targeted fixes:

- `haws.sh`: `help`, `--help`, and `-h` now print the shared usage text and exit 0.
- `runtime/settings.sh`: an unloaded skills draft now displays `all active (default)` rather than `0 active`.
- `runtime/settings.sh`: lazy skills loading synchronizes the original skills baseline, preventing a false `Discard Changes?` prompt when Skills is opened and left unchanged.

TDD evidence:

- RED: the new settings regressions failed while the existing settings checks passed (`47 passed, 2 failed`); the new launcher help check failed because the aliases returned exit 1.
- GREEN: `tests/cli/run.sh` exited 0 with catalog 6, cross-platform 5, first-install 10, settings 49, state 12, status/doctor 6, sync 8, uninstall 7, and Windows launcher 8 tests passed (111 total).
- GREEN: `node --test tests/windows_launcher_execution.test.mjs` exited 0 (`10` tests passed, `0` failed).
- GREEN: `.\haws.bat --help` printed the shared usage text and returned `$LASTEXITCODE = 0`.

Platform limits:

- Direct macOS/Linux execution and native macOS/Linux TTY behavior: [Unverified].
- Physical Windows Explorer double-click behavior and native interactive-console/TUI behavior outside the executed launcher checks: [Unverified].

The requested commit boundary is this validated change set only. No later
recovery batch is in scope.

## Task 3 Subtask 5 Evidence (2026-09-12)

Final fixture verification completed with Git Bash (`C:\Program Files\Git\bin\bash.exe`, PATH extended with `/usr/bin:/bin`):

- `tests/cli/settings_test.sh`: exit 0 — 47 passed, 0 failed.
- `tests/cli/first_install_test.sh`: exit 0 — 9 passed, 0 failed.
- `tests/cli/state_test.sh`: exit 0 — 12 passed, 0 failed.
- `tests/cli/run.sh`: exit 0 — catalog 6, cross-platform 5, first-install 9, settings 47, state 12, status/doctor 6, sync 8, uninstall 7, Windows launcher 6 passed.
- `git diff --check`: exit 0.

Manual Git Bash TTY trial used isolated fixture `/tmp/haws-manual.wzhxhy` with fixture-only `HOME` and `HAWS_REPO_DIR`. Observed Settings render, arrow navigation into Skills, `Q` return to Settings, `Q` exit, and terminal redraw/clear controls without duplicate visible frames. No real user HOME or repository was used. Direct macOS/Linux TTY behavior remains unverified.

Task 3 user UX acceptance: **Pending user review; not claimed by automation evidence.**

## Task 4 Clean Base Validation Evidence (2026-09-12)

Required validation executed on the isolated CLI fixture suite:

- `bash -n haws.sh`: exit 0.
- `bash tests/cli/run.sh`: exit 0. Catalog 6, cross-platform 5, first-install 10, settings 47, state 12, status/doctor 6, sync 8, uninstall 7, and Windows launcher 6 tests passed; 0 failures.
- `git diff --check`: exit 0.

Direct read-only commands `bash haws.sh status --details` and `bash haws.sh doctor` were attempted against the current checkout. They produced no output and exceeded the validation window; the process was interrupted. Classification: **pre-existing/unrelated validation hang or environment-specific issue, not proven to be a recovery regression**. No source change was made for this observation.

Failure classification:

- Recovery regression: none observed in the isolated regression suite.
- In-scope defect: none observed in the required automated checks.
- Pre-existing/unrelated: direct real-repository status/doctor hang; cause remains unverified.

Manual acceptance checklist: automated fixture coverage passed for product flow, Settings/state, repositories, skills, AI environments, second brain, TUI, Home/Sync/Status/Doctor, and architecture assertions. A direct real-repository TTY walkthrough was not repeated in Task 4; platform paths outside Git Bash remain unverified.

Clean Base approval: **awaiting user review; not claimed.**

## Task 5 Windows `.bat` Entry Evidence (2026-09-12)

- Inspected `haws.bat` before changes. It remains a thin launcher: root/script resolution, Git Bash discovery, working-directory selection, argument forwarding, and exit-code propagation only.
- TDD red phase: the new login-shell test failed (`6 passed, 1 failed`) because the launcher invoked `bash.exe` without `--login`; direct `cmd.exe` invocation consequently failed before HAWS could resolve `dirname`.
- Minimal fix: invoke the selected Bash runtime as `"%BASH_CMD%" --login "%HAWS_SCRIPT%" %*`.
- `tests/cli/windows_launcher_test.sh`: exit 0 — 7 passed, 0 failed.
- `git diff --check`: exit 0.
- Manual Windows trial: `cmd.exe /d /c haws.bat --help` reached shared `haws.sh` and displayed its usage. A separate isolated fixture trial invoked `haws.bat settings` with temporary `HOME`, `HAWS_REPO_DIR`, and `HAWS_TEST_KEYS=cancel`; it rendered `HAWS Setup` and the shared Settings surface, performed no real installation or sync, and exited 1 from the intentional cancel path.

Task 5 classification:

- In-scope defect fixed: Git Bash was not started as a login shell, causing the Windows launcher to fail before shared HAWS execution in the tested `cmd.exe` environment.
- Recovery regression: none observed in the Windows launcher suite.
- Pre-existing/unrelated failures: none in the focused launcher tests; direct `--help` exit 1 is the existing shared CLI usage behavior, not a launcher error.

Task 5 user acceptance: **Awaiting user review; not claimed.** Task 6–7 remain out of scope.

## Task 6 Cross-Platform Parity Evidence (2026-09-12)

| Behavior | Windows `haws.bat` | macOS/Linux `haws.sh` | Evidence / status |
|---|---|---|---|
| First install | Thin launcher forwards to shared core; shared core enters `HAWS Setup` | Shared core entry exists | Windows fixture/manual evidence; macOS/Linux `[Unverified]` |
| Installed bare launch / Home | Shared core owns install-state decision and Home flow | Same shared core | Static/shared-core inspection; macOS/Linux `[Unverified]` |
| Settings draft / Preview | Forwards unchanged to shared `haws.sh` | Native shared entry | Shared settings tests 47 passed; macOS/Linux `[Unverified]` |
| Sync | Explicit command forwarding only | Explicit shared command | sync tests 8 passed; macOS/Linux `[Unverified]` |
| Status | Explicit command forwarding only | Explicit shared command | status/doctor tests 6 passed; macOS/Linux `[Unverified]` |
| Doctor | Explicit command forwarding only | Explicit shared command | status/doctor tests 6 passed; macOS/Linux `[Unverified]` |
| Exit codes | `.bat` captures and returns `%ERRORLEVEL%` | Shell returns shared command status | launcher tests 7 passed; direct macOS/Linux `[Unverified]` |
| TUI behavior | Uses shared `haws.sh` TUI, no Windows TUI duplication | Uses same shared TUI | Task 3 Git Bash TTY evidence; macOS/Linux TTY `[Unverified]` |

Automated evidence:

- `bash tests/cli/cross_platform_test.sh`: exit 0 — 5 passed, 0 failed.
- `bash tests/cli/windows_launcher_test.sh`: exit 0 — 7 passed, 0 failed.
- `bash tests/cli/first_install_test.sh`: exit 0 — 10 passed, 0 failed.
- `bash tests/cli/settings_test.sh`: exit 0 — 47 passed, 0 failed.
- `bash tests/cli/state_test.sh`: exit 0 — 12 passed, 0 failed.
- `bash tests/cli/status_doctor_test.sh`: exit 0 — 6 passed, 0 failed.
- `bash tests/cli/sync_test.sh`: exit 0 — 8 passed, 0 failed.
- `git diff --check`: exit 0.

The only observed parity-test failure was a stale assertion for the pre-Task-5 forwarding line without `--login`; it was classified as a test expectation mismatch caused by the accepted Task 5 launcher fix and updated accordingly. No product behavior divergence was found. Different launcher source code is intentional; business/product behavior remains in shared `haws.sh`.

Remaining unverified behavior: direct execution on macOS/Linux, macOS/Linux-specific shell/runtime environment, native TTY rendering there, and physical Windows double-click UI behavior. These require platform/manual validation outside this workspace.

Task 6 user acceptance: **Awaiting user review; not claimed.** Task 7 remains out of scope.

## Task 7 Documentation and Final Validation Evidence (2026-09-12)

Documentation updated:

- `README.md` now documents both launchers: Windows `haws.bat` (Git Bash discovery/login-shell forwarding) and macOS/Linux `./haws.sh` (shared core entry).
- README documents first-install `HAWS Setup` with `Use Default Setup`/`Customize Settings`, installed `HAWS Home`, Settings draft → `Apply` → `Preview Install`/`Preview Update` → `Install`/`Update`, explicit `Sync`, and read-only/diagnostic `Status`/`Doctor`.
- README removes the obsolete `Apply & Install`/`Apply Selection` wording and avoids claiming direct macOS/Linux execution has been verified.
- README explicitly states bare launch does not auto-sync or auto-run Doctor.

Final validation commands and results (Git Bash with `/usr/bin:/bin` available):

- `bash -n haws.sh`: exit 0.
- `bash tests/cli/run.sh`: exit 0. Catalog 6, cross-platform 5, first-install 10, settings 47, state 12, status/doctor 6, sync 8, uninstall 7, and Windows launcher 7 passed; 0 failures.
- `git diff --check`: exit 0.

No validation failures remain. The earlier Task 4 real-checkout `status --details`/`doctor` hang remains a known environment-specific limitation and was not retried or silently reclassified.

Remaining `[Unverified]` paths:

- direct macOS/Linux execution and native shell/runtime behavior;
- macOS/Linux TTY rendering and interactive UX;
- physical Windows Explorer double-click behavior outside the `cmd.exe` manual invocation;
- any platform-specific Git Bash/MSYS installation layout not represented by the tested Windows environment.

Final architecture: platform-native launchers remain intentionally different, while product behavior and state semantics remain in shared `haws.sh`/`runtime/` code. No Task 7 source feature work was added.

Merge-readiness: **technically ready for user merge decision, subject to the listed `[Unverified]` platform paths.** No merge, push, or commit was performed.

Task 7 user acceptance: **Awaiting user review; not claimed.**

## Immediate Next Action

Stop for user review and merge decision. No further Task 7 work is pending in this workspace; do not merge or push without explicit authorization.

## Historical Documents

Older plans and handoffs remain useful for rationale and Git history, but are not status authorities. When they conflict with this file or `spec.md`, this file governs live state and `spec.md` governs product requirements.
