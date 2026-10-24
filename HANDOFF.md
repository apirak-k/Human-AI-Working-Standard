# Development Handoff

Updated: 2026-10-24

## Branch Contract

- `dev` is the working branch and carries automated tests, fixtures, and development instructions. `main` is the user branch and carries user-facing HAWS code and finalized documentation.
- `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, tests, fixtures, unfinished plans, and task progress notes stay on `dev`; keep user-facing product code and documentation on both branches.
- When a completed work chunk is pushed to `dev`, synchronize its user-facing code and documentation to `main` in that task. Do not wait for the user to repeat this direction.
- The `origin` branch set is `main` and `dev`.

## Kit Device-Local Skill Sources — 2026-10-09

- Root cause: default `kit add` edited the HAWS root by registering a submodule and then immediately ran Sync. Strict root preflight correctly blocked that uncommitted `.gitmodules`/gitlink change, so the add and Sync flow contradicted each other.
- Default `kit add` and Settings repository Add now clone/register external skills under device-local `.haws/state/skill-sources/`; Sync links those skills without dirtying the HAWS root. Maintainers can still request `kit add --tracked` for a committed submodule.
- Added strict `kit migrate <name>` for one exact older Kit addition. It requires the staged gitlink and `.gitmodules` registration to be the only clean root changes, verifies the checkout/origin and ignored files, reuses an existing clean device mirror, and refuses unrelated root or `.gitmodules` changes. `_sync_root_status` and `_sync_root_preflight` remain unchanged.
- Updated the shared README and added dev-only regressions for add → Sync, source and HAWS updates, strict root protection, migration, ignored-file preservation, prune ownership/origin checks, and tracked submodule compatibility.
- Verification on Windows Git Bash: `tests/cli/run.sh` passed **223/223** across launcher/menu (19), local state (16), Settings (56), catalog (6), repository/skill (45), Sync (33), status/doctor (14), uninstall (16), Home (4), and lifecycle/plugins E2E (14). `bash -n` and `git diff --check` passed. Mutation-testing the strict `.gitmodules` comparison made `test_kit_migrate_refuses_unrelated_gitmodules_addition` fail; restoring the comparison made it pass.
- User-facing commit: `696b498` on `dev`; local `main` promotion: `6487055`. Both branches were pushed to their matching origin branch after verification.
- On local `main`, the staged Hallmark addition was verified clean, including ignored files, with origin `https://github.com/Nutlope/hallmark.git` and matching checkout/index SHA `13ac0ec7e148655948100b6396439e481361d690`. `kit migrate hallmark` moved it into device-local state; the HAWS root is clean and `kit list` reports the local source `up-to-date`.
- Post-migration `doctor` reports one unrelated device-local warning: `gemini-skills-json` differs from its recorded ownership fingerprint. It was left untouched. macOS and Linux were not tested.
- Resume on `dev` at the follow-up test/Handoff commit recorded below; keep this Handoff and the test files dev-only.

## User Branch Content — 2026-10-05

- `main` is for HAWS users. Keep the automated test suite and fixtures on `dev`; they are not part of the user branch.
- The full `tests/` directory is retained on `dev` and removed from the current `main` tree. Past commits remain in Git history; no history rewrite was performed.
- Keep finalized user-facing code, skills, templates, README, and user documentation synchronized to both branches. Keep test and continuation material on `dev` only.
- Delivery: policy and handoff commit `59a7ba4` was pushed to `origin/dev`; main cleanup commit `f0e5ecf` removed the 15 tracked test files (5,740 lines) and was pushed to `origin/main`. The branch tree comparison confirmed that tests and development-only documents are the only intended differences. `git diff --check` passed; no runtime tests were run because this cleanup changed no executable product code.

## Main User-Branch Audit Follow-up — 2026-10-05

