# HAWS Old-Base Implementation Specification

**Status:** Current implementation contract for the old-base selected worktree  
**Implementation worktree:** `codex/old-base-selected-improvements`  
**Reference checkout:** `.worktrees/codex-haws-bootstrap`  
**Last automated verification:** 2026-09-13 on Windows PowerShell 7.6.5, Git Bash 5.3.15, Node.js v22.14.0, and Git 2.55.0.windows.2
**Language:** English

This specification describes behavior implemented in the old-base worktree. It
does not claim physical Windows acceptance or external authenticated remote
acceptance until those actions are executed.

## 1. Platform entry

- Windows primary entry is `haws.bat`.
- macOS and Linux entry is `./haws.sh`.
- `haws.bat` locates Git Bash and delegates to the shared `haws.sh` engine.
- The launcher files may differ by platform. Shared behavior and state
  semantics remain in `haws.sh`.
- Legacy convenience batch files remain references; they are not required as a
  single cross-platform launcher.

## 2. Interaction contract

The implementation keeps the old terminal interaction engine:

- `Up`/`Down` moves the current menu row.
- `Enter` selects the current row.
- `Space` toggles checklist items.
- `Q`/`q` leaves the current selector.
- Cursor movement and redraw happen on the existing menu surface.
- No replacement full-screen renderer is introduced.

Primary routes:

```text
First launch -> HAWS Setup
Setup -> Use Default Setup -> Preview Install -> Install -> HAWS Home
Setup -> Customize Settings -> Apply -> Preview Install -> Install -> Home
Later launch -> HAWS Home
Home -> Sync | Settings | Doctor | Status Details | Uninstall | Exit
Settings -> Apply -> Preview Install/Update -> Install/Update -> Home
```

Cancel and Back preserve or discard draft state according to the existing old
menu route. Final Install/Update is the first point where the draft persists.

## 3. State and sync rules

- Settings values are stored as validated TSV state.
- Remote values reject control characters, option-like values, and malformed
  remote syntax.
- Second Brain Remote stays in draft until final validation and Apply.
- Toggle does not access the remote.
- Final Apply and Home Sync use bounded remote operations.
- Sync validates a candidate before activating it.
- Sync reports measured `updated`, `up-to-date`, `skipped`, `blocked`,
  `failed`, or `timeout` results.
- HAWS update preserves the current branch and does not detach the checkout.
- Sync lock release occurs on success, failure, and interrupt.

## 4. Source-aware repositories and skills

- Repository changes use the old Settings/Repositories route and draft state.
- Duplicate URL and destination collisions are rejected before mutation.
- Source identity remains in catalog state.
- Legacy single-skill and multi-skill-pack organization remains visible.
- Disabled source-aware skills are not linked by legacy sync consumers.
- Reference and implementation submodules remain separate from this contract.

## 5. Read-only health

`status` and `doctor` inspect current state only:

- They do not repair files.
- They do not install hooks.
- They do not fetch, pull, push, or run Sync.
- They do not rewrite settings or ownership records.
- Findings use measured `Ready`, `Attention`, or `Blocked` labels.
- `doctor --json` returns the measured overall classification.

## 6. Ownership-aware uninstall

- Uninstall shows a preview before mutation.
- Dry-run and preview do not remove files or rewrite state.
- Only recorded HAWS-owned items with matching type and fingerprint are
  removable.
- Modified owned files are preserved and reported.
- Unrelated files and Second Brain data remain untouched.
- Dirty owned repositories are blocked.
- Interrupts leave remaining ownership records recoverable.
- Windows junctions are removed without deleting their targets when the host
  supports the operation. Unsupported link privileges are `[Unverified]`.

## 7. Adapter boundary

- Codex native agent profiles are installed, checked, and uninstalled through
  `ai-configs/codex/agents.mjs`.
- Existing generated profiles and unrelated profiles are preserved according
  to ownership hashes.
- Adapter and template files are not copied wholesale from the reference
  checkout.
- Current adapter audit found no selected adapter delta between the old-base
  and reference trees.

## 8. Evidence

Final automated verification executed on 2026-09-13:

- `bash -n haws.sh && bash tests/cli/run.sh` under Git Bash exited 0: 84/84
  CLI tests passed (9 + 14 + 19 + 6 + 7 + 12 + 7 + 10).
- `node --test ai-configs/codex/agents.test.mjs
  tests/windows_launcher_execution.test.mjs` exited 0: 23 passed and 1
  skipped. The Codex adapter suite passed 14/14; the Windows launcher suite
  passed 9/10, with the file-symlink capability skipped as `[Unverified]`.
- `ai-configs/codex/skills.test.mjs` and `tests/cli/adapters_test.sh` are not
  present in either compared adapter tree; no placeholder tests were created.
- `git diff --check` passed after the documentation update.

These results are automated evidence, not physical Windows verification or
human acceptance. No production code or submodule content was changed in
Batch 8.

## 9. Remaining acceptance

- `[Unverified]` Launch `haws.bat` by double-clicking from Explorer.
- `[Unverified]` Exercise Setup, Settings, Preview, Back, Cancel, Install/Update,
  Home, Sync, Status, Doctor, and Uninstall on a disposable Windows fixture.
- Record actual terminal cursor behavior and any rejected route.
- `[Unverified]` Test external authenticated remotes separately.
- Keep old-base, current, and reference checkouts until the user authorizes
  merge or retirement.

No merge or push is part of this specification.
