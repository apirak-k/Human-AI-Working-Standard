# HAWS old-base recovery: selected improvements

Date: 2026-09-12
Status: inspected selection proposal; implementation and manual acceptance pending.

## Purpose and confirmed direction

Build on the old Windows terminal experience. Select useful current capabilities,
requirements, code, and tests individually. The current implementation remains a
reference. A feature's presence in code is not evidence that it works correctly.

The old implementation method is part of the selected baseline, not only its
visible output. New screens must reuse or minimally refactor the old input,
cursor, redraw, and rendering engine. A visually similar replacement that clears
and redraws the whole screen, scrolls output quickly, or introduces a parallel
raw-key loop does not satisfy this direction.

### UX contract and additive changes

The old checkout is the UX contract. Existing screens keep their menu names,
wording, item order, navigation destinations, key behavior, cursor behavior,
redraw behavior, return behavior, and progress presentation unless this spec
explicitly changes one of them. Do not redesign or restate an old screen from
the current implementation.

This spec defines only additions or explicit changes to that contract. For each
selected improvement, inspect the old screen it extends and add the smallest
new item or state using the nearest old pattern. The implementation worker must
not invent labels, destinations, screens, or interaction rules from the current
renderer. If an addition has no unambiguous old placement or this spec does not
name its flow, record it as a pending UX decision before implementation.

Selected additions currently mapped to the old UX are:

- `haws.bat` consolidates entry navigation while preserving the old Windows
  launch and terminal behavior.
- First use opens `Setup`; completed installations open `Home`.
- `Home` adds explicit `Sync` and routes existing Status, Doctor, and Uninstall
  capabilities without redesigning their established screens.
- Settings adds `Auto Update` as an On/Off setting. It controls remote update
  work during explicit Sync; it does not create background updating.
- Settings adds `Second Brain Remote` and per-device AI environment selection
  using the old checklist/toggle behavior.
- Existing repository and Single Skills/Multi-Skill Packs screens gain draft
  behavior and validation without changing their established organization.
- Settings changes use `Apply` to open `Preview Install` or `Preview Update`.
  Preview offers the lifecycle actions specified below: `Install` or `Update`,
  `Back to Settings`, and `Cancel`.

Anything not listed as an addition or explicit change inherits old behavior.

Compare only these two filesystem states, including current uncommitted changes:

- Old: `E:/Human-AI-Working-Standard/.worktrees/codex-haws-bootstrap`,
  branch `codex/haws-bootstrap`, previously inspected HEAD `7179722`.
- Current: `E:/Human-AI-Working-Standard`, branch `recovery/clean-base`,
  refreshed HEAD `b8752cf`, with existing uncommitted work.

This is a capability selection, not a commit-history audit. Windows uses a BAT
entrypoint; macOS/Linux may use a shell entrypoint. One identical launcher file
for every OS is not a requirement. Preserve both reference checkouts while
building and validating a replacement in a separate checkout.

## What the old version already provides

Old paths below are relative to the old checkout; current paths are relative to
the current checkout. Line numbers describe the inspected snapshot.

| Existing capability | Old evidence | Selection |
| --- | --- | --- |
| Double-click BAT, visible terminal output | `SETUP.bat:41`, `1-CLICK-SYNC.bat:53` | Keep the launch and readable output experience; consolidate entry navigation. |
| Arrow/Space/Enter checklist | `haws.sh:1130`, raw input at `haws.sh:1207` | Reuse or minimally refactor this engine. Preserve cursor hiding/restoration, relative in-place redraw, raw-key handling, and row rendering. Do not build a parallel menu renderer. |
| Single Skills and Multi-Skill Packs | `haws.sh:1524`, `haws.sh:1616` | Already present; preserve rather than count as a new feature. |
| Repository add, classification, multi-select removal | `haws.sh:1267`, `haws.sh:1313`, `haws.sh:1366` | Preserve useful UX; add draft and validation safeguards. |
| Skill enable/disable persistence | `haws.sh:522`, `haws.sh:534` | Preserve selections; adapt storage only where needed. |
| Status, Doctor, uninstall dry-run, manifest | `haws.sh:20`, `haws.sh:128`, `haws.sh:2235` | Existing features; assess newer safety improvements individually. |
| Second Brain connection and synchronization | `haws.sh:1853`, `haws.sh:2041` | Preserve intended capability; integrate the new explicit settings controls. |