- After `f0e5ecf` removed the root test suite, the tracked-file audit found two HAWS-maintained tests elsewhere: `ai-configs/codex/agents.test.mjs` and `skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`. Commit `ee957ae` removes them from `main`; both remain on `dev`.
- `PROJECT_SPECIFIC.md` now keeps all HAWS-maintained tests and fixtures on `dev`, regardless of path, including `tests/`, `test/`, `__tests__/`, `*.test.*`, and `*.spec.*`. This closes the prior gap where tests next to product code escaped the root-suite cleanup.
- Verified the resulting repository-level tree: no HAWS-maintained test files remain in `main`. Imported skill submodules remain upstream Gitlinks; their upstream contents are not HAWS-owned test artifacts.
- `origin/main` was pushed to `ee957ae`; the branch-policy update was pushed to `origin/dev` at `fc4a349` before this Handoff update.
- The Ponytail/Caveman preference was present only in a skip-worktree local overlay of the `main` checkout, not in the tracked `main` commit. The tracked default is neutral. The preference and the ignored local `SKILLS_GUIDE.md` were moved into the private `dev/secondbrain/notes/` directory; both files match `.gitignore` and are not staged.
- History check: old `main` commits contain root development instructions, tests, planning records, and a `secondbrain/notes/SKILLS_GUIDE.md`; those files are absent from the current `main` tree. The old skill guide inspected here is a generic skills taxonomy. Normal cleanup commits preserve old objects in Git history; no history rewrite was performed.
## Branch Sync Rule Correction — 2026-10-05

- The previous correction incorrectly placed `AGENTS.md` and `PROJECT_SPECIFIC.md` on `main`; both are development-only instructions and must remain on `dev` with this Handoff.
- The standing rule is stored in the dev-only `PROJECT_SPECIFIC.md`: every completed, checked work chunk delivered to `dev` also syncs its user-facing code and documentation/templates to `main` in the same task; tests stay on `dev`.
- Updated the user-facing README on both branches to describe scrolling long menus. Removed the development instruction files from `main`.
- Delivery under the current policy: only user-facing product code and documentation are synchronized to `main`; tests, development instructions, and this Handoff remain on `dev`. Resume from the current `dev` HEAD.

## Skill Menu Viewport and Codex Skill Check — 2026-10-05

- Root cause: `interactive_menu` redrew every checklist row and moved the cursor by the full list height. Long skill packs exceeded the terminal viewport; cursor movement was clamped at the screen boundary, so redraws duplicated rows. Long descriptions also wrapped and made the physical list taller than its row count.
- Fix: render only the visible row window, keep the selection in view, show the item range, and fit row details to the terminal width. The key controls are shortened only when they would wrap.
- Codex skill check: `frontend-ui-engineering` exists in the `agent-skills` pack, its `SKILL.md` and HAWS Codex link are readable, it is not disabled in the device-local skill list, and the current Codex catalog exposes it. The screenshot's `mattpocock-skills` pack is separate; no skill repair was needed.
- Branch workflow rule at that delivery: completed, checked work was synchronized to both branches. The current rule keeps tests and development instructions on `dev` and sends only user-facing work to `main`.
- Verification: launcher/menu **19/19**, local state **16/16**, settings flow **56/56**, catalog **6/6**, repository/skill **27/27**, sync **32/32**, status/doctor **14/14**, uninstall **16/16**, home **4/4**, lifecycle/plugins **14/14** — **204 passed, 0 failed**. `bash -n` and `git diff --check` passed. Manual 24×80 TTY check with 35 skills showed 16 visible rows per frame, range update from `Items 1-16 of 36` to `Items 2-17 of 36`, and no wrapped details.
- Delivery: menu fix commit `ef23b16` was pushed to `origin/dev`, and the same code and regression test were delivered to `main` as `2ae4967`. This Handoff and the workflow instructions remain on `dev`; the README behavior note is shared. Resume from the current `dev` HEAD.

## Sync Candidate Validation Follow-up — 2026-10-02

- Root cause: candidate validation required every active skill entrypoint to remain at its previous path. A valid upstream move or removal therefore failed the entire source update.
- Updated validation to inspect regular skill entrypoints in the fetched candidate tree, accept path changes/removals when the candidate still has usable skill content, and continue rejecting an empty candidate without falling back to old content.
- Verification: `tests/cli/sync_test.sh` passed **32/32**; `bash -n haws.sh tests/cli/sync_test.sh` and `git diff --check` passed.
- Fix commit `9df9a79` was promoted to `main` in merge commit `e7da972`; `origin/main` was verified at that revision.
- Next action for an affected device: update HAWS to `main`, then retry Sync.

## Baseline Audit Follow-up — Commit 7846259

