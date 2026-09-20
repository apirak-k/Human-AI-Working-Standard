# HAWS CLI UX Refinement — Task Plan

**Branch:** `feat/haws-cli-ux-refinement`
**Base:** `dev/standards-and-docs` @ `fa446aa`
**Head:** `0a5cbb0`
**File:** `E:/Human-AI-Working-Standard/haws.sh` (6297 lines, 253 KB)
**Date:** 2026-09-19

---

## Context

User reported UX issues with the HAWS interactive CLI settings menu. A plan was
brainstormed, approved, partially implemented, then paused mid-session when
additional bugs were discovered. This document is the handoff brief for the
next agent (Codex or otherwise) to continue.

---

## Original 4-Change Plan (approved by user)

| # | Change | Status |
|---|--------|--------|
| 1 | 1-step back navigation: every `q` = back 1 level | ✅ Done |
| 2 | Doctor AI Environments: show AI names, not check count | ✅ Done |
| 3 | 3-digit skill count alignment `%3d / %3d` everywhere | ✅ Done |
| 4 | Separate Custom Skills from Single Skills (3-category menu) | ✅ Done (but introduced new bugs — see below) |

---

## What Was Committed

### Commit `2f8038f` — main feature
- Extracted `_health_active_ai_names()` helper (shared by Doctor summary and findings)
- Doctor now shows: `[PASS] AI Environments - Claude, Gemini, Codex`
- Added `__custom__` and `__single__` sentinels to `_settings_skill_selector()`
- `settings_skills_page()` rewritten to show 3 categories:
  - Custom Skills → `__custom__` filter
  - Single Skills → `__single__` filter
  - Multi-Skill Packs → `while true` loop (proper 1-step back)
- All skill count formats changed to `%3d / %3d`
- Added `_skills_recalc_active_counts()` inner function called after each selector visit

### Commit `f730c1a` — reset fix (partial, incomplete)
- `settings_draft_reset()`: populate `HAWS_DRAFT_SKILLS` with all skill IDs from
  catalog immediately on reset, instead of leaving blank and re-loading from disk
- **Problem:** "all skill IDs" comes from `catalog_skills` which reflects the
  current `skills.disabled` on disk — so this fix does NOT yet clear the
  persisted disabled list. Apply still writes the old disabled state.

---

## Bugs Discovered After Implementation (DO NOT SHIP YET)

### Bug A — CHECKLIST_RESULTS key mismatch (Critical)

**File:** `haws.sh` line ~5129
**Symptom:** Opening a skill checklist, toggling items, saving — the saved result
does NOT match what the user ticked. Skills get incorrectly disabled or enabled.

**Root Cause:**
```bash
# Line 5129 (current broken code):
if [ "${CHECKLIST_RESULTS[${items[$i]%%|*}]:-0}" -eq 1 ]; then
```
`items[$i]%%|*` strips the description and active flag, leaving the **display
label** (which may have been truncated by `_interactive_truncate`). Meanwhile
`interactive_checklist` / `CHECKLIST_RESULTS` keys are set using the same
truncated label. BUT: when `display_counts > 1`, the label has ` [source]`
appended (line 5107), and when the label collides or is truncated differently
between build and lookup, the key mismatches → wrong save result.

**Fix:** Replace label-key lookup with index-based lookup. The `ids[]` array is
already parallel to `items[]`. Use it:
```bash
# Replace line 5129 lookup with index-based:
if [ "${CHECKLIST_RESULTS[$i]:-0}" -eq 1 ]; then
```
This requires `interactive_checklist` to use numeric keys (0, 1, 2...) instead
of label strings, OR pass IDs directly. See `interactive_menu` at line ~3038 —
it uses `INTERACTIVE_MENU_SELECTION` as an integer index. The checklist should
do the same. Verify how `CHECKLIST_RESULTS` is populated in `interactive_menu`
(mode: `checklist`) and update the writer and reader together.

