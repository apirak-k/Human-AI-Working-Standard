# findings.md — HAWS CLI UX Refinement

## Classification Logic (Bug B Root)

ปัญหาหลักคือ `is_pack` classification ใช้ `source_counts > 1` ซึ่งทำให้
standalone bundles ที่มีหลาย sub-skills (caveman 20 sub, planning-with-files 6 sub)
ถูกจัดเป็น Multi-Skill Pack โดยผิดพลาด

Pattern นี้ซ้ำ 3 จุดใน haws.sh:
- line ~5090 (ใน `_settings_skill_selector`)
- line ~5225 (ใน `settings_skills_page` main count loop)
- ใน `_skills_recalc_active_counts` (ใหม่ที่เพิ่มไปในคอมมิตนี้)

## CHECKLIST_RESULTS Key Bug (Bug A Root)

`interactive_menu checklist` ตั้งค่า key เป็น label string
แต่ label อาจถูก truncate หรือมี ` [source]` ต่อท้าย ทำให้ key ไม่ตรง

Line 5129:
```bash
if [ "${CHECKLIST_RESULTS[${items[$i]%%|*}]:-0}" -eq 1 ]; then
```
ควรเปลี่ยนเป็น index-based หรือหา key ที่ stable กว่า

## Copilot Windows Path Gap (Bug D)

Detection: ตรวจ `AppData/Local/github-copilot` → เจอบน Windows
Sync Step 3: ตรวจแค่ `~/.copilot` และ `~/.config/github-copilot` → ไม่เจอ → skip

## Step 4 Fast-Skip Gate (Bug E)

`SYNC_SUMMARY_UPDATED` ถูก set เป็น 1 เมื่อ Step 3 update pointer
เมื่อ Auto Update ON → Step 3 เสมอ → `SYNC_SUMMARY_UPDATED=1` → fast-skip ไม่ทำงาน
→ mklink ทุก skill ใหม่ทุกครั้ง → ช้า 2-5 วินาที

## Implementation Red Checks (2026-09-20)

- Bug A red: a disposable two-row selector with identical display labels sent
  numeric checklist results `[0]=1, [1]=0`; the current label lookup produced
  an empty draft instead of selecting only the first ID.
- Bug B red: a disposable `skills/standalone/bundle` source with two skills was
  reported as `Single Skills 0/0` and `Multi-Skill Packs 3/3`; the expected
  source-path classification is `Single Skills 2/2` and `Multi-Skill Packs 1/1`.
- The first inline Bash fixture failed because Git Bash was launched without
  `/usr/bin:/bin` in `PATH`; the fixture was rerun with an explicit PATH and
  then produced the intended red result. No repository file was changed by the
  failed attempt.

## Bug B Green Check (2026-09-20)

- After making classification path-based in the selector, Settings category
  totals, active recount, and Preview, the same fixture reported `Single Skills
  2/2` and `Multi-Skill Packs 1/1`.
- `bash -n haws.sh` passed after the change.

## Bug A Green Check (2026-09-20)

- The duplicate-label selector fixture now preserves only the indexed first
  choice (`RAW=id-one`), with the second choice absent.
- The same index contract is now used by skill selection, AI-environment
  selection, and repository removal; no checklist consumer remains keyed by a
  rendered label.
- The first AI-environment assertion expected a newline-stripped value but
  compared it to the comma-rendered value; the raw result was then inspected
  and confirmed as `claude\n`. This was a fixture assertion error, not a
  product failure.
- `bash -n haws.sh` passed after the complete writer/reader update.

## Bug C Verification (2026-09-20)

- A disposable fixture started with a disabled skill, ran
  `settings_draft_reset` followed by `settings_apply_skill_draft`, and ended
  with only the header in `skills.disabled`.
- Bug C is already fixed by the existing reset implementation after the
  classification correction; no additional product-code commit was needed.

## Bug D Green Check (2026-09-20)

- Copilot was removed from the `haws.sh` environment catalog, label map,
  detection path, sync detection/pointer branch, and Doctor AI summary.