- Source: today's ChatGPT conversation “แก้HAWS,” which prioritized a real install-to-uninstall lifecycle, Second Brain settings as a draft until final confirmation, preserving unowned files during Sync, and a clear Bash minimum for macOS.
- Updated `haws.sh` and the Gemini JSON adapter to merge HAWS skill entries with existing Antigravity settings, record only HAWS-owned entries, and remove only those entries during uninstall. Existing or edited unowned files are preserved.
- Changed Second Brain connect/disconnect in Settings to remain draft actions until Install/Update applies the reviewed plan. Direct `haws.sh user connect` remains immediate.
- Added uninstall state tracking so a completed full uninstall does not reopen as installed solely because an old manifest remains. Native Codex cleanup now runs through its ownership manifest, and unchanged unowned profiles are no longer claimed by the shell ownership ledger.
- Added a Bash 4.2 startup guard and documented the Homebrew Bash launch command for macOS.
- Updated the stale Second Brain Settings expectations to verify draft-only connection changes and no mutation before final confirmation. Scoped the worktree ownership assertion to skill records, retained the Antigravity config status line, and fixed the Windows Codex manifest path by constructing it with Node's path API. The E2E helper now prints captured command output on failure.
- `tests/cli/run.sh` passed on Windows Git Bash 5.3.15 with 167 passed and 0 failed:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 38 passed |
| Catalog | 6 passed |
| Repository/skill | 23 passed |
| Sync | 31 passed |
| Status/doctor | 13 passed |
| Uninstall | 13 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 6 passed |

- Codex native profile tests passed 14/14. Disposable Gemini adapter checks passed for preserving user entries, removing only HAWS-owned entries, retaining edited entries, cleaning HAWS-created JSON, and leaving empty candidates untouched.
- `bash -n haws.sh`, `node --check ai-configs/codex/agents.mjs`, `node --check ai-configs/gemini/skills-json.mjs`, and `git diff --check` passed for commit `7846259`. [Unverified] The startup guard has not been exercised on macOS's system Bash 3.2; this machine has Git Bash 5.3.15. That commit is the pushed `origin/dev` baseline; the separate review fixes below are local until reported complete.

## ChatGPT Review Feedback Follow-up — Commit 4d5d222

- Evaluated the nine review findings against the current CLI, Gemini/Codex adapters, ownership records, and lifecycle tests. Legacy ownership recovery is now limited to a one-time migration from an installed v1 manifest and exact matching artifacts. Gemini adoption uses a path-specific candidate map; newly encountered exact-looking user integrations remain unowned.
- Uninstall now clears stale ownership rows for changed or missing artifacts while retaining ownership for dirty managed repositories. Codex Node adapter execution is required when either owned native records or a valid HAWS Codex manifest exists, and skipped when no HAWS Codex state exists.
- Second Brain reconnect operates on a disposable sibling candidate and only swaps it into place after fetch, merge, and push succeed. A failed push leaves the existing local checkout, history, and index unchanged; linked worktrees are refused.
- Install, Update, Settings, and Home preserve severe statuses such as `2` and `130`, including the `settings` command's final process status. First-use Setup no longer offers “Use Previous Settings” unless saved settings exist.
- Lifecycle coverage now includes a fresh integration that remains unowned through Uninstall, a frozen legacy fixture sourced from `7846259`, stateful Setup → Update → Uninstall → Setup, and Windows junction fixtures. The post-uninstall Auto Update assertion fails when its expected saved value is absent.
- The final `tests/cli/run.sh` regression passed on Windows Git Bash with **188 passed, 0 failed**:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 51 passed |
| Catalog | 6 passed |
| Repository/skill | 24 passed |
| Sync | 31 passed |
| Status/doctor | 14 passed |
| Uninstall | 16 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 9 passed |

- The post-uninstall Auto Update assertion was mutation-tested: changing the expected saved value makes its focused test fail. `bash -n haws.sh`, `node --check ai-configs/gemini/skills-json.mjs`, `node --check ai-configs/codex/agents.mjs`, and `git diff --check` passed.
- These verified review fixes were committed on `dev` and pushed to `origin/dev` after the checks above; the exact revision is in Git history.
- [Unverified] macOS and Linux were not run. Native platform behavior outside Windows Git Bash remains unverified.

## Completed

- Integrated the useful changes from the three public branches into `main`.
- Preserved the Second Brain merge and Settings Apply fixes with focused regression tests.
- Restored the advisory `commit-msg` hook required by the current setup flow.
- Updated repository taxonomy detection in `catalog_source_kind` to respect `skills/standalone/*` folder taxonomy and ignore hidden directories (`.*`).
- Fixed `load_disabled_skills` in `haws.sh` to declare `DISABLED_SKILLS` as a global associative array (`declare -gA`), eliminating `unbound variable` crashes during sync.
- Refined Antigravity (`skills.json`) generation to register exact active skill directories instead of broad parent directories, cleanly excluding disabled skills from Antigravity IDE.
- Added comprehensive `ponytail*` prefix matching in sync to prevent duplicate global symlinks when plugin cache exists.
- Kept this active checkpoint on `dev` only.