The old UX has user-provided working examples. Its entire backend has not been
certified safe or complete by this inspection.

## Selected improvements from the current version

Every row is a reuse recommendation. Runtime correctness remains [Unverified]
in this selection pass; no installation, sync, or deletion was executed.

| Improvement | User value | Current reference | How to reuse |
| --- | --- | --- | --- |
| One Windows BAT entry | Open one file and choose the job | `haws.bat`; `haws.sh:2995`; `runtime/settings.sh:716` | Adapt old launcher mechanics to one menu. Keep lifecycle decisions in Bash. |
| Setup on first install, Home afterward | Clear starting point and explicit Sync | `runtime/settings.sh:4`; `haws.sh:2995`; `spec.md` sections 15-17 | Keep the behavior, but implement every new screen through the shared old interaction engine. |
| Draft, Apply, Preview, Install/Update, Back/Cancel | Review changes before applying them | `runtime/settings.sh:582`, `runtime/settings.sh:629`; `spec.md` sections 15-16 | Keep requirements; adapt small pieces only after testing real state changes and failure paths. |
| Auto Update On/Off | Control remote updates during explicit Sync | `runtime/state.sh:40`; `runtime/settings.sh:568`; `runtime/operations.sh:111` | Reuse setting storage/toggle candidates; repair update execution before reuse. It is not a background scheduler. |
| Second Brain Remote setting in the same menu | Configure remote participation without a separate BAT | `runtime/settings.sh:337`; `runtime/state.sh:76`; `spec.md` section 11 | Retain toggle, URL review, and deferred persistence; retain actual synchronization capability. |
| Per-device AI environment selection | Link only selected AI environments | `haws.sh:618`; `runtime/state.sh:98`; `runtime/settings.sh:650` | Adapt environment selection and preserve existing local choices. |
| Repository draft edits and URL validation | Review additions/removals before changing disk | `runtime/settings.sh:181`, `runtime/settings.sh:257`; `runtime/integrations.sh:47` | Keep the improved behavior; validate application and dirty-repository protection separately. |
| Source-aware skill catalog and lazy loading | Distinguish duplicate skill names and avoid unnecessary scans | `runtime/catalog.sh`; `runtime/settings.sh:61`; `tests/cli/catalog_test.sh:74` | Candidate helpers to reuse with the existing Single/Pack UI; verify destination-name collisions too. |
| Local settings, complete-file replacement, compatibility readers | Keep preferences across launches and preserve older selections | `runtime/state.sh:18`, `runtime/state.sh:52`; `runtime/platform.sh:36` | Reuse small helpers after focused tests; file replacement does not make a multi-step install transactional. |
| Sync lock, local-change checks, candidate validation, per-target results | Protect local work and explain each update result | `runtime/state.sh:171`; `runtime/operations.sh:33`, `runtime/operations.sh:56` | Keep safeguards as requirements; repair gaps before carrying over implementation. |
| Read-only diagnostic separation | Inspect without silently repairing or syncing | `runtime/health.sh:115`, `runtime/health.sh:149` | Retain intent and useful checks; measure on real repository data. |
| Ownership-aware uninstall | Preserve modified or unrelated user files | `runtime/state.sh:154`; `runtime/operations.sh:214` | Reuse the ownership concept and suitable tests; verify migration and actual Windows link types. |
| Adapter improvements | Preserve newer integration fixes independently of TUI | `ai-configs/codex/skills.mjs`; `ai-configs/*/*.template` | Select individual changes with their adapter tests; do not revert project standards wholesale. |
| Behavior tests and product specification | Preserve lessons and prevent regressions | `tests/cli/`; `tests/windows_launcher_execution.test.mjs`; `spec.md` | Retain tests that assert desired outcomes; adapt tests tied to the rejected renderer or launcher mechanism. |

## Code evidence that changes the reuse decision

These are static findings, not claims from executing the workflows:

1. **Remote update reporting needs repair.** `runtime/operations.sh:91` and the
   HAWS branch at line 120 fetch and report `Up to date` without applying a remote
   revision or proving HEAD equals the remote. Preserve toggles, not this success
   claim. The current Second Brain path is not a complete replacement for the
   old synchronization flow.
