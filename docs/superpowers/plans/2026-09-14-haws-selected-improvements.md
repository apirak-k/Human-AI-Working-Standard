# HAWS Selected Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore selected historical usability qualities in HAWS while keeping
the current draft/Apply, Sync, launcher, and Uninstall safety model.

**Architecture:** Make one source-scoped logical-skill resolver the canonical
input to Settings, disabled-skill state, and adapter linking. Keep the existing
cursor-menu and shell architecture, making targeted behavior changes at its
current boundaries rather than copying clean-base modules or rewriting
`haws.sh`.

**Tech Stack:** Bash, Git Bash on Windows, Node.js `node --test`, existing
shell regression harness.

**Spec:** `docs/superpowers/specs/2026-09-14-haws-selected-improvements-design.md`

## Global Constraints

- Keep `haws.bat` a thin launcher; shared business logic remains in `haws.sh`.
- Do not auto-sync on exit, use Enter for a network/write/destructive default,
  duplicate Settings/Sync/Doctor state machines, or recursively treat every
  `SKILL.md` as a distinct selectable skill.
- Treat every registered repository that contains `SKILL.md` as a HAWS skill
  source, even when that repository also ships plugin metadata, hooks,
  commands, references, templates, or other extensions. Keep those extensions
  inside the source repository under `skills/packs/` or `skills/standalone/`;
  do not create a separate Plugin catalog or move them into a root `plugins/`
  tree. Only `SKILL.md`/`skill.md` files become selectable skill rows.
- Retain draft-only Settings until confirmed Apply/Install/Update, bounded
  Sync, read-only Status/Doctor, and ownership-aware preview-first Uninstall.
- Do not modify dirty skill submodules, reference checkouts, or user-owned
  unrelated changes. Do not push or merge.
- Add a failing regression before each behavior change. Do not suppress tests
  or create placeholder adapter tests.
- Stop after every checkpoint and wait for explicit user review before starting
  the next checkpoint.

---

## Change map

| File | Responsibility in this work |
| --- | --- |
| `haws.sh` | Canonical catalog identity, Settings Skills projection, terminal title, menu routing, and operation presentation. |
| `haws.bat` | Windows-only title handoff while remaining a launcher with no HAWS business logic. |
| `tests/cli/repository_skill_test.sh` | Source/logical-skill identity and Settings draft persistence fixtures. |
| `tests/cli/settings_flow_test.sh` | Settings category copy, draft/back/cancel flow, and non-mutating behavior. |
| `tests/cli/launcher_menu_test.sh` | Cursor-menu controls, safe exit/EOF behavior, title/launch assertions that work under Bash. |
| `tests/cli/status_doctor_test.sh` | Status summary/details and Doctor read-only presentation. |
| `tests/windows_launcher_execution.test.mjs` | Real Windows launcher command, argument, title, and no-mutation behavior. |
| `spec.md`, `README.md`, `HANDOFF.md` | Updated only after all code/test checkpoints are green; record evidence and remaining physical acceptance. |

## Checkpoint 1 — Canonical logical-skill identity

**Review gate:** Confirm that the raw-catalog regression is fixed in fixtures
without changing the UI, Sync, or adapter behavior yet.

### Task 1: Define and test the logical-skill catalog boundary

**Files:**

- Modify: `haws.sh:1202-1224`, `haws.sh:2734-2763`, and every internal caller
  of `catalog_skills` identified by `rg -n 'catalog_skills' haws.sh`.
- Modify: `tests/cli/repository_skill_test.sh`.

**Interfaces:**

- Consumes: `catalog_sources`, `extract_skill_name`, `extract_skill_desc`, and
  `_catalog_is_disabled`.
- Produces: a stable tab-separated logical-skill record:
  `source_id<TAB>logical_id<TAB>display_name<TAB>description<TAB>entrypoint<TAB>active`.
  `logical_id` must be stable for the same source-scoped selectable skill.

- [ ] **Step 1: Add failing fixtures and tests.**

  Add source fixtures containing one canonical skill and adapter/vendor copies
  with the same name. Add a second source with that same name, and a local
  custom skill directory. Assert that the first source produces one logical
  skill, the second source produces a separate logical skill, and the custom
  source is present. Assert descriptions come from the canonical file.