- A temporary HOME containing only `AppData/Local/github-copilot` produced no
  Copilot environment, and the runtime environment catalog is now
  `claude, gemini, cursor, codex`.
- `rg -i copilot haws.sh` returns no matches and `bash -n haws.sh` passes.
- Copilot templates and prose outside `haws.sh` were intentionally left alone
  because the active product-change scope is the single CLI file.

## Bug E Green Check (2026-09-20)

- A disposable `run_sync` fixture stubbed source sync and catalog discovery,
  set `SYNC_SUMMARY_UPDATED=1`, and supplied an unchanged skill manifest.
- Before the fix it did not print the manifest fast-skip message; after the fix
  it reported `All 0 active skill links verified and preserved (manifest
  unchanged)` and returned success.
- No real sync, setup, brain, remote, or user environment was touched.

## Interactive Save/Re-enter Check (2026-09-20)

- The real `interactive_checklist` and `_settings_skill_selector` were exercised
  with two rows from the actual `skills/packs/caveman` source. Input sequence
  `j`, Space, Enter, then `q` toggled the first row off, saved the draft, and
  re-entered the selector with the same row still off (`SAVE_RC=0`,
  `SAVE_STATE=OFF`, `REENTER_STATE=OFF`).
- The first full-catalog interactive fixture exceeded the wrapper window while
  scanning the 153-row catalog; the reduced real-source fixture avoided that
  harness limit without touching product state.

## Latest User Report: One Skill Remains Off After Toggle All + Q (2026-09-20)

This is not yet reproduced. The report is specifically different from the
already-passing two-row test: the user describes opening all skills, pressing
`q` to go back, and later finding one skill still off. The exact skill ID,
initial state, and whether `Confirm & Save` and top-level `Apply` were both
used are still unknown.

### Facts currently established

- `interactive_menu` treats the Toggle All row as a state-dependent toggle:
  when any row is off, `Space` turns all rows on; when all rows are on,
  `Space` turns all rows off. `Enter` confirms; `q` navigates back.
- A direct read-only checklist test proved both transitions (all on → all off
  and all off → all on), but did not prove the full category/back/re-entry path.
- A reduced real-source test toggled a row off, confirmed it, and re-entered;
  that row stayed off. It did not cover Toggle All, the last row, custom skills,
  standalone bundles, or the explicit top-level Apply path.
- The current user test state in `skills/skills.disabled` contains only the
  source-aware header, so all catalog skills are currently represented as
  active on disk. This is a live state observation, not proof that every prior
  interactive sequence persisted correctly.
- The custom catalog row `keyboard-layout-fixer` is currently reported active,
  while the installed manifest/link state was previously observed as stale
  (no matching manifest row and missing target links). No real sync was run to
  reconcile it, so this must not be conflated with selector persistence.

### Investigation decision

Do not patch another line based only on the “one skill” symptom. First run a
deterministic matrix for Toggle All, direct last-row toggling, `q` at each menu
level, and category types. Then compare the same ID through the checklist
result array, `HAWS_DRAFT_SKILLS`, `skills.disabled`, catalog/Preview, and
manifest observation. The first differing boundary determines the fix.

The first attempt must preserve Bash arrays; a pipeline subshell can make a
fixture report a false failure (`CHECKLIST_RESULTS: not found`). That harness
error is not product evidence.

## Confirmed Root Cause: Enabled Skill IDs Can Be Concatenated (2026-09-20)

The focused reproduction found a real persistence defect separate from the
already-fixed checklist label/index mismatch.

### Reproduction

- Used three real rows from `skills/packs/superpowers`.
- Initial draft: row 1 OFF; rows 2–3 ON.
- Action: checklist Toggle All (`Space`), then Confirm (`Enter`).
- Expected: all three IDs present in `HAWS_DRAFT_SKILLS`.
- Actual: row 1 remained OFF according to `_settings_list_contains`.
- Raw draft contained a fused value:

```text
...dispatching-parallel-agents<first-skill-id>
```

### Root cause

