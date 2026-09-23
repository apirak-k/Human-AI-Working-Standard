# HAWS Cross-Device Checkpoint

## Current goal

Finish the HAWS fix for Step 4 skill-link reconciliation when device-local
links point at another registered Git worktree, while preserving unrelated
user links.

## Current state

- Branch: `dev`
- Base commit before this checkpoint: `97fec8b` (`fix(hooks): make commit message checks advisory`)
- Worktree-link reconciliation and Step 4 runtime-source caching are implemented.
- Final manifest-pruning regression fix is committed as `83929be` and pushed
  to `origin/dev`.
- `main` remains clean; this checkpoint belongs to `dev`.

## Root cause currently established

Global Codex skill junctions and `${HOME}/.haws/skills-ownership.tsv` are
device-local and can point at the main checkout while HAWS is run from
`.worktrees/dev`. Step 4 then sees existing links that do not match the
current source. Before this revision, the repair path did not distinguish a
matching source in another Git worktree from an arbitrary path inside the
repository, and its dangling-link repair did not verify ownership.

The final regression exposed a second issue: after Step 4 repaired a dangling
or legacy link, pruning compared full manifest rows. A legacy `skill:<name>`
row therefore looked removed when the current manifest used a source-qualified
ID, and pruning deleted the just-created link even though its target was still
active. Pruning now retains a previous entry when the current manifest still
contains the same environment target.

## Changes in this WIP

- `haws.sh`: rebind only when the link resolves to the same relative skill
  path in another registered worktree and the previous manifest lists the
  skill; retain verified ownership as the first route, normalize Windows paths
  and select the most specific nested worktree root, cache Step 4 runtime-source
  lookups, and report actual Claude / Codex / plugin-owned counts.
- `tests/cli/repository_skill_test.sh`: cover dangling and unowned links from
  registered worktrees, plus preserving a link to an unregistered path inside
  the repository. Directory-link fixtures use Windows junctions on Git Bash
  and compare filesystem identity rather than relying on `realpath -m` to
  resolve a junction.
- `tests/cli/sync_test.sh`: add runtime-source-cache coverage.
- `README.md`: document the narrower ownership and rebind rules.

## Verification status

- `bash tests/cli/run.sh`: passed all 167 tests across launcher/menu, local
  state, settings flow, catalog, repository/skill, sync, status/doctor,
  uninstall, home entrypoint, and lifecycle/plugin suites.
- Focused link regressions: 3 passed, 0 failed on Windows Git Bash.
- `bash -n haws.sh tests/cli/repository_skill_test.sh`: passed.
- `git diff --check`: passed.
- Tests use disposable fixtures. The real user `HOME` and HAWS environment
  were not changed; live Codex skill discovery remains unverified.

## Exact resume point

1. The verified implementation is complete and available on `origin/dev`.
2. Live Codex skill discovery remains unverified because this task used only
   disposable fixtures; verify it on the target device if needed.

## Remote handoff

The completed branch is available on `origin/dev` so another device can fetch
the verified fix. Test success is not the same as human acceptance or proof of
live Codex skill discovery.
