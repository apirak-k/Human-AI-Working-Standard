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
memory until confirmation. The Go-hosted Sync now migrates HAWS root, registered
source repositories, and Second Brain targets natively while retaining the
legacy orchestrator for Claude/Gemini skill linking, agents, integrations, and
ordering. Codex active-skill links, Gitlink preparation, and stale-link pruning
now run in Go within the same Sync presentation.

## Priority 2 progress — Native Sync

- [x] HAWS root target: Go validates the current upstream and checkout, fetches
  through the existing candidate ref, preserves local custom skills and tracked
  Gitlink worktree drift, validates `haws.sh`, and fast-forwards the current
  branch only. Existing shell result recording and restart behavior remain.
- [x] Second Brain target: Go reads the existing auto-update setting, locks
  against concurrent connection changes, rejects dirty checkouts, and only
  fast-forwards `origin/main`. It uses the legacy Sync result row and state
  record.
- [x] Registered source repository targets: Go validates the registered
  checkout and candidate, blocks dirty sources, preserves local-ahead commits,
  and only checks out a candidate when an enabled skill changes or an eligible
  skill entrypoint changes. Go also prepares absent registered device sources
  with a staged clone under the source registry lock and validates the
  registered remote and a skill entrypoint before activation.
- [x] Gitlink source preparation: Go materializes tracked and package-pinned
  Gitlinks through staged checkouts, validates remote, pin, path, and skill
  entrypoint, and preserves unowned nonempty destinations.
- [x] Codex active and stale links: Go uses the native catalog and shared
  ownership ledgers, keeps source-qualified duplicate names, defers Ponytail to
  Codex plugins, removes only verified HAWS-owned links, and preserves foreign,
  edited, malformed, and symlink-parent destinations. Unix links use symlinks;
  Windows links use junctions.
- [ ] Remaining skill lifecycle: Claude symlinks and Gemini skills
  configuration.
- [ ] Agents, AI integrations, and the remaining Sync orchestration.

## Remaining priorities, after Priority 1 parity

- [ ] Finish native Sync parity for remaining skills, agents,
  integrations, and the remaining orchestration (HAWS root, registered sources,
  and Second Brain are now native targets).
- [ ] AI client configuration parity and ownership preservation.
- [ ] Shared CLI/MCP inventory, consumers, installation and safe removal.
- [ ] Read-only Doctor and exact confirmed Repair.
- [ ] Migration, rollback and Uninstall parity and recovery.

Verification must distinguish macOS execution, native CI and cross-compilation.
The original request remains open until all required lifecycle behavior is
implemented and verified; UI appearance approval does not imply acceptance.