- [ ] **Step 2: Run the focused RED test.**

  Run: `bash tests/cli/repository_skill_test.sh`

  Expected: FAIL because current `catalog_skills` walks every `SKILL.md` below
  only `.gitmodules` sources and emits the path as its identity.

- [ ] **Step 3: Implement the minimum resolver.**

  Replace the raw recursive row emission in `catalog_skills` with an internal
  resolver that:

  1. enumerates registered repositories plus the approved local custom source;
  2. inventories all `SKILL.md`/`skill.md` files for source classification,
     so a repository with multiple vendor-specific skill copies is still a
     PACK while a repository with one skill file is a SINGLE;
  3. applies the existing historical filters from `get_repo_skills` when
     producing selectable canonical skills, without treating plugin metadata,
     hooks, commands, references, or templates as skill rows;
  4. deduplicates by logical name only within one source;
  5. retains same names in different sources; and
  6. passes the canonical source-scoped identity to `_catalog_is_disabled`.

  The resolver must preserve extension files in their owning skill source.
  A `.codex-plugin/plugin.json` or hook manifest is metadata for that source,
  not a separate repository type and not a reason to remove the source from
  the skill catalog.

  Keep output parsing localized: migrate callers in this checkpoint rather
  than making them guess old/new column layouts.

- [ ] **Step 4: Run the focused GREEN test.**

  Run: `bash tests/cli/repository_skill_test.sh`

  Expected: exit code `0`; identity, filtering, custom-source, and existing
  repository/draft tests pass.

- [ ] **Step 5: Run boundary regressions.**

  Run: `bash tests/cli/catalog_test.sh && bash tests/cli/state_test.sh`

  Expected: exit code `0`; catalog state and TSV state handling remain green.

- [ ] **Step 6: Review and checkpoint commit.**

  Inspect `git diff --check` and `git diff -- haws.sh tests/cli/repository_skill_test.sh`.
  Stage only these logical-skill files with `git add -p`, then commit:
  `feat(catalog): resolve source-scoped logical skills`.
  Stop and present the test output and diff summary for user review.

## Checkpoint 2 — Settings and Skills presentation

**Review gate:** Confirm that Settings consumes the canonical model and that
Single Skills/Packs counts and descriptions are clear without persisting a
draft before Apply.

### Task 2: Project logical skills into the existing Settings draft

**Files:**

- Modify: `haws.sh:4245-4250`, `haws.sh:4380-4473`, `haws.sh:4475-4555`.
- Modify: `tests/cli/repository_skill_test.sh`, `tests/cli/settings_flow_test.sh`.

**Interfaces:**

- Consumes: the logical-skill records from Task 1 and `HAWS_DRAFT_SKILLS`.
- Produces: draft values keyed by source-scoped logical ID and UI rows split
  into individual Single Skills and per-source Multi-Skill Packs.

- [ ] **Step 1: Add failing Settings flow assertions.**

  Extend fixtures so one source contains filtered duplicate files and two
  logical skills, while a local custom source contains one individual skill.
  Assert: Single Skills has no redundant aggregate count; each pack prints
  `active / total`; descriptions are concise; opening, backing out, and
  cancelling without Apply does not create `skills.disabled`.

- [ ] **Step 2: Run the focused RED tests.**

  Run: `bash tests/cli/repository_skill_test.sh && bash tests/cli/settings_flow_test.sh`

  Expected: FAIL on raw-file-derived counts or current duplicated category
  presentation.

- [ ] **Step 3: Implement the Settings projection.**

  Update `_settings_ensure_skill_draft`, `_settings_skill_selector`, and
  `settings_skills_page` to consume the Task 1 record shape. Preserve the
  existing lazy-load behavior and use only source-scoped logical IDs in
  `HAWS_DRAFT_SKILLS`. Render Singles as selectable skill rows and Packs as
  source rows with `active / total`; retain Space multi-select and existing
  Back-to-Settings behavior.

- [ ] **Step 4: Run focused GREEN tests.**

  Run: `bash tests/cli/repository_skill_test.sh && bash tests/cli/settings_flow_test.sh`

  Expected: exit code `0`; no false discard prompt, no premature persistence,
  and the updated category/count copy appears exactly once.

- [ ] **Step 5: Run compatibility checks.**

  Run: `bash tests/cli/launcher_menu_test.sh && bash tests/cli/sync_test.sh`

  Expected: exit code `0`; keyboard selection and disabled-skill Sync behavior
  remain intact.

