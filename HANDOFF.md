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
current source, preserves some of them through the ownership guard, and can
leave skills mismatched while the serial linking pass appears stuck.

## Changes in this WIP

- `haws.sh`: repair dangling links, recognize HAWS workspace-family links,
  cache runtime source resolution during Step 4, and report actual Claude /
  Codex / plugin-owned counts.
- `tests/cli/repository_skill_test.sh`: add dangling-link and unowned-worktree
  link cases.
- `tests/cli/sync_test.sh`: add runtime-source-cache coverage.

## Verification status

- `git diff --check`: passed before checkpoint (exit 0; no output).
- Full CLI regression suite: intentionally not run for this checkpoint; run
  once after the user reviews the WIP.
- A previously interrupted partial run showed failures in the new and existing
  worktree-link cases. Do not claim the fix is complete until those cases pass.

## Exact resume point

1. Review the WIP diff, especially Windows junction detection/removal and path
   normalization for main-vs-dev worktrees.
2. Run the focused repository/sync regression tests once the implementation is
   adjusted.
3. Run the full CLI suite, inspect the final diff, then decide whether to keep
   this checkpoint commit or amend it.

## Remote handoff

This checkpoint is intended to be pushed to `origin/dev` so another device can
fetch the branch and continue from the exact WIP state. It is not a claim that
HAWS is fixed or test-green.