2. **Timeout labels are not timeout enforcement.** Fetch calls at
   `runtime/operations.sh:49`, `:99`, and `:121` have no explicit deadline in
   those functions. Carry over bounded-wait requirements, not a claim of complete
   offline/timeout handling.
3. **Candidate validation can fall back to old content.** At
   `runtime/operations.sh:66`, a missing candidate entrypoint falls back to the
   current local file. Repair this before trusting it to reject broken updates.
4. **Apply is not an all-or-nothing transaction.** `runtime/settings.sh:653`
   saves settings before integration application at line 682. A later failure can
   leave partial changes. Preserve preview semantics and design honest recovery.
5. **Repository-only plans need an execution check.** The apply guard at
   `runtime/settings.sh:680` matches initialize/pointer/skill-link but excludes
   add-source/remove-source. A plan containing only repository operations can be
   skipped. Test actual disk outcomes, not merely plan text.
6. **Repository removal is not proven safe.** `runtime/integrations.sh:143`
   uses forced submodule removal and suppresses errors. Ownership checks for
   linked files do not establish protection of local edits inside the repository.
7. **Health output must reflect executed checks.** `runtime/settings.sh:693`
   prints `Doctor: Ready (read-only)` without calling Doctor there. The Home
   summary also prints a fixed Ready label. Reuse meaningful status reporting,
   not these unconditional health claims.

## How to use spec and tests

Use product requirements in `spec.md` as input, reviewed against the user's
latest direction. Keep selected settings, preview, explicit execution, ownership,
and responsive terminal requirements. Replace the recovery-base assumptions and
Task 1-7 execution instructions with a plan for the old base. Treat previous
Done/Accepted text as historical documentation, not current user acceptance.

Keep existing behavior-test ideas for disabled targets, preserved local choices,
draft cancellation, dirty repositories, ownership, and lock handling. Adapt
fixtures to the chosen implementation. Tests asserting strings such as Ready or
specific launcher source text cannot establish real execution or terminal UX.

Apply Ponytail before adding code or files: first reuse the old function, then
refactor the shared boundary only when more than one screen needs it. Do not add
a second renderer, input loop, abstraction, dependency, or runtime module when a
small change to the old `haws.sh` path covers the selected behavior. Tests must
detect method drift as well as output drift: no full-screen clear during row
movement, cursor hidden during interaction and restored on every exit, and all
menu/checklist callers routed through one shared input/redraw engine.

## Proposed implementation order

1. Establish an isolated old-base checkout and a runnable Windows reference.
   Confirm visible menus, keyboard interaction, cursor behavior, and relative
   in-place redraw before adding flow.
2. Adapt the useful local-state helpers and environment/toggle selections into
   the old menus. Preserve existing device choices.
3. Add unified entry, Setup/Home, and draft/preview/final confirmation. Exercise
   Back, Cancel, restart, no-change, and partial failure behavior.
4. Integrate repository and skill changes with actual filesystem assertions;
   preserve the old Single/Pack interaction and improve readable review output.
5. Integrate selected sync, diagnosis, and uninstall safeguards. Verify real
   outcomes in disposable repositories, including remote divergence and timeout.
6. Reuse relevant adapter fixes, update the product spec and operating docs, and
   complete user terminal acceptance. Retire superseded code only afterward.

This order is a design proposal, not a claim that migration has started. The next
implementation plan must name exact files and behavioral checks for each batch.
There is no requirement to preserve the current renderer, runtime directory
layout, historical task numbering, or identical launchers across operating systems.
The old interaction mechanism is required unless an observed platform defect
forces a minimal documented change to that same shared engine.

## Evidence and current handoff

- Inspected both versions' entrypoints, old feature functions, current state,
  operations, integration, settings/apply, diagnostic code, relevant spec sections,
  and existing test cases. No commit-history audit was needed.
- Created this selection document only. Existing edits and both code bases remain.
- Automated behavior tests were not rerun because no executable code changed.
- Actual migration, full-system correctness, and physical Windows acceptance are
  [Unverified]. The selected improvements above provide the input for that work.
