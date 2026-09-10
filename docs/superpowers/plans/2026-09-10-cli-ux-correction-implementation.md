# HAWS CLI UX Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the HAWS terminal UI redraw correctly, expose truthful loading,
and configure multi-skill packs through an unambiguous draft-only hierarchy.

**Architecture:** Keep catalog and persisted settings as system-of-record.
`runtime/ui.sh` owns terminal redraw and key input. `runtime/settings.sh`
derives category and pack records from the catalog and owns draft navigation.
Existing fixture tests drive all behavior; no new dependency is introduced.

**Tech Stack:** Bash, ANSI terminal control compatible with Git Bash, fixture
HOME tests in `tests/cli/`.

**Spec:** `docs/superpowers/specs/2026-09-10-cli-ux-correction-design.md`

## Global Constraints

- Preserve draft-before-Apply; no checklist confirmation writes persistent state.
- Use the catalog as the only source of skill and pack membership.
- Status and Doctor remain local and read-only; do not invoke Sync.
- Do not introduce a `.bat`, launcher, Go binary, adapter, or dependency.
- Test only fixture HOME/repositories; do not modify the user's real HAWS home.
- Preserve unrelated dirty-worktree files and stage only UX-owned changes.

---

### Task 1: Repair cursor-menu rendering and loading feedback

**Files:**
- Modify: `runtime/ui.sh`
- Modify: `tests/cli/settings_test.sh`

**Interfaces:**
- `ui_cursor_menu TITLE ITEM...` redraws one menu surface and leaves
  `UI_MENU_RESULT` as the selected stable ID.
- A small UI status helper renders and clears a transient loading message.

- [ ] **Step 1: Add failing tests for one menu surface and a loading message.**

  Assert fixture output records the menu title and rows once per rendered
  surface, and that skill-catalog loading emits an explicit loading label
  before its result.

- [ ] **Step 2: Run the focused failure check.**

  Run: `bash tests/cli/settings_test.sh`

  Expected: failure because arrow navigation currently appends menu blocks and
  catalog loading has no visible phase.

- [ ] **Step 3: Implement ANSI redraw and transient-status helpers in `runtime/ui.sh`.**

  Track the number of rows rendered by `ui_cursor_menu`; on subsequent keys,
  move the cursor to the start of the prior surface, clear its lines, and
  redraw title, rows, and controls. Keep `HAWS_TEST_KEYS` deterministic and
  avoid ANSI control sequences in its captured output. Add helpers that print
  a loading line and clear it once the catalog is ready.

- [ ] **Step 4: Run focused tests.**

  Run: `bash tests/cli/settings_test.sh`

  Expected: exit 0.

### Task 2: Implement the three-level Skills draft flow

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `tests/cli/settings_test.sh`
- Modify: `tests/cli/first_install_test.sh`

**Interfaces:**
- A catalog grouping helper returns single-skill rows, pack rows, aggregate
  counts, and pack-local skill rows using stable catalog IDs.
- `skills_menu` produces the category page; `multi_skill_packs_menu` produces
  the pack picker; a pack checklist updates `HAWS_SELECTED_SKILLS` in memory.

- [ ] **Step 1: Add failing category, aggregate, and pack-boundary tests.**

  Assert the Skills page has only Single Skills, Multi-Skill Packs, and Back;
  assert both aggregate counts; assert pack names are absent from that page;
  assert the pack picker contains each pack once; assert selecting one pack
  exposes only its skills.

- [ ] **Step 2: Run the focused failure check.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: failure because Multi-Skill Packs currently opens one combined
  multi-source checklist.

- [ ] **Step 3: Derive category and pack records from the catalog.**

  Replace the `skills-pack` combined-list branch with catalog grouping by
  provenance/source. Count a source with one skill as Single; count all skills
  in sources with more than one skill as Multi. Build Multi's active/total
  count by summing its packs, and build each pack row from that pack only.

- [ ] **Step 4: Implement category, pack-picker, and pack-local checklist navigation.**

  Make `skills_menu` display aggregate details for both categories. Selecting
  Multi enters `multi_skill_packs_menu`; selecting a pack invokes
  `ui_checklist` with only that pack's records. Enter updates only
  `HAWS_SELECTED_SKILLS`; Back exits without writing. Redraw parent counts
  from the current draft after every confirmed checklist.

- [ ] **Step 5: Run focused tests.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh && bash tests/cli/state_test.sh`

  Expected: exit 0, with no persistent change before Preview and Apply.

### Task 3: Correct review actions and the Apply-to-Home path

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `runtime/operations.sh`
- Modify: `tests/cli/settings_test.sh`
- Modify: `tests/cli/first_install_test.sh`

**Interfaces:**
- Review emits explicit Apply, Back to Settings, and Cancel outcomes.
- `settings_apply` calls `home_run` when Home is selected after successful Apply.
- `home_run` renders one cursor menu only.

- [ ] **Step 1: Add failing tests for Back, Cancel, Home, and a single Home menu.**

  Assert Review Back returns to Settings with selected draft skills retained;
  assert Cancel removes the draft; assert successful Apply plus Home enters the
  Home cursor menu; assert Home rows are not printed before that cursor menu.

- [ ] **Step 2: Run the focused failure check.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

  Expected: failure because the current review accepts yes/no semantics, Apply
  only prints Home, and Home has duplicate presentation paths.

- [ ] **Step 3: Implement explicit review actions and Home transition.**

  Use `ui_cursor_menu` for Apply, Back to Settings, and Cancel. Preserve the
  draft on Back, discard it on Cancel, and route a successful Home choice to
  `home_run`. Remove any static Home-row printing that duplicates cursor rows.

- [ ] **Step 4: Run focused tests.**

  Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh && bash tests/cli/sync_test.sh`

  Expected: exit 0.

### Task 4: Regression and human acceptance evidence

**Files:**
- Modify only for a scoped defect found by the checks: `runtime/ui.sh`,
  `runtime/settings.sh`, `runtime/operations.sh`, and their CLI tests.

**Interfaces:**
- Produces test evidence; does not add behavior beyond the approved spec.

- [ ] **Step 1: Run syntax and fixture regressions.**

  Run: `bash -n haws.sh runtime/*.sh tests/cli/*.sh && bash tests/cli/run.sh`

  Expected: exit 0; record each suite count.

- [ ] **Step 2: Run adapter regression tests.**

  Run: `node --test ai-configs/codex/agents.test.mjs ai-configs/codex/skills.test.mjs`

  Expected: exit 0.

- [ ] **Step 3: Run whitespace and scope checks.**

  Run: `git diff --check && git status --short`

  Expected: no whitespace errors and no unrelated file staged.

- [ ] **Step 4: Perform the manual Windows Git Bash acceptance flow.**

  Run one process only: `bash haws.sh settings`. Verify visible loading,
  in-place arrow movement, category totals, pack picker, pack-local checklist,
  Preview/Back/Apply, and immediate Home. Record user acceptance separately
  from automated test results.

## Out of Scope

- Cross-platform entry command and launcher design.
- Any `.bat` restoration or replacement.
- Live installation, remote interaction, or Git push.
- The deferred Task 4–5 product work outside these UX corrections.