`HAWS_DRAFT_SKILLS` is created by command substitution, which strips its final
newline. `_settings_skill_selector()` appends a newly enabled ID with
`selected="${selected}${ids[$i]}"$'\n'` and does not insert a separator when the
existing list is non-empty. The first newly enabled ID is therefore joined to
the last existing ID and cannot be found as an exact newline-delimited entry.

This explains the user's symptom: the UI can show the skill ON, but the draft
contains a malformed combined ID, so later counts/Apply treat that skill as
OFF. It also explains why the issue became visible after the category changes:
the selector now makes more partial-category edits against a non-empty draft.

### Scope decision

This is now the first implementation slice. Fix only the list-delimiter
invariant, then rerun the same fixture and the full persistence checks. Keep
the broader Preview/count/manifest issues separate until this state corruption
is gone.

## Delimiter Fix Green Verification (2026-09-20)

- Product fix commit: `f53b435` (`fix(cli): preserve skill draft item
  boundaries`).
- The same three-row real-source fixture now reports
  `GREEN_EXPECTED_FIRST_ON_ACTUAL=ON`.
- The raw draft is newline-delimited; the previously fused ID is now a
  separate entry.
- Direct row toggle, Toggle All + Confirm, Toggle All + `q` cancellation,
  re-entry after save, and all-on → Toggle All were exercised. Results were
  `ON ON ON`, `OFF ON ON` for cancellation, `ON ON ON` after saved re-entry,
  and `OFF OFF OFF` for the all-on inverse toggle respectively.
- A disposable `settings_apply_skill_draft` fixture with all rows active wrote
  only `# HAWS Disabled Skills (source-aware)`. The real
  `E:/Human-AI-Working-Standard/skills/skills.disabled` file was not written.
- Verification passed: `bash -n haws.sh`, human Doctor (`Overall: Ready`), and
  Doctor JSON (`{"status":"Ready"}`).

## Full Catalog and Preview Regression (2026-09-20)

- The real `settings_skills_page` fixture started with one skill disabled in
  the first real Pack, selected Multi-Skill Packs, entered the first Pack,
  used Toggle All + Confirm, then used `q` to leave the Pack and the category
  page. The target skill became ON, active count returned to `153`, and the
  newline-delimited draft signature exactly matched the all-active catalog.
- The current full-catalog category totals are:

```text
Custom Skills      1 / 1
Single Skills      4 / 4
Multi-Skill Packs 148 / 148
```

- Read-only Preview output includes the four standalone skills (`archify`,
  `drawio-skill`, `graphify`, `humanizer`) and the custom
  `keyboard-layout-fixer` entry.
- Preview reports `caveman` as `20 / 20` and `planning-with-files` as `6 / 6`
  under Multi-Skill Packs, consistent with their current `skills/packs/*`
  source paths.
- These checks used in-memory drafts and a temporary Apply fixture only; the
  real disabled-skills file and installed links were not changed.

## Confirmed Doctor Count Mismatch (2026-09-20)

The reported numeric mismatch is real, but it is in Doctor's display summary,
not in the catalog/category model.

- `catalog_skills` active rows: `153`.
- `_health_collect --deep` counters: `HAWS_HEALTH_SKILLS_ACTIVE=153`,
  `HAWS_HEALTH_SKILLS_TOTAL=153`.
- `HAWS_HEALTH_FINDINGS` rows whose section is Skills: `154`.
- The extra row is the parse-health check:
  `Ready Skills skills.disabled parsed successfully`.
- The remaining 153 rows are the individual active skill entrypoint checks.
- `_health_print_findings()` currently uses the section `total` for the
  successful Skills label, producing `154 active skill check(s) passed`.

This is a confirmed display-count bug. It must be fixed independently from the
selector delimiter fix and category totals.

## Doctor Count Fix Green Verification (2026-09-20)

- Product fix commit: `e195bb2` (`fix(cli): report active skill count
  accurately`).
- `_health_collect --deep` still reports both internal counters as `153`.
- Human Doctor now reports `Skills - 153 active skill check(s) passed`.
- Doctor JSON remains `{"status":"Ready"}`.
- The fix changes only the successful Skills summary to use
  `HAWS_HEALTH_SKILLS_ACTIVE`; it does not alter catalog rows or health status.
