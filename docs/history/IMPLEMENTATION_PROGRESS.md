# Implementation progress

Plan: E:/Human-AI-Working-Standard/docs/superpowers/plans/2026-09-12-old-base-selected-improvements-implementation.md

## Scope and decisions

- User authorized unattended implementation and tested batch commits on 2026-09-13. Merges and pushes remain prohibited.
- Task 1 complete: created isolated worktree on codex/old-base-selected-improvements at 71797228368959ab7a8d16b152da87e8452392b6. Reference checkouts remain unchanged.
- Task 2 / Batch 1 in progress. Tasks 3-9 continue after automated verification and review. User moved physical UX acceptance to the end so development can run unattended.
- Ruling: use real piped input and PTY checks where feasible instead of inventing the plan's undefined HAWS_TEST_KEYS API. This tests actual input paths; physical Windows key handling still needs user acceptance.
- Updated ruling: commit each verified and reviewed batch in this checkout, per the user's latest authorization. Never stage reference-checkout changes.

## Plan consistency review

| Tasks | Shared files/contracts | Finding |
| --- | --- | --- |
| 1 / 2 | New worktree / implementation destination | Consistent; branch and HEAD checked. |
| 2 / 3 | haws.sh / accepted menu | User permits automated gate now; physical acceptance remains pending at the end. |
| 3 / 4 | state APIs / draft lifecycle | Follow-up APIs need concrete signatures when implemented. |
| 4 / 5 | action plan / repository actions | Repository-only operations must execute, not just render. |
| 5 / 6 | catalog / sync targets | Candidate validation and remote advancement require actual fixture Git outcomes. |
| 6 / 7 | ownership and lock / safety | Read-only checks must not acquire mutating state automatically. |
| 7 / 8 | ownership / adapter integration | Adapter modifications remain separate from renderer. |
| 8 / 9 | tested behavior / documentation | Documentation must report pending user acceptance explicitly. |
| 2 internal | fixture assertions / launcher | Old base lacks HAWS_TEST_KEYS; use actual stdin paths. |
| 3 internal | settings_save calls / API list | Signature will be fixed by focused tests in Batch 2. |
| 4 internal | pre-integration persistence / partial recovery | Do not claim an atomic transaction. |
| 5 internal | catalog identity / destination names | Test both identities separately. |
| 6 internal | deadline / update result | Output labels alone cannot prove either behavior. |
| 7 internal | Windows links / available privileges | Unsupported link types remain unverified. |
| 8 internal | optional selected adapter / aggregate paths | Only run suites for selected files that exist. |
| 9 internal | clean status / commits | User authorizes reviewed batch commits; verify clean final state. |

## Verification

Implementation and verification report: BATCH1_REPORT.md (written by implementer).
Batch 1 automated gates: CLI 7/7, Windows 6/6, existing Codex agents 14/14; pre-commit gate passed. Independent reviewer approved the batch. Physical Explorer acceptance remains pending. Missing-Bash execution test is a minor coverage gap (static assertion only).

Task 2: implementation complete and reviewed; commit checkpoint follows. Next: Batch 2 compatible state.

## User correction after Batch 1

- Commit `941f8e8` matches much of the visible behavior but uses a separate `run_main_menu()` input/render loop and full-screen clear/redraw.
- User requires implementation-method fidelity, not only similar output. Old terminal behavior is comparable to video redraw in place; fast full-screen redraw is comparable to moving paper quickly and is rejected.
- Task 2A is now required before Batch 2: reuse or minimally refactor the old `interactive_checklist()` engine, remove the parallel renderer, preserve cursor hide/restore and relative row redraw, then test and review.
- Ponytail is mandatory: reuse existing code before adding code, delete duplication, use the fewest files, and add one focused check per non-trivial change.
- Execution routing: `gpt-5.6-luna` at `max` implements Tasks 2A-8; `gpt-5.6-sol` at `high` handles focused review/debugging; `gpt-6-astra` is reserved for final whole-branch review or unresolved architecture defects.

## Task 2A completion

