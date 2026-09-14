# Cross-device handoff: selected improvements

Date: 2026-09-14

## Resume point

- Repository: `Human-AI-Working-Standard`
- Worktree used: `.worktrees/cli-task1`
- Branch: `codex/old-base-selected-improvements`
- Last implementation commit: `9ab4499 feat(ui): clarify HAWS navigation and window identity`
- Checkpoint 1 commit: `774cab1`
- Checkpoint 2 commit: `0671a2d feat(settings): present logical skills clearly`
- Checkpoint 3 commit: `9ab4499`
- Plan: `docs/superpowers/plans/2026-09-14-haws-selected-improvements.md`
- Design spec: `docs/superpowers/specs/2026-09-14-haws-selected-improvements-design.md`

Checkpoint 3 is complete. Stop here until the user explicitly authorizes the
next checkpoint. Checkpoint 4 has not started.

## What Checkpoint 3 changed

- `haws.bat` establishes the product window title while remaining a thin
  launcher.
- `haws.sh` sets the terminal title for non-source-only launches and adds
  concise purpose/control hints to the relevant screens.
- Home opens with a safe Settings default instead of implicitly running Sync.
- Preview opens with a safe Back default instead of implicitly applying or
  installing.
- Dirty settings drafts ask before being discarded; Back preserves the parent
  draft and Cancel/Q does not persist it.
- Tests were added or adjusted in the launcher menu, settings flow, and Windows
  launcher execution suites.

## Verification evidence

All commands below exited `0` in the source worktree:

```text
bash tests/cli/launcher_menu_test.sh
13 passed, 0 failed

bash tests/cli/settings_flow_test.sh
27 passed, 0 failed

node --test tests/windows_launcher_execution.test.mjs
10 passed, 0 failed, 1 skipped

bash tests/cli/sync_test.sh
12 passed, 0 failed

bash -n haws.sh tests/cli/launcher_menu_test.sh tests/cli/settings_flow_test.sh
git diff --check
```

The commit hook also passed the broader CLI quality gates, including launcher,
local-state, settings-flow, catalog, repository/skill, sync, status/doctor,
and uninstall tests.

## `[Unverified]`

One Windows test was skipped, not failed:

`Windows file symlink ownership removes only the symlink when executable`

Reason: `file symlink creation requires Windows link privilege`.

This is a host-capability gap. If full physical verification is desired on the
next device, enable Windows Developer Mode or grant the symlink privilege and
rerun:

```text
node --test tests/windows_launcher_execution.test.mjs
```

Other physical acceptance items remain separate: double-clicking the Windows
launcher, native cursor behavior, and external authenticated remotes.

## Preservation rules

- Do not start Checkpoint 4 or later without explicit user authorization.
- Do not modify `main`, push, merge, or alter dirty submodules/reference
  checkouts.
- The dirty submodule `skills/standalone/planning-with-files` was not touched.
- Existing modified `HANDOFF.md` and unrelated untracked `.planning/`,
  `.superpowers/`, and `docs/` content were preserved. Do not reset, clean, or
  stage them wholesale.
- Global-install/link behavior, Add Repo, Ponytail installation, Sync, and
  Uninstall implementations were not expanded by Checkpoint 3.

## Moving this state to another device

The branch is local and was not pushed. Transfer or publish the branch using
the user's approved mechanism, then on the next device check out
`codex/old-base-selected-improvements` and verify `git log --oneline -3` ends at
`9ab4499`. Confirm the handoff file and the plan/spec are present before doing
any new work. The first action after resuming should be review/confirmation,
not implementation.
