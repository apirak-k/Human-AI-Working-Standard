# HAWS Sync and Step 4 Repair

## Outcome

The Step 4 slowdown and stale skill-link issue have been addressed for the
reported worktree-switch scenario. Sync caches runtime-source lookups during
Step 4, only rebinds a link when HAWS ownership or the manifest plus a matching
registered worktree proves it is the same skill, and preserves unrelated links.
Manifest pruning also keeps a repaired link when a skill's ID changes from a
legacy name to a source-qualified name.

The top-level `sync` and `update` commands use the same sync flow. Auto Update
controls remote source refresh; Step 4 still verifies and reconciles links when
remote refresh is disabled.

## Live Device Repair

The validation device had three Codex junctions pointing to removed worktrees.
They were repointed to the current active HAWS skill sources. This changed only
device-local links and is intentionally not part of the Git change.

## Verification

- Automated CLI suite: 167 tests passed across launcher/menu, local state,
  settings, catalog, repository/skill, sync, status/doctor, uninstall, and
  lifecycle/plugin coverage.
- Focused Windows link regressions, shell syntax checks, and `git diff --check`
  passed.
- User-reported live trial on 2026-09-24: Sync with Auto Update off completed
  quickly twice. With Auto Update on, one run completed with a short,
  acceptable wait at Step 4 and no reported error. These timings were not
  independently measured by the agent.

## Limits

The automated checks use disposable fixtures; the live trial covers the
reported device and settings only. It does not establish behavior on every
device or AI client. Device-local junctions and configuration are not synced
or committed.