---

### Bug B — Standalone multi-skill packs misclassified (Structural)

**File:** `haws.sh` lines ~5090, ~5225, ~5089
**Symptom:** `caveman` shows `1 / 20` active. `planning-with-files` shows `1 / 6`
active. These are Standalone skill bundles but HAWS classifies them as
Multi-Skill Packs.

**Root Cause:**
```bash
# Classification logic (unchanged from original):
if [[ "${source_path}" == skills/packs/* ]] || [ "${source_counts[${source_id}]:-0}" -gt 1 ]; then
    is_pack=1
fi
```
- `skills/packs/*` → true Pack (correct)
- `source_counts > 1` → "more than 1 skill in this source dir" → treated as Pack

`caveman` lives at `skills/standalone/caveman/skills/caveman/SKILL.md` and has
20 sub-skills (caveman-compress, caveman-discover, etc.) all under the same
source_id. `planning-with-files` has 6 sub-skills. Both get `is_pack=1` because
`source_counts > 1`.

These should be classified as **Standalone bundles** (shown under Single Skills
or their own expanded view), NOT as Multi-Skill Packs.

**Fix options (pick one):**
1. *(Simpler)* Classify packs by path only (`skills/packs/*`), not by skill
   count. Remove the `|| source_counts > 1` condition.
2. *(Accurate)* Add a `standalone-bundle` concept distinct from pack: path
   matches `skills/standalone/*` with multiple skills → show as a single
   expandable entry under Single Skills, not as a Pack.

Verify with: how many legit packs rely on the `source_counts > 1` heuristic and
do NOT live under `skills/packs/`? If none → option 1 is safe and simple.

---

### Bug C — Reset to Default does not clear `skills.disabled` on disk (Partial Fix)

**File:** `haws.sh` lines ~5040–5058
**Symptom:** After "Reset to Defaults" + Apply, `skills.disabled` still contains
the old disabled list. Next load reloads the old disabled state.

**Root Cause:** `settings_draft_reset()` was patched to set `HAWS_DRAFT_SKILLS`
to all skill IDs in memory. But the Apply path (`settings_draft_apply()`) still
calls `save_disabled_skills()` which compares `HAWS_DRAFT_SKILLS` against the
catalog and writes the *difference* as disabled. This should work IF the draft
contains all IDs — but if `catalog_skills` returns fewer IDs than expected (due
to Bug B misclassification), some IDs are missing from the catalog output and
therefore the diff is wrong.

**Fix:** After Bug B is fixed, verify that `settings_draft_reset()` + Apply
correctly zeroes `skills.disabled`. If not, explicitly call
`save_disabled_skills` with `--all-enabled` or equivalent to force-clear the
file.

---

### Bug D — Copilot detected but never linked (Windows path missing)

**File:** `haws.sh` lines ~2431–2445, ~2631–2636
**Symptom:** Doctor and Settings show `GitHub Copilot` detected. Sync never links
it. User: "ไม่เอา Copilot" but default selects all detected AIs.

**Root Cause:**
- Detection (line ~2439) checks `AppData/Local/github-copilot` — found on user's
  Windows machine
- Sync Step 3 pointer linking (line ~2632) only checks `~/.copilot` and
  `~/.config/github-copilot` — misses Windows AppData path → skip → no link

**User intent:** Remove Copilot from the entire system OR add Windows AppData
path so detection and linking are consistent.

**Recommended:** Add `"${APPDATA}/github-copilot"` (or `LOCALAPPDATA`) to both
the detection check and the pointer linking block. Alternatively add a first-
class way to exclude an AI from auto-detection.

---

### Bug E — Step 4 (Sync) slow even when nothing changed, when Auto Update = ON

**File:** `haws.sh` lines ~2694–2710
**Symptom:** Step 4 always takes 2–5s even when no skills changed.