## Prior Verification — Before the Current Audit Follow-up

The results below describe the earlier tree only and do not verify the current uncommitted changes:

The scripts included by `tests/cli/run.sh` were run individually on the final tree:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 38 passed |
| Catalog | 6 passed |
| Repository/skill | 23 passed |
| Sync | 31 passed |
| Status/doctor | 13 passed |
| Uninstall | 13 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 6 passed |

Additional checks passed: Settings Apply regression, Second Brain merge preservation, and `bash -n`. Node tests passed 28 with 1 Windows symlink case skipped because the runner lacks link-creation privilege.

## Graphify Installation Boundary

- HAWS catalogs Graphify as an external standalone skill. HAWS Sync updates its device-local runtime source and links the skill directory like other skills, so the linked skill instructions follow that source.
- HAWS does not bootstrap Graphify's CLI or run Graphify's platform installer. Users who need the full CLI and native Codex/Antigravity skill bundles install those Graphify extras separately; HAWS Sync does not refresh the generated app bundles.
- Device snapshot on 2026-09-30: the HAWS submodule pin is Graphify `0.9.65`, while this device's runtime source, CLI, and Codex/Antigravity bundles are `0.9.72`. The CLI is editable from the device runtime; the app bundles are generated copies outside HAWS Sync.
- Current accepted behavior: HAWS supplies Graphify as a regular skill, and users maintain Graphify's CLI and app-specific extras. Add Graphify-specific HAWS automation only if this support requirement changes.

## Resume Point

Continue on `dev`. Use the final dated entry below for the latest verified result and branch delivery state. Keep automated tests and this Handoff on `dev`; user-facing runtime files are synchronized to both branches. Preserve the pre-existing edit to `secondbrain/WORKFLOW.md` without staging or modifying it.

## Global Pointer Ownership Migration Repair — 2026-10-23

- Root cause: `_haws_prepare_ownership_ledger_v2` completed the legacy integration migration while upgrading the ownership ledger. The two markers consequently had the same timestamp, so Sync treated existing exact HAWS pointers as unowned files after the migration window had closed.
- Fix: ledger upgrade no longer completes integration migration. An affected install can recover pointer ownership only when the marker timestamps identify the upgrade case, the pointer predates the marker, and the complete HAWS block exactly matches current instructions. Recovery touches ownership state only; it does not rewrite the pointer or reopen agent, skill-link, Gemini, or hook adoption. An unversioned current ownership ledger or quarantined Gemini manifest blocks full legacy migration, while the supported old device-level skill ledger does not block migration of other artifacts.
- Marker repair is written only after a successful Sync. Failed Sync leaves the recovery eligible for retry.
- Changed user-facing files: `haws.sh` and `README.md`; both must be synchronized to `main`. Regression tests and this Handoff remain on `dev`.
- Device evidence (read-only): the two markers both contain `2026-10-01T23:17:50Z`, the pointer ownership ledger has no entries, and both existing pointer files predate the markers. No live Sync was run during diagnosis.
- Verification: `tests/cli/run.sh` passed 225 tests with 0 failures, including both pointer-recovery regressions and the legacy-ledger ownership-boundary case. `bash -n` and `git diff --check` passed.
- Delivery boundary: keep regression tests and this Handoff on `dev`; promote only `haws.sh` and `README.md` to `main`. Preserve the pre-existing user edit in `secondbrain/WORKFLOW.md`; do not stage it.

## Antigravity Skill Link Ownership Repair — 2026-10-23

- The user's screenshot came from the E-drive `haws.bat`; the launcher changes to its own HAWS checkout and the successful `[ADOPTED]` pointer lines confirm the current main launcher ran. `[PRESERVED]` on native Antigravity agent profiles is an ownership safeguard, not a Sync failure.
- Root cause in the Antigravity skills adapter: dead path-only entries inside HAWS's device-local `skill-sources` cache were preserved indefinitely. The device had 14 such missing targets and only six owned entries.
- The first candidate fix adopted exact existing paths, but the full lifecycle suite correctly rejected that behavior because a user's fresh exact-looking integration must remain unowned. Final fix on `dev`: remove only a path-only entry beneath HAWS's private source cache when its target is no longer a valid skill directory. Keep all existing active entries user-owned unless already present in HAWS's ownership record. Preserve entries with user metadata and paths outside that cache.
- The screenshot reports 120 active skills out of 146 catalog entries. The difference is 26 disabled skills; 240 linked counts the same 120 skills in two environments. The 10 native agent profiles are a separate category, not extra skills. Do not change disabled-skill selections to force a count of 130.
- Delivery boundary: promote only `ai-configs/gemini/skills-json.mjs` and `README.md` to `main`; keep `tests/cli/gemini_skills_json_test.mjs`, its `tests/cli/run.sh` entry, and this Handoff on `dev`. Preserve the user's existing `secondbrain/WORKFLOW.md` edit and never stage it.
- Verification: `tests/cli/run.sh` passed 226 tests with 0 failures, including the new Antigravity stale-cache regression and all 14 lifecycle/plugin E2E cases. The focused adapter test, `node --check` for adapter/test, and `git diff --check` passed.

