# HAWS Selected Improvements — Design Specification

**Status:** Draft for user review; not an implementation authorization  
**Scope:** Improve the current old-base HAWS experience without replacing its
existing safety model or copying another implementation wholesale.  
**Baseline:** Current old-base worktree, the architecture regression audit, and
the historical/clean-base comparison matrix.  
**Out of scope:** A rewrite of HAWS, a new full-screen TUI, a merge to `main`,
or changes to remote services.

## 1. Intent

HAWS already has the required core capabilities. This work keeps those
capabilities while recovering selected clarity and interaction qualities found
in the historical and clean-base references:

- Users can identify the product, current screen, available action, and result
  without reading implementation-oriented output.
- Skills represent what a user can actually select, rather than every
  `SKILL.md` file found inside a source checkout.
- Navigation is explicit and safe: Back returns; Exit leaves HAWS; Apply is the
  sole persistence boundary.
- Long-running operations visibly state that they have started, what they are
  doing, and whether they completed or failed.

## 2. Preserved current behavior

The following are existing strengths and remain the implementation baseline:

- `haws.bat` is a thin Windows launcher and delegates shared behavior to
  `haws.sh`.
- Settings remain draft-only until the final confirmed Apply/Install/Update
  step.
- Sync remains explicit, bounded, per-target, and protective of local changes.
- Status and Doctor remain read-only.
- Uninstall remains ownership-aware, preview-first, and protective of modified
  or unrelated files.
- No route performs automatic sync when HAWS exits.

## 3. Logical skill model

### 3.1 Canonical identity

Catalog processing must use this model:

```text
Source (repository or local custom source)
  -> Logical Skill (one selectable user-facing skill)
    -> AI Target (a Codex, Claude, Cursor, or other adapter projection)
```

A logical skill is scoped to its source. Adapter and vendor copies of the same
logical skill inside one source are deduplicated and filtered before the UI,
counts, state, or adapter projections consume them. Same-named skills from
different sources remain distinct.

Local custom skills participate as sources; catalog discovery must not be
limited to `.gitmodules` entries.

### 3.2 Presentation

- **Single Skills** lists individual standalone or custom logical skills.
  It supports multiple selections with Space and does not show a redundant
  aggregate count beside each individual skill.
- **Multi-Skill Packs** lists repository packs and shows `active / total` for
  each pack.
- Descriptions are extracted from canonical logical-skill metadata when
  available, and otherwise use a concise safe fallback.
- In the first-install draft, any aggregate is explicitly marked as the
  default draft rather than an installed result.

## 4. Interaction and information contract

### 4.1 Launch and window identity

- Launching `haws.bat` is inert: it may read local state only. It must not
  sync, run Doctor, write state, or use the network automatically.
- The launcher routes an uninstalled machine to Setup and an installed machine
  to Home.
- The terminal/tab title is `HAWS — Human-AI Working Standard`, not a generic
  shell path.

### 4.2 Screen structure

Every primary route uses a consistent hierarchy:

1. Product/screen heading.
2. A concise sentence explaining the screen's purpose or current status.
3. Relevant state or choices.
4. Context-appropriate controls, including their effect.

The existing cursor menu engine remains. It must reuse one screen surface:
menus must not stack duplicate frames, redraw unrelated content, or introduce
unnecessary flicker. Loading indicators appear only for genuinely slow work.

### 4.3 Navigation and safety

- **Back** returns to the parent route and retains the parent draft.
- **Exit** leaves HAWS. When an unapplied draft would be discarded, HAWS asks
  for confirmation before leaving.
- **Apply** is the only route that persists settings and must require explicit
  confirmation before its write/network phase.
- Enter chooses only the current context's safe default. It must not silently
  start Sync, Install/Update, Uninstall, another network action, or a write.
- `q`/`Q`, cancellation, EOF, and error returns must be context-specific and
  leave state truthfully reported rather than silently applying it.

## 5. Operations presentation

### 5.1 Status and Doctor

- Home `Status Details` invokes the actual detailed status mode.
- Status summary presents overall health, Skills `active / total`, Second
  Brain mode, Auto Update state, and Last Sync as separate facts. No sync is
  represented as `Never`; disabling Auto Update does not erase the last sync.
- Detail output groups AI Environments, Sources, and Skills.
- Doctor remains read-only and leads with a concise overall result before
  detailed findings and next actions.

### 5.2 Sync and Uninstall

- Sync retains its current bounded reporting and clearly separates updated,
  up-to-date, skipped, blocked, failed, and timeout results.
- Uninstall retains its preview/apply boundary and ownership checks. This work
  changes only presentation or navigation where necessary, not deletion logic.

## 6. Reference-selection boundaries

Use selectively:

- Historical line: logical-skill filtering, deduplication, classification, and
  description extraction.
- Current line: draft/Apply safety, bounded Sync, ownership-aware Uninstall,
  and thin launcher ownership.
- Clean-base: UX contracts, status-details routing, single-versus-pack display,
  and reusable module boundaries where they reduce coupling.

Do not port:

- Raw recursive cataloging of every `SKILL.md`.
- Auto-sync on exit.
- A duplicate Settings, Sync, or Doctor state machine.
- Business logic in `haws.bat`.
- A wholesale clean-base architecture replacement.

## 7. Acceptance criteria

The implementation is accepted only when automated checks demonstrate:

- Within a source, adapter/vendor copies do not inflate skill counts; the same
  name in distinct sources remains distinct; local custom sources appear.
- Settings, counts, state, and adapter links consume the same logical-skill
  model.
- Single Skills and Multi-Skill Packs show the correct classification and
  count semantics.
- Launch is inert and sets the HAWS title; installed/uninstalled routing is
  correct.
- Back, Exit, Apply, Enter, cancel, and EOF follow their respective safety
  rules, including no unintended write/network action.
- Status Details is observably more detailed than Status summary; Doctor,
  Sync, and Uninstall retain the protected behavior described above.
- Existing CLI, launcher, catalog, state, sync, status/doctor, uninstall, and
  Codex adapter regressions remain green.

Physical Windows Explorer launch, native cursor behavior, host link privilege,
and external authenticated remotes remain `[Unverified]` until manually
executed on a disposable fixture.

## 8. Implementation constraints

- Prefer targeted extraction of catalog/UI boundaries from `haws.sh` over a
  broad rewrite.
- Do not alter dirty user-owned files, skill submodules, or reference checkouts
  without a separately approved scope.
- Add regression tests before or alongside each behavior change; no placeholder
  adapter tests and no test suppression.
- No merge or push is implied by this specification.

## 9. Review decision

Approval of this draft authorizes writing a detailed implementation plan only.
It does not authorize production-code changes. Any requirement not stated here
remains outside the change scope until separately agreed.