**Root Cause:**
```bash
if [ "${SYNC_SUMMARY_UPDATED:-0}" -eq 0 ] && [ -f "${MANIFEST_FILE}" ]; then
    if cmp -s ...; then
        can_fast_skip_skills=1
    fi
fi
```
`SYNC_SUMMARY_UPDATED` is set to 1 when global pointers were updated in Step 3.
When Auto Update is ON, Step 3 always refreshes global pointers (even if content
unchanged) → `SYNC_SUMMARY_UPDATED=1` → fast-skip never fires → all 129 junctions
re-created via `cmd.exe /c mklink` on Windows → slow.

**Fix:** Decouple the fast-skip check from `SYNC_SUMMARY_UPDATED`. Instead
compare the manifest skill section independently: if skill IDs haven't changed,
skip relinking regardless of what happened in Step 3.

---

## Work NOT Yet Started

| # | Description |
|---|-------------|
| 5 | Fix Bug A (checklist key mismatch) — critical, blocks correct open/close |
| 6 | Fix Bug B (standalone bundle misclassification) — caveman, planning-with-files |
| 7 | Fix Bug C (reset to default doesn't clear disk) — needs Bug B fixed first |
| 8 | Fix Bug D (Copilot Windows path) — user wants either fix or removal |
| 9 | Fix Bug E (Step 4 slow when Auto Update ON) — perf improvement |

---

## Architecture Notes for Next Agent

### Key Functions

| Function | Line | Role |
|----------|------|------|
| `_settings_skill_selector()` | ~5057 | Renders checklist for a skill group; contains Bug A |
| `settings_skills_page()` | ~5165 | 3-category menu + pack loop; Bug B affects counts here |
| `settings_draft_reset()` | ~5029 | Reset to defaults; Bug C |
| `_haws_detected_environments()` | ~4811 | Env detection; Bug D |
| `_catalog_skill_sources()` | ~1408 | Source catalog; is_pack classification; Bug B root |
| `interactive_menu()` | ~3038 | Shared TUI engine; checklist mode uses `CHECKLIST_RESULTS` |
| `save_disabled_skills()` | ~1344 | Writes `skills.disabled` to disk |
| `catalog_skills()` | scans fs | Returns TSV: source_id, id, display, description, entrypoint, active |

### Classification Pattern (current, used everywhere):
```bash
if [[ "${source_path}" != skills/custom* ]]; then
    if [[ "${source_path}" == skills/packs/* ]] || [ "${source_counts[...]:-0}" -gt 1 ]; then
        is_pack=1
    fi
fi
```
This pattern appears at lines: **5090**, **5225**, **5089** (in selector) and
equivalents in `_skills_recalc_active_counts`. Any fix to classification must
update ALL occurrences consistently.

### CHECKLIST_RESULTS structure (current):
`interactive_menu checklist` mode sets `CHECKLIST_RESULTS["<label>"]=0|1` where
`<label>` is the first pipe-delimited segment of the item string passed in.
The selector builds items as `"${label}|${detail}|${active}"` and looks them up
by `${items[$i]%%|*}`. As long as label is not truncated differently between
construction and lookup, it works — but truncation + source-suffix appending
can break it. Safest fix: add numeric index as a lookup key.

### Bash constraints:
- `set -euo pipefail` active throughout
- Associative arrays (`declare -A`) are local to function scopes
- Windows-only: symlinks via `cmd.exe /c mklink /J` (junction); requires elevation
- No external dependencies allowed

---

## Files Changed So Far (in branch `feat/haws-cli-ux-refinement`)

- `E:/Human-AI-Working-Standard/haws.sh` — only file modified

## Files NOT Changed (reference only)

- `E:/Human-AI-Working-Standard/haws.bat` — launcher, no changes needed
- `E:/Human-AI-Working-Standard/ai-configs/skills.disabled` — disk state, managed at runtime

---

## Verification Commands

```bash
# After any change:
bash -n haws.sh                          # syntax check — must exit 0
bash haws.sh doctor                      # human output — must show AI names
bash haws.sh doctor --json               # must output {"status":"Ready"}

# Manual interactive test:
bash haws.sh menu
# → Settings → Skills → verify 3 categories
# → Enter Custom Skills → toggle items → save → re-enter → verify counts match
# → Enter Multi-Skill Packs → pick a pack → q → verify back to pack list (not category)
# → Reset to Defaults → Apply → verify skills.disabled is empty
```

---

## Recommended Order of Fixes

1. **Bug B first** — fix classification so caveman/planning-with-files are not
   treated as packs. This unblocks correct counts everywhere.
2. **Bug A** — fix checklist key lookup to index-based. Test open/close/save.
3. **Bug C** — verify reset+apply zeroes skills.disabled after B+A are fixed.
4. **Bug D** — either add Windows AppData path for Copilot or provide explicit
   exclude mechanism. User preference: exclude.
5. **Bug E** — decouple fast-skip from SYNC_SUMMARY_UPDATED.

---

## Implementation Phase: Confirmed Bug Fixes (2026-09-20)

**Scope:** Modify `haws.sh` only for product behavior. Preserve existing dirty
submodule revisions and unrelated planning artifacts. Do not run setup, sync,
brain, fetch, or push against a real environment.

### Commit boundaries

1. `chore: align skill sources with pack layout` — the user-accepted structure
   change, including only Gitlink paths, source registry, disabled IDs, and the
   current handoff reference.
2. `fix: classify skill packs by source path` plus the checklist/reset fixes —
   update the shared classification rule, make checklist save index-stable,
   then verify Reset + Apply persistence.
3. `fix: remove Copilot from environment discovery` — remove Copilot from the
   HAWS environment surface consistently.
4. `perf: decouple skill fast-skip from pointer refresh` — compare the skill
   manifest independently of pointer-refresh state.

### Test seams

- `bash -n haws.sh`
- `bash haws.sh doctor`
- `bash haws.sh doctor --json`
- Disposable catalog/selector fixtures for classification, checklist save,
  re-enter, and Reset + Apply persistence.
- Static/path fixtures for Copilot removal and the Step 4 fast-skip predicate.

### Explicit limits

- The numeric count mismatch was not reproduced; do not invent a new count
  model without a failing reproduction.
- Real Step 4 wall-clock and post-update state remain separate acceptance work;
  no real sync is run during this implementation phase.

---

## Investigation Addendum — one skill remains off after Toggle All + Q (2026-09-20)

**User report:** After opening all skills with the checklist's Toggle All action,
pressing `q` to go back, and returning to the selector, one skill sometimes
appears disabled. The exact skill ID and exact input sequence have not yet been
captured. This is an investigation item, not a confirmed new root cause.

**Current boundary:** Do not edit `haws.sh`, run real `setup`, `sync`, or
`brain`, mutate installed AI environments, or commit during this phase. The
only allowed writes are to the planning/evidence files. Preserve the user's
existing dirty state files and submodule revisions.

### Investigation questions

1. Is the observed result caused by Toggle All's state-dependent behavior?
   `Space` on the Toggle All row turns every row on when any row is off, but
   turns every row off when all rows are already on. Capture the pre-state and
   the exact key sequence rather than assuming that “เปิดหมด” always means the
   same operation.
2. Does `q` only navigate one level, or does the category/pack loop overwrite
   one draft entry while returning? Check category entry, checklist exit,
   pack-list exit, and top-level Settings exit separately.
3. Is the missing item already lost in `CHECKLIST_RESULTS`, in
   `HAWS_DRAFT_SKILLS`, or only when the disabled file/preview is regenerated?
4. Can the issue be reproduced on the final row, a long/truncated label, a
   duplicate display label, a standalone bundle, or a custom skill? The old
   label-key bug is fixed by an index contract, but the full navigation path
   still needs a real acceptance check.
5. Is an apparent Preview/Sync omission actually a stale manifest/link state
   after a save that was never applied, rather than a selector persistence bug?

### Ordered check plan

#### Check 0 — freeze and record baseline (read-only)

- Record branch, `git status --short`, `skills/skills.disabled`, disabled
  environments, and the current catalog rows.
- Do not normalize or reset the user's files. Treat current dirty state as
  test input and record it before any fixture.

#### Check 1 — deterministic Toggle All/Q matrix

Use a disposable two- or three-row catalog/selector fixture and then one small
real source fixture. Execute the checklist in a shell context that preserves
the arrays (process substitution, not a pipeline subshell). Record exact
before/after values for each row:

| Case | Initial rows | Action | Expected invariant |
|---|---|---|---|
| A | all off | Toggle All once, `q`, re-enter | every row on; no row disappears |
| B | one row off | Toggle All once, `q`, re-enter | every row on; the previously off row is included |
| C | all on | Toggle All once, `q`, re-enter | every row off; this is the documented inverse behavior |
| D | mixed, toggle last row directly | `q`, re-enter | only the intended last-row state changes |
| E | custom/standalone/pack category | enter, save/back, return | category membership and states remain stable |

For every case capture the row index, stable skill ID, display label, and
active state. If one row fails, preserve the smallest failing input and name
the exact missing ID.

#### Check 2 — trace the persistence layers

For the smallest failing case, compare the same selection at each boundary:

1. `interactive_checklist` numeric result array;
2. `CHECKLIST_RESULTS` consumer in `_settings_skill_selector`;
3. `HAWS_DRAFT_SKILLS` after returning with `q`;
4. `skills/skills.disabled` after the explicit Settings Apply flow;
5. `catalog_skills` active flags and Preview category counts;
6. manifest and target links only as a post-state observation, without running
   real sync in this phase.

The first boundary where the expected ID changes is the root-cause location.

#### Check 3 — full safe UI flow

After the focused fixture, test the real flow without setup/sync:

`Settings → Skills → category → Toggle All/individual toggle → Confirm & Save
→ q/back → re-enter → top-level Apply → Preview → Apply`.

Use a disposable backup/fixture for the managed disabled file, restore the
user's original state after the check, and verify that restoration. If the
flow cannot be run safely without touching the user's installation, stop at
the fixture and mark the real flow unverified instead of claiming success.

#### Check 4 — related count/preview/environment checks

Only after the toggle path is understood, compare:

- selector active/total counts versus Preview active/total counts;
- Custom, Single, and Multi-Skill Pack membership;
- disabled-environment ownership cleanup (especially stale Claude links);
- uninstall wording (`Skill Links`, not a unique skill or AI count);
- Auto prune location (Sync behavior, not Uninstall behavior);
- Step 4 timing and post-update state as a separate authorized test.

Do not use a count mismatch as the explanation for the one-row symptom until a
failing count reproduction identifies the same skill ID.

### Exit criteria for this phase

- The exact key sequence and exact skill ID are either reproduced or recorded
  as not reproducible.
- Every persistence boundary above has an observed value for the smallest
  failing case.
- A proposed code change names the first failing boundary and includes a
  focused regression test before any implementation begins.
- No product code was changed and no real sync/setup/brain was run.

The next phase after this investigation is a separate implementation plan
based on evidence; do not silently expand this plan into a code fix.

### Newly confirmed root cause — missing list delimiter when enabling a skill

The first focused reproduction found a second persistence defect after the
index-based checklist fix. `_settings_ensure_skill_draft()` builds
`HAWS_DRAFT_SKILLS` with command substitution, so the final newline is removed.
When `_settings_skill_selector()` enables an ID that is not already selected,
line ~5110 appends the ID directly to `selected`:

```bash
selected="${selected}${ids[$i]}"$'\n'
```

If `selected` is non-empty and has no trailing newline, the new ID is fused to
the previous ID. `_settings_list_contains()` then cannot find the new ID, so
the skill remains OFF even though the checklist result was ON. This matches the
reported “เปิดแล้วมี 1 สกิลไม่เปิด” symptom.

**Red evidence (2026-09-20):** With three real rows from the
`skills/packs/superpowers` source, the first row started OFF. Toggle All +
Confirm produced `RED_EXPECTED_FIRST_ON_ACTUAL=OFF` and a raw draft containing
`...dispatching-parallel-agents` immediately followed by the first skill ID.

**Minimal implementation direction:** preserve newline-delimited list
invariants when appending an enabled skill, then rerun the same red fixture as
green. Do not broaden this fix into a new count model or UI redesign.

**Implementation completed in `f53b435`:** The append path now inserts a
newline before a new ID whenever the existing selection is non-empty. The red
fixture is green, and a disposable Apply fixture writes only the disabled-file
header when all rows are active. The user's real disabled file was not used for
the Apply check.

**Full-catalog regression completed:** A real Settings-page fixture re-enabled
one disabled Pack skill through category → Pack → Toggle All → Confirm → `q`
navigation. The draft returned to the all-active `153`-skill signature, and the
category/Preview totals remained consistent (`Custom 1/1`, `Single 4/4`, Packs
`148/148`).

### Newly confirmed root cause — Doctor adds the parse check to the skill count

Doctor's internal counters are correct (`HAWS_HEALTH_SKILLS_ACTIVE=153`,
`HAWS_HEALTH_SKILLS_TOTAL=153`), but `_health_print_findings()` counts every
`Skills` finding. That section includes one non-skill finding,
`skills.disabled parsed successfully`, plus one finding per active skill. The
summary therefore prints `154 active skill check(s) passed`.