## False Gemini Ownership Attention — 2026-10-23

- Root cause: `ownership_list environments` emits six schema-v2 fields (`group`, `kind`, `path`, `source`, `fingerprint`, `schema`). `_health_collect` read the row as if it had five fields, shifting every value and reporting valid Gemini ownership as `Attention`. `_health_fingerprint` also used column 2 (`kind`) instead of column 3 (the target path), so the cache did not track the owned environment target.
- Fix: parse the ownership row with its group column, pass the actual kind/path/source/fingerprint to verification, and fingerprint the actual target path. A valid Gemini config now verifies as Ready; a missing target still reports Attention and invalidates cached health.
- User-facing README now explains `[ADOPTED]`/`[PRESERVED]`, the distinction between Sync result and health status, and the separate active skill, linked skill, and agent counts.
- Regression coverage: `test_gemini_environment_ownership_health_reads_schema_v2_columns`; updated the no-sync-history expectation to Ready because a missing last-sync record is informational and no ownership fault exists.
- Verification across component runs: 227 passed, 0 failed — launcher 19, local state 16, settings 56, catalog 6, repository/skill 45, Sync 35, Antigravity adapter 1, status/doctor 15, uninstall 16, Home 4, lifecycle/plugins 14. `bash -n` and targeted `git diff --check` passed. The first aggregate run stopped at the outdated no-sync-history expectation; after correcting it, all remaining suites passed in component runs.
- Delivery boundary: synchronize only `haws.sh` and `README.md` to `main`; keep `tests/cli/status_doctor_test.sh` and this Handoff on `dev`. Leave the user's existing `secondbrain/WORKFLOW.md` edit untouched and unstaged.
- Delivery complete: `origin/main` contains the user-facing `haws.sh` and README fix; `origin/dev` contains the same user-facing change plus the regression test and Handoff updates. The E-drive checkout is clean on `main` at the same head as `origin/main`. The dev worktree is on `dev` and synced to `origin/dev`; the pre-existing `secondbrain/WORKFLOW.md` edit remains unstaged and uncommitted.
- Live E-drive Sync after promotion exited 0 with `[PASS] HAWS synchronization completed` and `Overall: Ready`. Sources: 15 up to date, 1 skipped, 0 failed, 0 blocked, 0 timeouts. It reported 120 active skills / 146 catalog skills and 240 links across Gemini and Codex; 10 agent integration items are counted separately. Brain Auto Update was paused only for this run to prevent a private Second Brain remote write, then `settings.tsv` was restored byte-for-byte to Skills/Brain/Sync all On.
- Verified `frontend-ui-engineering` exists at `C:\Users\Boom\.agents\skills\frontend-ui-engineering\SKILL.md`; its skill metadata is present in the current Codex skill list. This is separate from the false Gemini ownership health warning.

## Windows Agent Profile Link Verification — 2026-10-23

