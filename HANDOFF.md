# HAWS Cross-Device Checkpoint

## Current goal

Finish the HAWS fix for device-local skill links that remain bound to a
different Git worktree than the checkout currently running `haws.sh`.

## Current state

- Branch: `dev`
- Base commit before this checkpoint: `97fec8b` (`fix(hooks): make commit message checks advisory`)
- The worktree-link reconciliation change is still WIP and must not be treated as a completed fix.
- `main` remains clean; this checkpoint belongs to `dev`.

## Root cause currently established

Global Codex skill junctions and `${HOME}/.haws/skills-ownership.tsv` are
device-local and can point at the main checkout while HAWS is run from
`.worktrees/dev`. Step 4 then sees existing links that do not match the
current source. Before this revision, the repair path did not distinguish a
matching source in another Git worktree from an arbitrary path inside the
repository, and its dangling-link repair did not verify ownership.

## Changes in this WIP

- `haws.sh`: rebind only when the link resolves to the same relative skill
  path in another registered worktree and the previous manifest lists the
  skill; retain verified ownership as the first route, normalize Windows paths
  and select the most specific nested worktree root, cache Step 4 runtime-source
  lookups, and report actual Claude / Codex / plugin-owned counts.
- `tests/cli/repository_skill_test.sh`: cover dangling and unowned links from
  registered worktrees, plus preserving a link to an unregistered path inside
  the repository.
- `tests/cli/sync_test.sh`: add runtime-source-cache coverage.
- `README.md`: document the narrower ownership and rebind rules.

## Verification status

- `git diff --check`: passed for this revision (exit 0; no output).
- Tests: intentionally not run; the user asked to review the patch before one
  final test run.
- A partial run before this revision showed failures in worktree-link cases.
  Those results do not verify this revision.

## Exact resume point

1. Review the WIP diff, especially Windows junction handling and path
   normalization across main and dev worktrees.
2. After the user reviews the patch, run the agreed final test suite once.
3. Inspect the resulting output and diff before calling the fix complete.

## Remote handoff

This checkpoint is intended to be pushed to `origin/dev` so another device can
fetch the branch and continue from the exact WIP state. It is not a claim that
HAWS is fixed or test-green.