- [ ] **Step 6: Review and checkpoint commit.**

  Inspect `git diff --check` and stage only `haws.sh` and the two focused shell
  tests with `git add -p`. Commit:
  `feat(settings): present logical skills clearly`.
  Stop for user review.

## Checkpoint 3 — Launcher identity and safe navigation

**Review gate:** Confirm title, headings, controls, and Back/Exit/Enter rules
without changing Sync or Uninstall implementations.

### Task 3: Make launcher/window identity and menu controls explicit

**Files:**

- Modify: `haws.bat:1-45`, `haws.sh:2287-2532`, `haws.sh:4637-4710`,
  `haws.sh:5054-5164`, `haws.sh:5173-5214`.
- Modify: `tests/cli/launcher_menu_test.sh`, `tests/cli/settings_flow_test.sh`,
  `tests/windows_launcher_execution.test.mjs`.

**Interfaces:**

- Consumes: the existing `interactive_menu` return contract and
  `_settings_draft_is_dirty`.
- Produces: context-aware headings/controls and a terminal title handoff that
  does not add HAWS behavior to the batch launcher.

- [ ] **Step 1: Add failing behavior tests.**

  Add assertions that bare Windows launch delegates inertly and establishes
  the `HAWS — Human-AI Working Standard` title; Bash menu output contains
  screen heading, one-sentence purpose, and control hints. Add fixture traces
  proving Back retains a parent draft, Exit asks before discarding a dirty
  draft, and Enter on Home never dispatches Sync, Install/Update, or Uninstall
  without selecting that row.

- [ ] **Step 2: Run RED tests.**

  Run: `bash tests/cli/launcher_menu_test.sh && bash tests/cli/settings_flow_test.sh && node --test tests/windows_launcher_execution.test.mjs`

  Expected: at least the title/control assertions fail; Windows-only execution
  tests may skip host link capability and must report it as `[Unverified]`.

- [ ] **Step 3: Implement targeted menu/launcher changes.**

  Set the Windows console title before delegating, and set/refresh the terminal
  title from the shared engine for non-batch launches. Keep `.bat` limited to
  locating Bash, changing to the HAWS directory, setting launch metadata, and
  forwarding arguments. In `interactive_menu` and the Setup/Home/Settings
  callers, render the agreed heading/purpose/controls hierarchy once per
  surface; make Back return to its parent route and gate Exit with the existing
  dirty-draft confirmation. Do not change the selected-row dispatch model.

- [ ] **Step 4: Run GREEN tests.**

  Run: `bash tests/cli/launcher_menu_test.sh && bash tests/cli/settings_flow_test.sh && node --test tests/windows_launcher_execution.test.mjs`

  Expected: all executable tests pass; only privilege-dependent Windows link
  tests may skip with their existing `[Unverified]` label.

- [ ] **Step 5: Review and checkpoint commit.**

  Inspect `git diff --check`; stage only launcher/menu files and commit:
  `feat(ui): clarify HAWS navigation and window identity`.
  Stop for user review.

## Checkpoint 4 — Status Details and operation presentation

**Review gate:** Confirm Status Details is truly detailed and presentation
improves without weakening read-only Status/Doctor or bounded Sync/Uninstall.

### Task 4: Repair Home Status Details routing and concise health output

**Files:**

- Modify: `haws.sh:219-224`, health/status render functions preceding them,
  and `haws.sh:5136-5164`.
- Modify: `tests/cli/status_doctor_test.sh`, `tests/cli/launcher_menu_test.sh`.

**Interfaces:**

- Consumes: `status_run`, `doctor_run`, sync-state records, and existing
  health classifications.
- Produces: a summary view and an explicit `--details` view; neither mutates
  settings, ownership, repositories, or network state.

- [ ] **Step 1: Add failing route and presentation tests.**

  Drive Home to `Status Details` and assert the output contains the detailed
  AI Environments, Sources, and Skills sections. Add a summary assertion for
  overall health, Skills `active / total`, Second Brain, Auto Update, and Last
  Sync; use a fixture with no sync state to assert `Last sync: Never` while
  Auto Update remains independently visible. Keep file and git-state snapshots
  before/after Status and Doctor.