- Device diagnosis: the five Antigravity `agent.md` files exactly matched `agents/*.md` and were listed in `.haws_manifest`, but the device ownership ledger had no corresponding agent rows after the migration marker completed. This caused `[PRESERVED]` even though the files were HAWS-generated.
- The first local adoption was not a valid repair: Git Bash `ln -s` returned success while leaving regular copies, and Sync reported `[LINKED]` without checking the filesystem type. That repair also exposed duplicate ownership rows when the same path changed record kind. The state was not considered fixed.
- Root-cause fix: `safe_link_file` verifies a symbolic link with `-L` and its exact target, verifies hard links with `-ef`, and otherwise records a copied file as `generated-file` and reports `[COPIED]`. If an earlier Sync recorded an exact source copy as a symlink or hard link, Sync reclassifies it only when the recorded source matches and its bytes exactly match that source. `ownership_record` replaces any existing record for the same group and path, even when the ownership kind changes.
- Regression tests: simulate a link command that exits successfully but creates a regular file, and recover an exact copy previously recorded as a symlink; both assert truthful `[COPIED]` output and one ownership row. Scope the tests' fake PATH to each run so it cannot replace Windows `cmd.exe` in later junction fixtures.
- Verification on Windows Git Bash: the full `tests/cli/run.sh` passed **228 checks, 0 failed** before the final stale-record recovery case was added. After that final code and regression test, `tests/cli/repository_skill_test.sh` passed **47/47**, including both new profile-link regressions and the ten junction/worktree cases; `bash -n haws.sh` and `git diff --check` passed. The only full-run test failures were reproduced as a fake-PATH leak from the new test; all affected cases then passed in the full run after scoping PATH.
- User-facing files: `haws.sh` and `README.md` must be synchronized to both branches. The tests and this Handoff stay on `dev`. Preserve the existing edit to `secondbrain/WORKFLOW.md`; never stage it.
- Delivery at the 2026-10-23 checkpoint: `beb10c4` was the `dev` delivery commit; user-facing `haws.sh` and `README.md` were on `main` at `1e4221b`. The two files matched across branches. Tests and this Handoff remained dev-only.
- Live E-drive Sync after promotion exited 0 with `[PASS] HAWS synchronization completed` and `Overall: Ready`. Sources: 15 up to date, 1 skipped, 0 failed, 0 blocked, 0 timeouts. It reported 120 active skills / 146 catalog skills and 240 Codex links; 10 agent integrations are counted separately. All five Antigravity profiles reported `[COPIED]`, matching their actual regular-file type; each is byte-identical to its source and has exactly one `generated-file` ownership row. No Antigravity agent was `[PRESERVED]`.
- Brain Auto Update was turned off only during that Sync to avoid writing to the connected personal Second Brain remote; `.haws/state/settings.tsv` was restored and byte-compared to its original contents. Skills and Brain Auto Update both read `on` afterward.
- Worktree state at that 2026-10-23 checkpoint: the E-drive checkout was clean on `main` at `1e4221b`; the `dev` worktree was at `beb10c4`. A later Handoff-only commit advanced `dev` to `a3704c243a6f0a45e8b69285effd8f0d74d6a81c` before the 2026-10-24 task. The pre-existing `secondbrain/WORKFLOW.md` edit remains user-owned and must stay unstaged and uncommitted.

## Native Agent Hardlink Ownership Repair — 2026-10-24

- Confirmed root cause: `safe_link_file` reclassified any non-symlink regular destination as `generated-file` when its bytes matched the recorded source. A valid hardlink met that test before the existing `-ef` hardlink retention check, so Sync reported `[REPAIRED]` and removed/recreated the destination.
- Fix: stale-link recovery now requires the destination not to share filesystem identity with its source. Exact ordinary copies with matching source ownership and bytes still recover as `generated-file`; valid hardlinks reach the existing keep path. Link creation and the `[COPIED]` fallback are unchanged.
- Regression coverage: the existing false-success link-command test remains; stale copies recorded as either `symlink` or `hardlink` still reclassify; a new valid-hardlink test checks `src -ef dest` before and after Sync, one `hardlink` ownership row, and no `[REPAIRED]`, `[LINKED]`, `[HARDLINK]`, or `[COPIED]` report.
- Verification on Windows Git Bash 5.3.15: `tests/cli/repository_skill_test.sh` passed **49/49**. The final `tests/cli/run.sh` passed **231 checks, 0 failures**: launcher/menu 19, local state 16, settings 56, catalog 6, repository/skill 49, Sync 35, Antigravity adapter 1, status/doctor 15, uninstall 16, Home 4, lifecycle/plugins E2E 14. `bash -n haws.sh` and `git diff --check` passed.
- Branch delivery: product-code commit `578c74d69f40aac4076b482b4c836df025854cd1` is on `dev`; the same `haws.sh` fix was promoted to `main` as `70c3dbce12d91b1f0649b10f9a0ff4f45c44ffb9`. After the full suite passed, both branches were pushed. `origin/main` is at `70c3dbce12d91b1f0649b10f9a0ff4f45c44ffb9`; `origin/dev` includes the runtime fix, dev-only tests, and this Handoff. `haws.sh` and `README.md` match across branches; README is unchanged. The current `dev` tip is a later development-only test/Handoff commit above the product-code commit; read `git rev-parse origin/dev` for its exact SHA and do not report the product-code SHA as the current `dev` HEAD.
- Preserve the pre-existing user edit to `secondbrain/WORKFLOW.md`; it is not part of this change and must remain unstaged and uncommitted.
- [Unverified] macOS and Linux were not run. Hardlink identity was exercised on Windows Git Bash; fallback was exercised through simulated link-command failure, not through a real platform where link creation is unavailable.

