# Native lifecycle continuation

Goal: preserve the existing HAWS behavior while replacing the shell lifecycle
incrementally. Base: `b6410eb`, live checkout `codex/go-modernization` tracking
`origin/dev`. The separate dirty local `dev` worktree remains untouched.
Delivery is `HEAD:dev` only; no main change or Release.

## Priority 1 — Setup and Settings

- [x] Native state store: compatible TSV defaults/aliases, environment and skill
  selections, bounded reads, safe writes, stale-draft detection and rollback.
- [x] Native catalog: tracked/device/custom sources, source-aware identities,
  metadata/filtering, effective and baseline disabled selections.
- [x] Native repository and Second Brain configuration actions: preflight,
  ownership checks, transactional connect, no personal data publication.
- [x] Native Setup/Settings draft, reset, preview, cancellation, final apply and
  recovery markers through the existing Go TUI. Retain the Home structure.
- [x] Parity/safety tests, real isolated launcher exercise, Go tests/vet,
  legacy regressions, vulnerability check, available native CI.
- [x] Review, update Handoff, commit and push verified milestone to dev.

Implementation boundaries: `internal/settings` owns persisted configuration,
catalog and configuration actions; `internal/tui` renders the draft flow;
`internal/app/settings.go` applies approved changes and invokes the existing
authoritative Sync once when integrations change. Settings edits stay in
memory until confirmation. Component Sync remains explicitly legacy until
its own parity migration passes. The Go-hosted Sync now migrates the Second
Brain target natively while retaining the legacy orchestrator for the other
targets.

## Priority 2 progress — Native Sync

- [x] Second Brain target: Go reads the existing auto-update setting, locks
  against concurrent connection changes, rejects dirty checkouts, and only
  fast-forwards `origin/main`. It uses the legacy Sync result row and state
  record.
- [ ] HAWS/source repository updates, skills, agents, AI integrations, and the
  remaining Sync orchestration.

## Remaining priorities, after Priority 1 parity

- [ ] Native Sync of HAWS, sources, skills, agents and integrations.
- [ ] AI client configuration parity and ownership preservation.
- [ ] Shared CLI/MCP inventory, consumers, installation and safe removal.
- [ ] Read-only Doctor and exact confirmed Repair.
- [ ] Migration, rollback and Uninstall parity and recovery.

Verification must distinguish macOS execution, native CI and cross-compilation.
The original request remains open until all required lifecycle behavior is
implemented and verified; UI appearance approval does not imply acceptance.