**Red evidence (2026-09-20):** the same run reported
`SKILLS_FINDINGS=154` while both health counters were `153`; human Doctor
printed 154. The display must use the health active counter, not the section's
total finding count.

**Minimal implementation direction:** change only the successful Skills summary
to use `HAWS_HEALTH_SKILLS_ACTIVE`, then verify human Doctor reports 153 while
JSON status remains Ready.

**Implementation completed in `e195bb2`:** Doctor now reports the active
counter (`153`) instead of counting the parse-health row (`154`). Deep human
Doctor and JSON verification both pass.

### Newly confirmed UX issue — Uninstall label counts links, not unique skills

`uninstall_preview()` counts ownership records in the internal `skills` group.
On the current installation the dry-run reports `426` such records, while
those records represent managed links/targets across environments, not 426
unique skill definitions or AI environments. The user-facing label `Skills`
is therefore misleading.

**Minimal implementation direction:** change only the displayed group label to
`Skill Links`. Keep Auto prune in Sync; Uninstall and Sync have different
ownership/cleanup semantics.

**Implementation completed in `78901fc`:** Uninstall dry-run now displays
`Skill Links : 426 items`; no removal behavior changed and no real uninstall
was run.

### Newly confirmed bug — disabled environment links survive Sync fast-skip

The skill manifest is environment-agnostic. If Claude is disabled while the
active skill manifest remains unchanged, Step 4 can fast-skip because the
manifest still matches. The old HAWS-owned Claude skill links are not present
in the new manifest diff, so the existing obsolete-entry prune loop never sees
them.

**Red evidence (2026-09-20):** a disposable two-run fixture created one Claude
skill link and a one-skill manifest with Claude enabled. The second run disabled
Claude, reported no Claude detection and one `manifest unchanged` fast-skip,
but the old link remained present. Both runs used a temporary HOME/state and
Auto Update Off; the user's installation was not touched.

**Implementation direction:** before the Step 4 fast-skip decision, enumerate
only HAWS-owned skill-link records under disabled environment roots and remove
those records safely. Do not remove user-owned or modified paths. Keep the
manifest format unchanged and test Claude-disabled fast-skip plus an enabled
environment regression.