- Reused the old checklist interaction path by extracting one `interactive_menu()` core with `menu` and `checklist` modes; `interactive_checklist()` now delegates to that core.
- Removed the parallel `run_main_menu()` reader/renderer and all full-screen `\033[H\033[2J` redraws. Main-menu movement uses the shared cursor hide/show, relative movement, and per-row clear path.
- Red evidence before the correction: CLI `7 passed, 1 failed`; Windows launcher `6 passed, 1 failed` on the method-fidelity assertions against `941f8e8`.
- Green evidence after the correction: `bash -n haws.sh` plus CLI `8/8`, Windows launcher `7/7`, Codex-agent regression `14/14`, and `git diff --check` all passed.
- PTY runtime check exercised Down then q and observed cursor hide/restore, relative row movement, and per-row clearing; the source audit found no full-screen clear sequence in `haws.sh`.
- Self-review found no new dependency, renderer/input duplication, dead main-menu renderer, or changes outside the implementation worktree. Physical Explorer acceptance remains `[Unverified]` and no merge or push was performed.

## Task 3 / Batch 2 completion

- Added the smallest local-state boundary to the old `haws.sh`: settings TSV load/save, compatible AI-environment disabled-file load/save, ownership records, and atomic sync-lock acquire/release.
- Preserved the existing `skills.disabled` loader/saver and added a legacy-named loader alias; no replacement or migration rewrote that file. Empty `ai-configs/environments.disabled` leaves every environment enabled.
- Settings and ownership files use complete temporary files followed by rename. A disposable pre-rename failure leaves the previous settings file byte-for-byte intact and removes the stage file. Unchanged disabled-environment selections compare parsed entries and leave original bytes unchanged, including CRLF.
- Red evidence: the new state suite initially failed all 9 tests because the state APIs were absent from the old `haws.sh` path.
- Green evidence: Batch 2 state suite `13/13`; Batch 1 launcher/menu suite `8/8`; Windows launcher suite `7/7`; Codex-agent regression `14/14`; `bash -n` and `git diff --check` passed.
- Self-review found no new runtime module, network operation, second renderer, or unbounded lock recovery. Physical Windows acceptance and human acceptance remain `[Unverified]` for the final end-to-end gate. No reference checkout was edited; no merge or push was performed.

## Task 4 / Batch 3 completion

- Added Setup/Home lifecycle controllers and draft/preview/final APIs to the old `haws.sh` engine. Bare launch now selects Setup until measured completion state exists, then Home; explicit `haws.sh menu` still opens the accepted old main menu.
- Setup presents `Use Default Setup`, `Customize Settings`, and `Exit`. Settings remains lifecycle-neutral, uses the shared old-derived menu reader/redraw path, supports draft-only Auto Update and Second Brain toggles, requires confirmation for Reset to Defaults, and keeps Apply separate from final Install/Update.
- Preview uses exact lifecycle vocabulary: `Preview Install` or `Preview Update`, `Install`/`Update`, `Back to Settings`, and `Cancel`. No-change Update exposes only `Back to Settings` and `Back to Home`. Home routes explicit Sync, Settings, Doctor, Status Details, Uninstall, and Exit.
- Final application persists settings before integration and records per-action progress. Injected failure reports `Partial failure`, `Completed: settings`, and `Remaining: integration` without claiming atomicity; successful fixture installation writes the completion marker, after which bare launch enters Home.
- Red evidence: the first lifecycle run had 10 failing route tests because Setup/Home/draft/Preview were absent; after the settings-engine fix, old Skills regression was restored from 7/8 to 8/8.
- Green evidence: lifecycle suite `12/12`; launcher/menu `8/8`; local state `13/13`; Windows launcher `7/7`; Codex-agent regression `14/14`; `bash -n` and `git diff --check` passed.
- Self-review confirmed no second raw-key loop or full-screen clear, draft cancellation preserves existing settings/environment bytes, and Home does not auto-run Sync or Doctor. Physical Explorer verification and human acceptance remain `[Unverified]`; no reference checkout was edited and no merge or push was performed.
