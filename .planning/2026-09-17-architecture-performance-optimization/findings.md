# Findings: Architecture & Performance Optimization Audit

## 1. Context & Baseline State
- Active Worktree: `.worktrees/cli-task1-remote`
- Active Branch: `codex/remote-continuation` (currently at `901f49d`)
- Test Status: All 10 CLI test suites in `tests/cli/run.sh` currently pass 100%.

## 2. Root-Cause Analysis of Performance & Usability Bottlenecks

### Finding 1: Eager Cache Unset in Navigation Lifecycle
- **Location:** `haws.sh:4430` in `settings_draft_load()` and line 4471 in `settings_draft_discard()`.
- **Problem:** `unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE` is called every time Settings is entered or exited.
- **Consequence:**
  - `settings_draft_load` takes 4.2s on Windows because line 4446 immediately executes `catalog_sources` from scratch.
  - Entering `Skills` or `Remove Repository` re-scans 50+ skills and submodules from scratch (3-5s).
- **Architecture Fix:** Preserve session cache in memory across menu navigation. Invalidate only on real mutations (git add submodule, sync pull). Support incremental cache mutation on add/remove.

### Finding 2: Uninstall Double-Verification & Eager Hashing
- **Location:** `haws.sh:4057` in `uninstall_preview()` and line 4145 in `uninstall_apply()`.
- **Problem:** `uninstall_preview` computes SHA256 hashes for dozens of files and runs `git status` on every submodule just to render the preview table. Then `uninstall_apply` repeats the exact same SHA256 calculation.
- **Architecture Fix:** Preview does lightweight existence/liveness check (<0.2s). Deep SHA256 hashing runs once during `uninstall_apply` after user confirms `y`.

### Finding 3: Doctor Full-Scan Brute Force
- **Location:** `haws.sh:66` in `_health_collect()`.
- **Problem:** Scans all 50+ skills and git hooks from scratch every time, taking 10-18s on Windows even when zero files changed.
- **Architecture Fix:** State Fingerprint (Git HEAD + config file mtimes). If fingerprint matches, return cached health findings in 0.05s. Provide `--deep` flag for forced full audit.

### Finding 4: Sequential Network Fetch in Sync Auto-Update
- **Location:** `haws.sh:2140-2147` in `sync_run()`.
- **Problem:** Loops through repositories one by one executing `_sync_fetch_candidate`, each taking 2-3s over network while terminal cursor blinks quietly.
- **Architecture Fix:** Parallelize git fetch calls using background jobs (`&` and `wait`) and apply a short TTL cooldown so back-to-back syncs finish in 0.05s.

### Finding 5: Settings Skills Description & Step Header Polish
- **Location:** `haws.sh:4901` (`settings_page`) and `haws.sh:2185` (`run_sync`).
- **Problem:**
  - `skills_detail` shows `26 disabled` without context.
  - Step results print `[PASS] Step 1:` repeating "Step" from the header.
- **Architecture Fix:**
  - Format skills description dynamically: `[ 126 active · 26 disabled ]` or `[ All active ] - All active by default`.
  - Remove `Step X:` prefix from `[PASS]` lines.