- [ ] **Step 2: Run RED tests.**

  Run: `bash tests/cli/status_doctor_test.sh && bash tests/cli/launcher_menu_test.sh`

  Expected: the Home route fails because it currently calls `run_status`
  without `--details`.

- [ ] **Step 3: Implement minimal routing and output changes.**

  Change only the Home Status Details dispatch to `run_status --details`.
  Arrange existing status/doctor fields so the concise classification appears
  before grouped detail; preserve existing measured labels and the read-only
  APIs. Do not call Sync, mutate state, or rewrite Doctor checks.

- [ ] **Step 4: Run GREEN and safety tests.**

  Run: `bash tests/cli/status_doctor_test.sh && bash tests/cli/launcher_menu_test.sh && bash tests/cli/sync_test.sh && bash tests/cli/uninstall_test.sh`

  Expected: exit code `0`; Status/Doctor remain non-mutating and Sync/Uninstall
  retain existing safety behavior.

- [ ] **Step 5: Review and checkpoint commit.**

  Inspect the focused diff, stage with `git add -p`, then commit:
  `fix(status): route Home details to detailed health output`.
  Stop for user review.

## Checkpoint 5 — Final regression, documentation, and physical acceptance

**Review gate:** Verify the integrated behavior, update only evidence-based
documentation, and clearly preserve remaining manual checks.

### Task 5: Run full verification and update continuity documents

**Files:**

- Modify: `spec.md`, `README.md`, `HANDOFF.md` only if actual results match
  the recorded commands.
- Modify: `.planning/2026-09-14-architecture-regression-audit/task_plan.md`,
  `progress.md`.
- Test: `tests/cli/run.sh`, `ai-configs/codex/agents.test.mjs`,
  `tests/windows_launcher_execution.test.mjs`.

**Interfaces:**

- Consumes: the completed checkpoint commits and their test output.
- Produces: an evidence-backed implementation contract and a checkpoint that
  distinguishes automated verification from physical Windows acceptance.

- [ ] **Step 1: Run the complete automated suite.**

  Run: `bash -n haws.sh && bash tests/cli/run.sh && node --test ai-configs/codex/agents.test.mjs tests/windows_launcher_execution.test.mjs && git diff --check`

  Expected: every runnable assertion passes. Any Windows link privilege skip
  remains explicitly `[Unverified]`; do not hide or convert it to pass.

- [ ] **Step 2: Inspect the integrated change set.**

  Run: `git status --short && git diff --stat && git diff --check`

  Expected: only intended HAWS files are changed; pre-existing dirty
  submodules/user-owned files remain unstaged and untouched.

- [ ] **Step 3: Update documentation from executed evidence only.**

  Update `spec.md`, `README.md`, and `HANDOFF.md` with actual test totals,
  commands, checkpoint commits, behavior changes, and the remaining physical
  Explorer/native-cursor/external-remote `[Unverified]` items. Mark the audit
  plan implementation phase complete only after the evidence is recorded.

- [ ] **Step 4: Commit documentation separately.**

  Stage only documentation and audit ledger files with `git add -p`, then
  commit: `docs(haws): record selected-improvements verification`.

- [ ] **Step 5: Manual acceptance checkpoint.**

  On a disposable Windows fixture, double-click `haws.bat`; traverse Setup,
  Settings, Skills, Back, Exit, Apply, Home, Sync, Status, Doctor, and
  Uninstall preview. Record observed title, cursor behavior, rejected routes,
  and external authenticated remote results. Do not run destructive Uninstall
  apply against real user data.

## Coverage review

| Spec requirement | Implemented by |
| --- | --- |
| Source-scoped logical skills, dedup/filter/custom discovery | Checkpoint 1 |
| Settings draft, Single/Packs, description/count semantics | Checkpoint 2 |
| Inert launch, title, headings, Back/Exit/Apply/Enter safety | Checkpoint 3 |
| Status Details, Status/Doctor presentation, operation safety | Checkpoint 4 |
| Existing regression preservation and physical `[Unverified]` acceptance | Checkpoint 5 |

## Execution order

Execute exactly one checkpoint, present its focused diff and green test output,
and wait for the user before continuing. If a checkpoint discovers that a
shared interface change affects a later checkpoint, update this plan and ask
for review before modifying that interface. Do not batch checkpoints together.