## macOS HAWS Sync Convergence — 2026-10-24

- Reproduced on this Mac (macOS 26.6.2, arm64). `/bin/bash` is Apple Bash 3.2.57; the user's current `bash` resolves to `~/.local/bin/bash` 5.2.0. The original checkout was `main` at `f9d01d8`, ahead 3 / behind 5 versus `origin/main`. The exact stock-Bash invocation stopped at HAWS's version guard. Running the compatible HAWS implementation reproduced `haws` candidate activation failure because the local branch had diverged and Sync permits only fast-forward activation. All 13 registered sources were available; status was 121 active / 145 total, with Gemini and Codex detected.
- Root causes: a child background prefetch could materialize a missing source without invalidating the parent process's pre-materialization catalog; a same-command HAWS update could continue later phases in the old runtime; and stock macOS Bash could not meet the runtime minimum. These paths are now covered by regression fixtures. The cache fix reports source materialization back to the parent, invalidates only when needed, and refreshes source IDs. Direct CLI self-update releases its lock and re-executes the updated implementation once with the original arguments. The launcher bootstraps to a compatible user-installed Bash when invoked by stock Bash.
- The stale-catalog hypothesis is confirmed by the background-prefetch regression: a multi-skill source absent during initial catalog loading becomes visible and is linked in the same Sync after child materialization. The self-update/old-runtime hypothesis is confirmed by fixtures that update HAWS and add a source, then verify the new runtime handles the same command. Neither required a second Sync in the fixture.
- After verification, the current checked-out catalog contains 145 rows: 144 rows from 13 registered sources plus one local custom skill. Of 178 physical `SKILL.md` / `skill.md` files in registered sources, 144 pass HAWS eligibility filters. There are 121 active rows and 24 deliberately disabled rows. The current Taste source has one physical eligible skill, one catalog row, and one active skill; the 12 old Taste integration names were stale remnants, not current eligible skills.
- Main's user-facing HAWS runtime is identical to the verified dev runtime. Focused coverage includes absent-source preparation, background parent-cache invalidation, multi-skill counts, disabled selections, HAWS self-update, a source added by the HAWS update, idempotent second Sync, and Bash 3.2 bootstrap.
- Full verification after the final implementation and test changes: `tests/cli/run.sh` passed **238 checks, 0 failures** (launcher/menu 19, local state 16, settings 56, catalog 6, repository/skill 49, Sync 43, status/doctor 15, uninstall 16, Home 4, lifecycle/plugins E2E 14). The targeted static Sync-output test also passed. Supported-Bash syntax checks and `git diff --check` passed.
- Real Mac acceptance on local `main` `dfded389163270b323d772932c5aac41ce9c7b4c`: two consecutive exact `bash haws.sh sync` runs exited 0. Each reported 14 targets up-to-date, one intentional Second Brain skip while Brain Auto Update was temporarily off, zero Failed/Blocked/Timeout, and `[PASS] HAWS synchronization completed`. Both runs retained 121/145 active/total and 242 skill links across Gemini and Codex; status and Doctor reported Ready. HAWS HEAD stayed at `dfded38`, already containing the fetched `origin/main` state at `70c3dbce`; the local main branch is ahead by four commits and has no behind commits.
- Live integration audit matched all 121 active catalog targets by name and source: 121 valid Codex symlinks, 121 HAWS Gemini config paths, and 121 skill entries in the manifest; zero missing, extra, broken, or wrong-target Codex links. The single active Taste skill is present in both environments. The 24 disabled selections remained disabled. Gemini's config has 18 existing entries outside HAWS's manifest; six resolve through alternate path spellings to already-installed HAWS targets, and were preserved because the ownership manifest does not claim those entries.
- The on-device ownership file had historical duplicates and missing-target records: 121 `junction` rows exactly duplicated verified live symlinks, 12 versioned rows targeted removed Taste links and sources, and 37 unversioned rows had no destination. Only ownership metadata was pruned; no live integration, source checkout, user skill, or disabled-selection file was removed or changed. The final file has 121 valid versioned symlink records, with zero duplicate destinations, stale destinations, or invalid records.
- Brain Auto Update was disabled only during the two live Sync runs to avoid modifying personal Second Brain content. The settings file SHA-256 was identical before and after each run, Brain Auto Update is `on` again, and Second Brain remained clean at `ffca926`.
- Delivery: local `main` is a merge of the user's existing commits and fetched `origin/main`, with HAWS Sync repair included; `dev` retains tests and this Handoff. Nothing was pushed. Preserve `secondbrain/WORKFLOW.md` as a user-owned file; it was not staged or changed.
- [Unverified] The six Gemini path aliases are known to resolve to current HAWS targets, but their original authorship cannot be established because they are absent from HAWS's ownership manifest; they remain preserved. No other operating system was exercised in this acceptance run.

