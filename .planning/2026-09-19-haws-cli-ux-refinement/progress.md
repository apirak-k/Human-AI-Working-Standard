# progress.md — HAWS CLI UX Refinement

## Completed

- [x] Phase 1: Doctor AI names (`_health_active_ai_names` helper + findings update)
- [x] Phase 2: `__custom__` / `__single__` sentinels in `_settings_skill_selector`
- [x] Phase 3: 3-category menu in `settings_skills_page` + while-true pack loop
- [x] Phase 4: `%3d / %3d` format strings everywhere
- [x] Partial fix: `settings_draft_reset` sets HAWS_DRAFT_SKILLS from catalog

## Blocked / In-Progress

- [x] Bug A: Checklist key mismatch fixed with index-based results
- [x] Bug B: Pack classification now follows `skills/packs/*`
- [x] Bug C: Reset + Apply verified to clear `skills.disabled`
- [x] Bug D: Copilot removed from the `haws.sh` runtime surface
- [x] Bug E: Step 4 fast-skip decoupled from pointer refresh

## Commits on Branch

```
f730c1a fix(cli): ensure reset to default restores all skills as active defaults
2f8038f feat(cli): 1-step back nav, custom skills category, doctor AI names, 3-digit alignment
```

## Branch

`feat/haws-cli-ux-refinement` on top of `dev/standards-and-docs` @ fa446aa

## 2026-09-20 Implementation Handoff

- [x] User accepted the skill-source layout in the Dev checkout.
- [x] Moved the four pack Gitlinks into `skills/packs` without staging the
  pre-existing revision differences in `planning-with-files` and
  `ui-ux-pro-max`.
- [x] Commit the accepted structure as the first save point: `b81b383`.
- [ ] Fix Bug B, Bug A, and Bug C with focused red/green checks.
- [ ] Remove Copilot consistently from the HAWS environment surface.
- [ ] Decouple Step 4 fast-skip from pointer refresh state.
- [ ] Run the final safe verification set and review the staged diff.

### Red checks completed

- Bug A: synthetic duplicate-label selector failed as expected (`RESULT=`).
- Bug B: synthetic standalone multi-skill source failed as expected (`Single
  Skills 0/0`, `Multi-Skill Packs 3/3`).

### Bug B complete

- [x] Pack classification now uses `skills/packs/*` in selector, Settings
  category totals/recount, and Preview.
- [x] Green fixture reports `Single Skills 2/2` and `Multi-Skill Packs 1/1`.
- [x] `bash -n haws.sh` passes.

### Bug A complete

- [x] Checklist results are written and read by numeric index.
- [x] Skill, AI-environment, and repository-removal consumers use the same
  index contract.
- [x] Duplicate-label selector fixture passes with only the intended ID active.
- [x] AI-environment selection fixture passes with only the intended
  environment active.

### Bug C verified

- [x] Disposable Reset + Apply fixture leaves `skills.disabled` empty of skill
  IDs.
- [x] No additional `haws.sh` change or commit was needed for Bug C.

### Bug D complete

- [x] Copilot removed from the `haws.sh` runtime environment surface.
- [x] AppData-only Copilot fixture is ignored.
- [x] No Copilot reference remains in `haws.sh`; syntax passes.

### Bug E complete

- [x] Fast-skip no longer depends on `SYNC_SUMMARY_UPDATED`.
- [x] Unchanged-manifest fixture skips linking even when pointer refresh reports
  an update.
- [x] No real sync was run.

### Interactive acceptance evidence

- [x] Real selector save/re-enter path toggled an actual Pack row off and kept
  it off after re-entry.
- [x] No Apply was run; `skills.disabled` and user environment state were not
  changed by the interactive fixture.

### Current checkout note

The active Dev checkout is `E:/Human-AI-Working-Standard` on
`feat/haws-cli-ux-refinement`. Existing dirty submodule revisions and planning
directories predate this implementation and must remain separate from the
implementation commits.

### Errors encountered

- The first `git mv` attempt was denied while creating `.git/index.lock` by the
  sandbox; the lock did not exist. The same targeted command succeeded after
  the required filesystem approval, with no repository lock left behind.

## 2026-09-20 Investigation Plan — one-row Toggle All/Q report

- [x] Freeze current state without changing `haws.sh`: branch is
  `feat/haws-cli-ux-refinement`, HEAD is `0a5cbb0`, and existing user/submodule
  dirty state is preserved.
- [x] Record that `skills/skills.disabled` currently contains only its header;
  this means the current persisted catalog state is all-active, but does not
  prove the reported navigation sequence.
- [x] Confirm the Toggle All primitive is state-dependent: all-off/mixed plus
  `Space` turns all on, while all-on plus `Space` turns all off.
- [x] Confirm the existing real-source acceptance check is narrower than the
  latest report: it covers one row off → confirm → re-enter, not Toggle All +
  `q` + full Apply.
- [ ] Run the deterministic Toggle All/Q matrix with exact skill IDs and
  before/after states.
- [ ] Trace the first boundary at which the missing row changes state:
  checklist result → draft → disabled file → catalog/Preview → manifest.
- [ ] Recheck Custom, Single, Multi-Skill Pack, final-row, and long/duplicate
  label cases only after the smallest reproduction is captured.
- [ ] Write a separate evidence-backed implementation plan; do not modify
  product code or commit in this investigation phase.

### Root-cause evidence — first implementation slice

- [x] Baseline: `haws.sh` syntax passed; Doctor returned `Ready`; JSON returned
  `{"status":"Ready"}`; no product file was changed during baseline.
- [x] Corrected the disposable fixture's source ID after the first harness
  error (`path` was passed where the full `path::path` source ID was required).
- [x] Red reproduction: Toggle All + Confirm with one real row initially OFF
  left that row OFF and concatenated its ID to the previous draft entry.
- [x] Patch the newline-delimited draft append at the smallest responsible
  code location (`f53b435`).
- [x] Rerun the red fixture as green, then test individual toggle, Toggle All,
  `q` cancellation, re-entry, and Apply persistence in disposable fixtures.
- [x] Commit the focused product fix separately from the evidence/planning
  checkpoint.
- [ ] Run the remaining full-catalog and real UI acceptance checks before
  declaring the broader UX work complete.
- [x] Full-catalog Settings fixture re-enabled one real Pack skill after the
  delimiter fix; active count returned to `153/153` and the ID signature
  matched the all-active catalog.
- [x] Category totals are `Custom 1/1`, `Single 4/4`, and `Packs 148/148`.
- [x] Read-only Preview lists all four standalone skills and the custom skill;
  moved `caveman` and `planning-with-files` appear as Packs.

### Harness notes

- The first selector attempt passed `skills/packs/superpowers` instead of its
  full catalog source ID and correctly found no rows; this was a fixture error,
  not product evidence.
- The corrected fixture used the full source ID and reproduced the malformed
  newline-delimited draft without touching `skills.disabled`.
- The fixed fixture reports the first row ON after Toggle All + Confirm, and
  the disposable Apply fixture leaves no disabled IDs when all rows are active.

### Commits in this investigation slice

- `a1999f7 docs: record skill toggle root cause evidence`
- `f53b435 fix(cli): preserve skill draft item boundaries`

### Current safety boundary

No real `setup`, `sync`, or `brain` was run for this report. Do not stage or
reset the user's dirty `ai-configs/environments.disabled`, `skills/skills.disabled`,
or submodule revisions while reproducing the issue.
