# HAWS Old-Base Implementation Specification

**Status:** Current implementation contract for the old-base selected worktree  
**Implementation worktree:** `codex/old-base-selected-improvements`  
**Reference checkout:** `.worktrees/codex-haws-bootstrap`  
**Last automated verification:** 2026-09-15 on Windows PowerShell 7.6.5, Git Bash 5.3.15, Node.js v22.14.0, and Git 2.55.0.windows.2
**Current code checkpoint:** pending UX simplification commit (Health grouping and result navigation)
**Remote checkpoint:** `origin/codex/old-base-selected-improvements` remains at `95e9733`; no push performed
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
- `Q`/`q` is shown once in the footer: `Back` on child pages and `Exit` on
  Home/root pages.
- Cursor movement and redraw happen on the existing menu surface.
- Settings Single Skills and other checklists use the shared renderer; every
  redraw includes the same rows and footer height, so the cursor does not jump
  or overwrite the footer.
- No replacement full-screen renderer is introduced.
- Main-menu Skills category and pack selectors use the same shared cursor
  controls; numeric shortcuts remain accepted for compatibility.
- Selectable menu rows provide a short action description.
- Actions show a visible start/completion or failure result; catalog-backed
  routes show a loading/ready status before presenting their selector.

Primary routes:

```text
First launch -> HAWS Setup
Setup -> Use Default Setup -> Preview Install -> Install -> HAWS Home
Setup -> Customize Settings -> Apply -> Preview Install -> Install -> Home
Later launch -> HAWS Home
Home -> Sync | Health | Settings | Uninstall
Settings -> Apply -> Preview Install/Update -> Install/Update -> Home
Settings -> Skills -> Single Skills | Multi-Skill Packs -> Settings
Settings -> AI Environments -> detected-environment checklist -> Settings
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
- Explicit integration follows the bootstrap-style sequence: prepare local
  state, apply the requested draft at its existing boundary, link skills and
  profiles, configure the `commit-msg` hook, then show the result.
- Sync target rows show fixed `Target`, `Result`, and `Detail` columns with
  batch-style `[PASS]`, `[WARN]`, `[BLOCKED]`, and `[FAIL]` markers.
- Opening the launcher does not auto-sync or auto-run Doctor; hook setup is
  part of explicit integration/Sync only.
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
- Before the Skills draft is loaded, Settings displays `all active (default)`.
- Opening Skills loads the catalog with visible progress and leaves without a
  discard prompt when no edit was made.
- AI Environments opens an actionable enable/disable checklist for detected
  environments; changes remain draft-only until final Apply.
- Disabled source-aware skills are not linked by legacy sync consumers.
- Reference and implementation submodules remain separate from this contract.

## 5. Read-only health

Home presents a compact status summary immediately. Health is the single UI
page combining that summary with grouped Doctor findings for Settings,
AI Environments, Ownership, Sources, Skills, and Hooks. It is read-only.
The compatibility commands remain available:

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

Final automated verification executed on 2026-09-15 for implementation
checkpoint `1bb1f0b`:

- `bash -n haws.sh && bash tests/cli/run.sh && node --test
  ai-configs/codex/agents.test.mjs tests/windows_launcher_execution.test.mjs
  && git diff --check && cmd.exe /c haws.bat --help` under Git Bash exited 0.
- The CLI aggregate passed 110/110 assertions (17 + 14 + 27 + 6 + 10 + 17 +
  9 + 10). This includes the shared-checklist redraw, bootstrap-style phase,
  hook orchestration, and Sync result-marker tests.
- The Node aggregate passed 26 tests and skipped 1. The Codex adapter suite
  passed 14/14; the Windows file-symlink capability was skipped as
  `[Unverified]`.
- The target root has no production source changes. Five skill-pack submodules
  retain dirty worktrees; `agent-skills`, `anthropics-skills`, and `ponytail`
  also retain staged gitlink drift. These states were preserved.
- The selected-improvements history through the prior checkpoint includes
  `774cab1`, `0671a2d`, `9ab4499`, `500b59e`, `0d0f259`, `1c17b40`, `1aa832d`,
  and `95e9733`. Bootstrap-aligned orchestration is committed locally as
  `1bb1f0b`; the tracking remote remains at `95e9733`, and no push or merge was
  performed.
- `ai-configs/codex/skills.test.mjs` and `tests/cli/adapters_test.sh` are not
  present in either compared adapter tree; no placeholder tests were created.

These results are automated evidence, not physical Windows verification or
human acceptance. The five dirty skill submodules remain outside the checkpoint
commit, and standalone skill submodules remain uninitialized.

## 9. Remaining acceptance

- `[Unverified]` Launch `haws.bat` by double-clicking from Explorer.
- `[Unverified]` Exercise Setup, Settings, Preview, Back, Cancel, Install/Update,
  Home, Sync, Health, compatibility Status/Doctor, and Uninstall on a
  disposable Windows fixture.
- Record actual terminal cursor behavior and any rejected route.
- `[Unverified]` Test external authenticated remotes separately.
- Keep old-base, current, and reference checkouts until the user authorizes
  merge or retirement.

No merge or push is part of this specification.
Health presents one `[PASS]` marker without padding inside the brackets, groups
normal findings by section, and hides long filesystem paths from the default UI.
Full diagnostic details remain available through the compatibility CLI details
output. Result screens entered from Home return after one key; `Q` in child
menus returns to the parent without a duplicate Back row.