## Dynamic SINGLE/PACK Source Classification — 2026-10-24

- Root cause: `catalog_source_kind` treated `skills/standalone/*` as SINGLE and `skills/packs/*` as PACK before inspecting content. Settings repeated that path check in the skill selector, totals/recounts, and preview. Sync also compared only currently active skill paths, so a new `SKILL.md` or a structural change limited to disabled skills could be skipped; source-kind/catalog caches were not invalidated after an existing source checkout advanced.
- Architecture decision: `catalog_source_kind` now counts rows from `catalog_skills baseline <source_id>`. This reuses HAWS eligibility checks, empty-file rejection, legacy-name exclusions, and per-source display-name deduplication, while the baseline catalog keeps device-local enable/disable choices out of classification: zero rows is `UNVERIFIED`, one is `SINGLE`, and more than one is `PACK`. A source filter avoids scanning unrelated sources for each classification.
- Settings selector, category totals/recounts, and install/update preview now use the centralized source kind. Repository-source labels, Doctor/health output, and other callers already used `catalog_source_kind`, so they inherit the corrected result.
- Sync now activates a fetched candidate whenever a `SKILL.md` or `skill.md` path changes, regardless of current skill enablement. After a successful existing-source update it invalidates source, skill, and source-kind caches before later Sync phases run. Documentation-only source revisions still use the existing no-checkout fast path.
- Taxonomy audit: the remaining `skills/packs/` and `skills/standalone/` checks constrain registration/destination safety or locate stable stored source paths. Kit add continues to store device-local sources under `skills/packs/<name>` for compatibility; this does not set their category. Source IDs and the Taste source path were not moved or migrated. `skills/custom/` remains its distinct Settings category.
- Files changed for this task: `haws.sh`, `README.md`, `agents/organizer.md`, `tests/cli/repository_skill_test.sh`, `tests/cli/settings_flow_test.sh`, and this Handoff. A pre-existing unstaged edit in `tests/cli/sync_test.sh` was preserved and is not part of this task.
- Regression coverage: effective catalog filtering and duplicate-name collapse; disabled skills do not change PACK classification; pack-to-single and single-to-pack remote updates are applied and classified during one Sync without moving the source; repeat Sync preserves skill count, source HEAD, and ownership; Settings category totals and preview follow the catalog kind even when the storage folder suggests the opposite.
- Taste acceptance (read-only): GitHub `Leonxlnx/taste-skill` `main` and the local device source cache both resolve to `6010f91a9935f1c167dfc500fb1a475681892e6b`. The catalog keeps source ID/path `skills/packs/taste-skill::skills/packs/taste-skill`, classifies it as `SINGLE`, and contains only `design-taste-frontend` with `active=1`. Its current `~/.agents/skills/design-taste-frontend` symlink resolves to a nonempty `SKILL.md`. No Taste code, checkout, or remote was modified.
- Verification on macOS with Homebrew Bash 5.2: `bash -n haws.sh` passed; `git diff --check` passed; `bash tests/cli/run.sh` passed **243 checks, 0 failures** (launcher/menu 19, local state 16, Settings 56, catalog 6, repository/skill 53, Sync 43, Antigravity adapter 1, status/doctor 15, uninstall 16, Home 4, lifecycle/plugins 14). Focused source-classification tests also passed.
- Branch/delivery state: runtime/docs commit `92008d3` is on local `dev`; the tests and this Handoff remain dev-only. Local `main` has matching user-facing files in commit `b1c2f71`. The remote tips remain `origin/dev` `696e40923415657c5372ac6f2255a2bc9eb937ba` and `origin/main` `70c3dbce12d91b1f0649b10f9a0ff4f45c44ffb9`; no push was performed because README requires explicit user confirmation before any `git push`. Preserve the pre-existing unstaged `tests/cli/sync_test.sh` diff.
- [Unverified] Windows and Linux were not exercised in this task. No live Sync was run against the user's installed Taste source; the real source and existing link were inspected read-only, while same-Sync structure changes were verified with local Git remotes in regression fixtures. Remote publication remains pending explicit user confirmation.
