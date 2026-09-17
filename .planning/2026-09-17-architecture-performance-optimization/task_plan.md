# Task Plan: Architecture & Performance Optimization

- [x] Phase 1: Skills Label & Step Wording Polish
  - Format skills description: `[ Active ] - X disabled by user` or `[ All active ] - All active by default`
  - Strip `Step X:` prefix from `[PASS]` result lines in `run_sync`
  - Focus Test: `tests/cli/settings_flow_test.sh` & `tests/cli/sync_test.sh`
  - Checkpoint Commit: `b485bc2` (`fix(ux): polish settings skill status and clean step result headers`)

- [x] Phase 2: In-Memory Session Cache & Incremental Mutation
  - Stop unsetting `HAWS_CATALOG_SOURCES_CACHE` & `HAWS_CATALOG_SKILLS_CACHE` on benign navigation
  - Initial loading message only displayed on cold scan
  - Settings, Skills, and Repositories open instantly (<0.01s)
  - Focus Test: `tests/cli/settings_flow_test.sh` & `tests/cli/launcher_menu_test.sh`
  - Checkpoint Commit: `6cb8f4f` (`perf(catalog): retain session cache across navigation and support incremental mutation`)

- [x] Phase 3: Uninstall Fast-Preview (Eliminate 15s delay)
  - Added lightweight existence verification mode to `ownership_verify` during preview (0.02s instead of 12s)
  - Retained strict SHA256 safety verification during `uninstall_apply` when user confirms `y`
  - Focus Test: `tests/cli/uninstall_test.sh` (13 passed)
  - Checkpoint Commit: `a82b03b` (`perf(uninstall): implement lightweight preview and single-pass apply verification`)

- [x] Phase 4: Doctor State-Fingerprint / Delta Check
  - Added state-fingerprint check (`_health_fingerprint`) tracking git HEAD, hooks path, state timestamps, and managed targets
  - Non-polluting cache stored in system temp directory reduces `haws doctor` runtime from 25.6s to 1.7s (93% speedup)
  - Supported `haws doctor --deep` override
  - Focus Test: `tests/cli/status_doctor_test.sh` (12 passed)
  - Checkpoint Commit: `011ac1e` (`perf(doctor): add state-fingerprint incremental caching with deep override`)

- [x] Phase 5: Parallel Git Fetch during Sync Auto-Update
  - Parallelized `_sync_fetch_candidate` across repositories using background jobs (`&` and `wait`)
  - Evaluates all 13 submodules simultaneously in 1-2s instead of 15s
  - Direct git ref detection in `sync_target` eliminates duplicate network calls
  - Focus Test: `tests/cli/sync_test.sh` (21 passed)
  - Checkpoint Commit: `eee1241` (`perf(sync): parallelize remote repository candidate prefetch`)

- [x] Phase 6: Final Full-Suite Acceptance & Handoff
  - Run full regression suite `tests/cli/run.sh` (all 10 suites: 100% green, 0 failures)
  - Update `HANDOFF.md` and planning files (`34a3c58`)
  - Ready for user review before push

- [x] Phase 7: Deep Architecture & Single-Pass Optimization
  - [x] 7.1 UI & Status Polish:
    - Display skills in settings as dynamic `active x/n` (e.g. `active 120/146`).
    - Hoist `HAWS SYNC` banner to very top before Step 1 in `run_sync`.
    - Add uniform blank lines between Steps 1 through 5.
    - Checkpoint Commit: `f693274` & `dcc9f82`
  - [x] 7.2 Session Cache Retention & Subshell Elimination:
    - Eliminate subshell cache leak in `_settings_repository_remove_page` by calling `catalog_source_kind "${id}" type` directly.
    - Reuse `HAWS_CATALOG_SOURCES_CACHE` in `settings_draft_load` (stop redundant `git rev-parse` on entering Settings).
    - Checkpoint Commit: `dcc9f82`
  - [x] 7.3 Clean Offline Sync (Batch Fallback):
    - Silence Git fatal stderr (`2>/dev/null`) during candidate fetch.
    - Skip redundant sequential retry loop in `sync_target` when parallel prefetch is done.
    - Checkpoint Commit: `f693274`
  - [x] 7.4 Uninstall Apply Single-Pass Batch Update:
    - Replace 150x `awk` and atomic disk rewrite loops in `uninstall_apply` with a single-pass in-memory batch write.
    - Checkpoint Commit: `156b493`

- [x] Phase 8: Verification & Checkpoint Commit
  - [x] Run targeted tests (`sync_test.sh`, `settings_flow_test.sh`, `uninstall_test.sh`).
  - [x] Run full test suite (`tests/cli/run.sh`) - 100% pass across all 10 suites.
  - [x] Checkpoint commits: `f693274`, `dcc9f82`, `156b493`.
