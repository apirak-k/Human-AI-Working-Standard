# HAWS CLI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the command-first monolithic HAWS shell script with one safe, interactive, cross-platform `haws.sh` entry point for Settings, Sync, Status, Doctor, and ownership-aware Uninstall.

**Architecture:** Keep `haws.sh` as a small dispatcher and source focused Bash modules from `runtime/`. Store device-local settings, ownership, sync results, and the sync lock under the Git-ignored `.haws/state/` directory, while preserving `ai-configs/environments.disabled` as the compatibility source for AI selections. Drive all mutations through explicit plan/apply functions so interactive screens and direct commands share the same behavior and the test suite can run against isolated fixture homes and repositories.

**Tech Stack:** Bash 3.2-compatible shell, Git, existing Node.js Codex adapter scripts where selected, and a dependency-free Bash integration-test harness.

**Spec:** `docs/superpowers/specs/2026-09-09-haws-cli-design.md`

## Global Constraints

- `haws.sh` is the only user-facing launcher on Windows through Git Bash, macOS, and Linux.
- A bare `haws.sh` invocation must never sync automatically.
- Settings begin with useful defaults; a default selection never performs an action until `Save & Apply`.
- `ai-configs/` remains limited to per-AI adapters, links, and registration compatibility.
- External sources containing `SKILL.md` remain under `skills/`; agent-specific skill compatibility is deferred.
- `.gitmodules` remains the versioned source registry and must preserve the user's selected source set.
- Second Brain stays private and separate; disabling it never contacts its remote or deletes local files.
- Status and Doctor are read-only and make no remote requests.
- Sync never overwrites a source with staged, unstaged, or untracked changes, and one target failure does not stop unrelated targets.
- Dependencies introduced by an update are reported and never installed silently.
- No setup, sync, Second Brain sync, or remote push may be run merely for inspection or plan verification.
- README and `HANDOFF.md` relocation are deferred until the product flow and all references are stable.

## File Map

| Path | Change | Responsibility |
|---|---|---|
| `haws.sh` | Rewrite | Resolve the repository root, source runtime modules, parse direct commands, and open First Install Settings or Home. |
| `runtime/platform.sh` | Create | Portable path, link, atomic-file, clock, timeout, process, and terminal capability helpers; isolate Windows Git Bash differences. |
| `runtime/state.sh` | Create | Read/write/migrate `.haws/state/`, `skills/skills.disabled`, and `ai-configs/environments.disabled`; expose settings, sync result, lock, and ownership APIs. |
| `runtime/catalog.sh` | Create | Read `.gitmodules`, discover `SKILL.md` entrypoints, retain source provenance, and calculate active/disabled source and skill sets. |
| `runtime/ui.sh` | Create | Arrow-key menus, multi-select with Space/A/C/Enter, explicit On/Off fields, review screens, Home, and non-TTY failure messages. |
| `runtime/settings.sh` | Create | Defaults, editable draft settings, change planning, `Save & Apply`, first-install orchestration, and later local reconfiguration. |
| `runtime/integrations.sh` | Create | Plan/apply AI pointers, skill links, agent profiles, and hooks; record every created or adopted artifact in ownership state. |
| `runtime/operations.sh` | Create | Per-target Sync orchestration, guarded source updates, Second Brain sync adapter, link refresh, and Uninstall preview/apply/report. |
| `runtime/health.sh` | Create | Shared Ready/Attention/Blocked classification, local Status, detailed Status, and read-only Doctor findings. |
| `.gitignore` | Modify | Ignore `/.haws/state/` and `skills/skills.disabled`; retain all existing `environments.disabled` ignore rules. |
| `.gitattributes` | Modify | Remove the obsolete special treatment for `.bat` after wrappers are retired; retain LF enforcement for shell and documentation files. |
| `skills/skills.disabled` | Remove from index | Convert the currently tracked selection into device-local state without deleting the current device's working copy during migration. |
| `SETUP.bat` | Delete | Retire the Windows-only setup wrapper after launcher parity tests pass. |
| `1-CLICK-SYNC.bat` | Delete | Retire the Windows-only sync wrapper after direct and interactive flow parity tests pass. |
| `.githooks/pre-commit` | Modify | Call the new read-only Doctor path and the CLI integration suite without allowing Doctor to repair Git configuration. |
| `.githooks/commit-msg` | Keep | No CLI behavior change is required. |
| `.githooks/pre-push` | Keep | Preserve the human push-authorization guardrail. |
| `ai-configs/claude/CLAUDE.md.template` | Modify | Keep only the Claude registration/pointer needed to reach canonical HAWS and Second Brain sources. |
| `ai-configs/gemini/GEMINI.md.template` | Modify | Keep only the Gemini/Antigravity registration/pointer needed to reach canonical sources. |
| `ai-configs/cursor/haws.mdc.template` | Modify | Keep only the Cursor registration/pointer and adapter metadata. |
| `ai-configs/copilot/copilot-instructions.md.template` | Modify | Keep only the Copilot registration/pointer and adapter metadata. |
| `ai-configs/codex/AGENTS.override.md.template` | Modify | Keep only the Codex registration/pointer and adapter metadata. |
| `ai-configs/codex/agents.mjs` | Keep behind adapter boundary | Invoke only when Codex is selected; preserve its existing ownership manifest behavior until converted through the integration API. |
| `ai-configs/codex/skills.mjs` | Keep behind adapter boundary | Generate the special Codex adapter only when required by the selected source. |
| `tests/cli/test_helper.sh` | Create | Make isolated repository/home fixtures, fake Git/network commands, capture output, and assert files, calls, and exit codes. |
| `tests/cli/state_test.sh` | Create | Verify defaults, migrations, atomic state writes, local selection preservation, ownership, and lock recovery. |
| `tests/cli/first_install_test.sh` | Create | Verify bare-launch First Install Settings and the Save & Apply sequence. |
| `tests/cli/settings_test.sh` | Create | Verify defaults, cancellation, changed selections, source download boundaries, and no unrelated updates. |
| `tests/cli/sync_test.sh` | Create | Verify settings-controlled targets, locking, dirty-source isolation, validation rollback, inactive-only changes, and per-target results. |
| `tests/cli/status_doctor_test.sh` | Create | Verify local-only Status, shared classification, actionable Doctor findings, and zero mutation/network calls. |
| `tests/cli/uninstall_test.sh` | Create | Verify preview, selected groups, ownership checks, modified/shared preservation, exact reports, and source deletion opt-in. |
| `tests/cli/cross_platform_test.sh` | Create | Exercise Linux/macOS/Windows-Git-Bash platform branches with fake platform commands and ensure no `.bat` dependency. |
| `tests/cli/run.sh` | Create | Run every CLI integration test with deterministic cleanup and aggregate exit status. |

## State Contracts

All records use UTF-8, LF endings, tab-separated fields, percent-escaped tabs/newlines, and atomic `write temporary -> fsync where available -> rename` replacement. Paths are stored as canonical absolute paths only after the target has been created or verified.

```text
.haws/state/
├── settings.tsv       key<TAB>value
├── sync-state.tsv     target<TAB>result<TAB>timestamp<TAB>revision<TAB>detail
├── ownership.tsv      group<TAB>kind<TAB>path<TAB>source<TAB>fingerprint
├── install.complete   schema=1<TAB>completed_at=<UTC timestamp>
└── sync.lock/          owner.tsv containing pid, started_at, and command
```

Required settings keys are `schema=1`, `second_brain=off`, and `auto_update=on`. The source selection is `.gitmodules`; disabled skills remain in the ignored `skills/skills.disabled`; disabled environments remain in the ignored `ai-configs/environments.disabled`. Empty or absent disabled files mean all discovered skills or all detected AI environments are active.

Ownership kinds are `symlink`, `hardlink`, `generated-file`, `managed-block`, `json-entry`, and `git-config`. For `git-config`, the source field records the previous value or the sentinel `absent`, while the fingerprint field records the HAWS-installed value. Uninstall may remove or restore an item only when the current artifact still matches its recorded target or fingerprint. A mismatch becomes `Preserved: modified or ownership unproven`.

## Migration Sequence from the Existing `haws.sh`

1. Add the isolated test harness and state compatibility tests around the existing paths without invoking live user integrations.
2. Add `platform.sh` and `state.sh`; migrate `.haws_manifest` entries into `ownership.tsv` only after validating each live artifact, and preserve existing disabled-environment and disabled-skill files byte-for-byte until the user saves Settings.
3. Extract catalog discovery and provenance from the existing skill/submodule functions without changing source selection.
4. Add the shared integration plan/apply boundary and make the legacy sync path call it, keeping existing adapters usable during transition.
5. Replace legacy Status and Doctor with read-only health functions; remove Doctor's current implicit `core.hooksPath` repair.
6. Implement Settings and First Install; switch the bare command from implicit sync to Settings/Home only after first-launch tests pass.
7. Replace sync orchestration with lock, eligibility, dirty-tree, candidate-validation, and per-target-result safeguards.
8. Replace uninstall with ownership-based preview and selective removal; keep the direct `haws.sh uninstall` command.
9. Remove unreachable legacy functions and the broken `notify` dispatch rather than creating a speculative root `tools/` directory.
10. Run cross-platform launcher tests, then delete both `.bat` wrappers and remove their `.gitattributes` rule.

### Task 1: Freeze Current Contracts in an Isolated CLI Harness

**Files:**
- Create: `tests/cli/test_helper.sh`
- Create: `tests/cli/run.sh`
- Create: `tests/cli/state_test.sh`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `new_fixture`, `run_haws`, `assert_status`, `assert_output_contains`, `assert_file_contains`, `assert_no_call`, and fixture variables `FIXTURE_REPO`, `FIXTURE_HOME`, `FAKE_BIN`.

- [ ] **Step 1: Add a dependency-free fixture harness**

```bash
new_fixture() {
  FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/haws-cli.XXXXXX")"
  FIXTURE_REPO="${FIXTURE_ROOT}/repo"
  FIXTURE_HOME="${FIXTURE_ROOT}/home"
  FAKE_BIN="${FIXTURE_ROOT}/bin"
  mkdir -p "$FIXTURE_REPO" "$FIXTURE_HOME" "$FAKE_BIN"
}

run_haws() {
  env HOME="$FIXTURE_HOME" HAWS_REPO_DIR="$FIXTURE_REPO" \
    PATH="$FAKE_BIN:$PATH" bash "$PROJECT_ROOT/haws.sh" "$@"
}
```

- [ ] **Step 2: Write failing compatibility tests** for absent/empty disabled files, existing disabled values, the legacy `.haws_manifest` input, and the new ignored state paths.

```bash
test_empty_disabled_environment_file_means_all_enabled
test_existing_disabled_environment_file_is_not_overwritten_by_migration
test_existing_disabled_skill_file_is_not_overwritten_by_migration
test_valid_legacy_manifest_entries_can_be_migrated
test_haws_state_and_skill_selection_are_git_ignored
```

- [ ] **Step 3: Run the focused test and confirm it fails before state APIs exist**

Run: `bash tests/cli/state_test.sh`

Expected: non-zero exit with missing state API/module assertions; no file outside the fixture changes.

- [ ] **Step 4: Add `/.haws/state/` and `skills/skills.disabled` to `.gitignore`** while retaining `ai-configs/environments.disabled`, `config/environments.disabled`, and root `environments.disabled` compatibility ignores.

- [ ] **Step 5: Run shell syntax checks**

Run: `bash -n tests/cli/test_helper.sh tests/cli/run.sh tests/cli/state_test.sh`

Expected: exit 0.

- [ ] **Step 6: Commit the harness and ignore contract**

```bash
git add .gitignore tests/cli/test_helper.sh tests/cli/run.sh tests/cli/state_test.sh
git commit -m "test(cli): add isolated HAWS state harness"
```

### Task 2: Introduce Portable Platform and Device-Local State Modules

**Files:**
- Create: `runtime/platform.sh`
- Create: `runtime/state.sh`
- Modify: `haws.sh`
- Remove from index: `skills/skills.disabled`
- Test: `tests/cli/state_test.sh`

**Interfaces:**
- Produces: `platform_id`, `canonical_path PATH`, `atomic_replace SOURCE DESTINATION`, `create_managed_link SOURCE DESTINATION`, `state_init`, `settings_load`, `settings_save`, `disabled_envs_load`, `disabled_envs_save`, `disabled_skills_load`, `disabled_skills_save`, `ownership_record GROUP KIND PATH SOURCE FINGERPRINT`, `ownership_list [GROUP]`, `sync_lock_acquire`, and `sync_lock_release`.

- [ ] **Step 1: Extend failing state tests** for atomic replacement, default settings, stale/live lock behavior, ownership round trips, and exact preservation of existing local selection files.

```bash
test_settings_defaults_are_second_brain_off_and_auto_update_on
test_settings_write_replaces_complete_record_atomically
test_live_sync_lock_blocks_second_owner
test_stale_lock_is_reported_and_recoverable_without_remote_work
test_ownership_round_trip_preserves_spaces_in_paths
test_first_state_init_preserves_environment_disabled_bytes
```

- [ ] **Step 2: Implement platform helpers without separate platform workflows**

```bash
platform_id() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo windows-git-bash;; Darwin*) echo macos;; *) echo linux;; esac; }
```

Windows link creation may use `cmd.exe /c mklink` internally; macOS/Linux use `ln`. Both return the same ownership kind and canonical source, and neither silently overwrites an unrelated destination.

- [ ] **Step 3: Implement state initialization and schema validation** so missing files receive defaults, existing compatibility files are read without rewrite, and malformed state returns `Blocked` with a concrete recovery action.

- [ ] **Step 4: Migrate `.haws_manifest` conservatively**

For each legacy `skill:<name>` or `agent:<name>`, locate the known destination, prove it resolves to a path in this HAWS checkout or matches generated content, then record it. Leave unverifiable entries unowned and report them; do not delete `.haws_manifest` until the ownership file has been atomically committed.

- [ ] **Step 5: Stop tracking `skills/skills.disabled` while leaving the working copy intact**

Run during implementation: `git rm --cached skills/skills.disabled`

Expected: the current device keeps its file and selections; new clones start with all discovered skills active.

- [ ] **Step 6: Run state tests**

Run: `bash tests/cli/state_test.sh`

Expected: all tests pass without reading or writing the real home directory.

- [ ] **Step 7: Commit the state boundary**

```bash
git add haws.sh runtime/platform.sh runtime/state.sh tests/cli/state_test.sh .gitignore
git add -u skills/skills.disabled
git commit -m "refactor(cli): add portable local state boundary"
```

### Task 3: Extract Source and Skill Catalog with Provenance

**Files:**
- Create: `runtime/catalog.sh`
- Create: `tests/cli/catalog_test.sh`
- Modify: `tests/cli/run.sh`
- Modify: `haws.sh`

**Interfaces:**
- Produces: `catalog_sources` as `source_id<TAB>path<TAB>url<TAB>revision`, `catalog_skills` as `skill_id<TAB>display_name<TAB>source_id<TAB>entrypoint<TAB>active`, `source_has_active_skills SOURCE_ID`, and `changed_paths_affect_active_skills SOURCE_ID OLD_REV NEW_REV`.

- [ ] **Step 1: Write failing catalog tests**

```bash
test_gitmodules_is_the_only_versioned_source_registry
test_skill_requires_nonempty_skill_md_entrypoint
test_duplicate_names_remain_distinct_by_source_id
test_absent_disabled_file_enables_every_discovered_skill
test_source_with_no_active_skills_is_ineligible
test_changed_paths_classify_inactive_only_update
```

- [ ] **Step 2: Implement stable identifiers**

Use `.gitmodules` subsection name plus repository-relative path as `source_id`; use `source_id::relative-entrypoint` as `skill_id`. Display names remain metadata and never serve as the unique ownership key.

- [ ] **Step 3: Move discovery logic** from `extract_skill_name`, `.gitmodules` iteration, and current `find ... SKILL.md` loops into the catalog module. Do not add support for nonstandard agent-specific entrypoints.

- [ ] **Step 4: Run tests and syntax checks**

Run: `bash tests/cli/catalog_test.sh && bash -n haws.sh runtime/*.sh tests/cli/*.sh`

Expected: exit 0.

- [ ] **Step 5: Commit the catalog boundary**

```bash
git add haws.sh runtime/catalog.sh tests/cli/catalog_test.sh tests/cli/run.sh
git commit -m "refactor(cli): extract source and skill catalog"
```

### Task 4: Add Shared UI and Settings Plan/Apply Flow

**Files:**
- Create: `runtime/ui.sh`
- Create: `runtime/settings.sh`
- Create: `runtime/integrations.sh`
- Modify: `ai-configs/claude/CLAUDE.md.template`
- Modify: `ai-configs/gemini/GEMINI.md.template`
- Modify: `ai-configs/cursor/haws.mdc.template`
- Modify: `ai-configs/copilot/copilot-instructions.md.template`
- Modify: `ai-configs/codex/AGENTS.override.md.template`
- Create: `tests/cli/first_install_test.sh`
- Create: `tests/cli/settings_test.sh`
- Modify: `tests/cli/run.sh`
- Modify: `haws.sh`

**Interfaces:**
- Produces: `ui_menu TITLE ITEMS...`, `ui_checklist TITLE ITEM_RECORDS...`, `ui_boolean TITLE VALUE`, `settings_defaults`, `settings_edit`, `settings_plan_apply`, `settings_apply PLAN_FILE`, `integration_plan OLD_SELECTION NEW_SELECTION`, and `integration_apply PLAN_FILE`.
- Checklist item record: `id<TAB>label<TAB>detail<TAB>selected`; result: selected IDs, one per line.
- Apply plan record: `action<TAB>group<TAB>source<TAB>destination<TAB>reason`.

- [ ] **Step 1: Write failing First Install tests**

```bash
test_bare_first_launch_opens_default_populated_settings_without_git_calls
test_default_setup_only_resets_the_draft
test_cancel_leaves_state_and_integrations_unchanged
test_first_save_apply_downloads_only_selected_missing_sources
test_first_save_apply_configures_only_selected_environments
test_first_save_apply_runs_doctor_then_reaches_home
```

- [ ] **Step 2: Write failing later Settings tests**

```bash
test_home_contains_status_sync_settings_doctor_details_and_exit
test_checklist_supports_space_select_all_clear_all_and_enter
test_boolean_requires_explicit_on_or_off
test_review_precedes_every_mutation
test_later_save_apply_refreshes_only_changed_selections
test_later_save_apply_does_not_fetch_existing_sources
test_uninstall_is_visible_only_after_install_complete
test_adapter_templates_reference_canonical_rules_without_duplicating_them
```

- [ ] **Step 3: Implement terminal input with injectable keys** using `HAWS_TEST_KEYS` only in tests. Production reads `/dev/tty`; a noninteractive bare launch prints direct-command help and exits without mutation.

- [ ] **Step 4: Implement draft Settings** in memory. `Default Setup` resets the draft to all detected environments, all discovered skills, Second Brain Off, and Auto Update On. Only `Save & Apply` writes local state or invokes an integration/source action.

- [ ] **Step 5: Implement integration planning and ownership recording**. Existing matching user artifacts may be adopted only after exact target/content verification; conflicts are preserved and reported as Blocked. Write ownership only after successful creation.

- [ ] **Step 6: Reduce AI templates to adapter pointers**. Each template identifies its AI-specific registration target and points to `core/HAWS.md`, `core/WORK_INSTRUCTIONS.md`, and the Second Brain sources. Remove copied engineering rules from templates so rule changes have one canonical source; do not alter skill discovery conventions or solve deferred agent-specific compatibility.

- [ ] **Step 7: Switch bare invocation safely**

```bash
if install_is_complete; then
  home_run
else
  settings_run first-install
fi
```

Keep `haws.sh sync`, `status`, `status --details`, `doctor`, and `uninstall` direct commands.

- [ ] **Step 8: Run First Install and Settings tests**

Run: `bash tests/cli/first_install_test.sh && bash tests/cli/settings_test.sh`

Expected: all pass; fake Git log contains only selected missing-source initialization calls.

- [ ] **Step 9: Commit the interactive shell**

```bash
git add haws.sh runtime/ui.sh runtime/settings.sh runtime/integrations.sh ai-configs tests/cli
git commit -m "feat(cli): add safe Settings and Home flows"
```

### Task 5: Replace Sync with Guarded Per-Target Operations

**Files:**
- Create: `runtime/operations.sh`
- Create: `tests/cli/sync_test.sh`
- Modify: `runtime/integrations.sh`
- Modify: `haws.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Produces: `sync_run`, `sync_target TARGET_ID`, `source_preflight SOURCE_ID`, `source_fetch_candidate SOURCE_ID`, `source_validate_candidate SOURCE_ID REVISION`, `source_activate_candidate SOURCE_ID REVISION`, `second_brain_sync`, and `sync_result_write TARGET RESULT REVISION DETAIL`.
- Result values: `Updated`, `Up to date`, `Skipped: no active skills`, `Skipped: inactive skills only changed`, `Offline / timeout`, `Blocked: local changes`, `Failed: validation`, `Disabled`, and `Needs resolution`.

- [ ] **Step 1: Write failing target-control and lock tests**

```bash
test_both_remote_settings_off_makes_no_network_request
test_second_brain_off_never_calls_its_git_remote
test_auto_update_off_never_fetches_haws_or_sources
test_concurrent_sync_reports_already_running
test_lock_is_released_on_success_failure_and_interrupt
```

- [ ] **Step 2: Write failing source-safety tests**

```bash
test_dirty_source_is_blocked_while_other_targets_continue
test_untracked_file_blocks_only_its_source
test_source_with_no_active_skills_is_skipped
test_inactive_only_candidate_is_not_activated
test_invalid_active_skill_candidate_keeps_previous_revision
test_new_dependency_is_reported_without_install
test_timeout_is_recorded_per_target_and_other_targets_continue
test_links_refresh_only_after_relevant_update_or_selection_change
```

- [ ] **Step 3: Implement lock ownership and traps**. Use atomic `mkdir sync.lock`; record PID and timestamp; release only a lock owned by the current process. A stale lock requires a visible recovery action or explicit `sync --recover-lock`, never silent deletion.

- [ ] **Step 4: Fetch candidates without changing active worktrees**. Resolve remote revisions into temporary refs or detached validation worktrees under `.haws/state/tmp/`; validate active entrypoints and inspect dependency metadata before fast-forward activation. Always remove temporary validation state through a trap.

- [ ] **Step 5: Implement relevance checks** by diffing old/candidate revisions and mapping changed paths to active entrypoints plus source-shared files. If only inactive skills changed, retain the active revision and record the exact skipped result.

- [ ] **Step 6: Isolate Second Brain results**. Merge stable records as chronological union; mark incompatible edits to one logical record `Needs resolution`, continue unrelated records and targets, and never delete local notes when disabled.

- [ ] **Step 7: Run Sync tests**

Run: `bash tests/cli/sync_test.sh`

Expected: all pass; no fixture with local changes changes revision; no test invokes a real remote.

- [ ] **Step 8: Commit guarded Sync**

```bash
git add haws.sh runtime/operations.sh runtime/integrations.sh tests/cli/sync_test.sh tests/cli/run.sh
git commit -m "feat(cli): add guarded per-target sync"
```

### Task 6: Implement Shared Read-Only Status and Doctor

**Files:**
- Create: `runtime/health.sh`
- Create: `tests/cli/status_doctor_test.sh`
- Modify: `.githooks/pre-commit`
- Modify: `haws.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Produces: `health_classify FINDINGS`, `status_run [--details]`, `doctor_run`, and finding records `level<TAB>item<TAB>cause<TAB>action`.
- Level values: `Ready`, `Attention`, and `Blocked`.

- [ ] **Step 1: Write failing Status tests**

```bash
test_status_reads_local_configuration_and_recorded_sync_only
test_status_never_invokes_fetch_pull_ls_remote_or_network_stub
test_status_distinguishes_last_sync_record_from_current_local_health
test_status_details_lists_each_selected_environment_source_and_skill
test_status_shows_active_disabled_source_counts_and_actions
```

- [ ] **Step 2: Write failing Doctor tests**

```bash
test_doctor_checks_only_enabled_components
test_doctor_reports_level_item_cause_and_action
test_doctor_does_not_set_core_hooks_path
test_doctor_does_not_link_repair_sync_or_install
test_doctor_checks_ownership_needed_for_safe_uninstall
test_doctor_and_status_use_identical_overall_classification
```

- [ ] **Step 3: Extract health checks** from the old `run_status` and `run_doctor`, removing count-only proof and all mutations. In particular, replace the existing Doctor behavior that sets `core.hooksPath` with an Attention finding and `haws.sh settings` action.

- [ ] **Step 4: Update pre-commit** to call `bash haws.sh doctor` as a read-only gate plus `bash tests/cli/run.sh`; keep the secret and LF checks. Do not install hooks or modify Git config from the hook.

- [ ] **Step 5: Run health tests and a Git-config immutability check**

Run: `bash tests/cli/status_doctor_test.sh`

Expected: all pass and fixture `.git/config` hash is unchanged before/after both commands.

- [ ] **Step 6: Commit health reporting**

```bash
git add haws.sh runtime/health.sh .githooks/pre-commit tests/cli/status_doctor_test.sh tests/cli/run.sh
git commit -m "feat(cli): add read-only status and doctor"
```

### Task 7: Replace Uninstall with Ownership-Aware Preview and Apply

**Files:**
- Modify: `runtime/operations.sh`
- Modify: `runtime/integrations.sh`
- Create: `tests/cli/uninstall_test.sh`
- Modify: `haws.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Produces: `uninstall_plan SELECTED_GROUPS`, `uninstall_preview PLAN_FILE`, `uninstall_apply PLAN_FILE`, `ownership_verify RECORD`, and report records `Removed|Preserved<TAB>path<TAB>reason`.

- [ ] **Step 1: Write failing Uninstall tests**

```bash
test_uninstall_preview_is_exact_and_nonmutating
test_default_groups_include_pointers_skills_agents_hooks_and_metadata
test_user_can_deselect_each_group
test_matching_owned_link_is_removed
test_modified_generated_file_is_preserved
test_shared_or_unproven_target_is_preserved
test_repo_sources_second_brain_and_remote_config_are_preserved_by_default
test_selected_removal_is_verified_after_apply
test_downloaded_source_deletion_requires_separate_exact_selection
test_direct_uninstall_uses_same_preview_confirm_apply_path
test_hook_uninstall_restores_previous_core_hooks_path
test_hook_ownership_works_when_dot_git_is_a_worktree_file
test_one_codex_profile_conflict_does_not_abort_other_uninstall_groups
```

- [ ] **Step 2: Implement ownership verification by kind**. Symlinks compare canonical targets; hardlinks compare file identity; generated files compare SHA-256 fingerprints; managed blocks remove only HAWS markers; JSON entries remove only exact recorded paths. Git config is restored to its recorded previous value, or unset when the previous value was `absent`, only if its current value still equals the HAWS-installed value. Detect a Git repository through `git rev-parse --git-dir`, not `[ -d .git ]`, so linked worktrees are supported.

- [ ] **Step 3: Build the preview before confirmation** and list every path/action. Unsupported, modified, shared, and unproven items appear in the preserved section before apply.

- [ ] **Step 4: Apply selected groups and verify absence**. Remove ownership records only after the selected artifact is verified absent. Retain records and report failures when removal or verification fails.

Codex adapter conflicts are converted to per-item `Preserved` results; one conflicting profile must not abort pointer, skill, hook, or other environment cleanup.

- [ ] **Step 5: Keep source deletion separate** with an exact repository checklist and a second explicit confirmation. This destructive option is never preselected and is never part of direct default uninstall.

- [ ] **Step 6: Run Uninstall tests**

Run: `bash tests/cli/uninstall_test.sh`

Expected: all pass; fixture user-owned content and repositories are byte-identical after default uninstall.

- [ ] **Step 7: Commit safe Uninstall**

```bash
git add haws.sh runtime/operations.sh runtime/integrations.sh tests/cli/uninstall_test.sh tests/cli/run.sh
git commit -m "feat(cli): add ownership-aware uninstall"
```

### Task 8: Remove Legacy Paths and Retire Windows Batch Launchers

**Files:**
- Modify: `haws.sh`
- Delete: `SETUP.bat`
- Delete: `1-CLICK-SYNC.bat`
- Modify: `.gitattributes`
- Create: `tests/cli/cross_platform_test.sh`
- Modify: `tests/cli/run.sh`

**Interfaces:**
- Consumes: all runtime module APIs from Tasks 2-7.
- Produces: the final public command surface `haws.sh`, `haws.sh sync`, `haws.sh status [--details]`, `haws.sh doctor`, `haws.sh settings`, and `haws.sh uninstall`.

- [ ] **Step 1: Write failing cross-platform tests**

```bash
test_linux_uses_posix_links_and_same_command_surface
test_macos_uses_posix_links_and_same_command_surface
test_windows_git_bash_uses_platform_helper_and_same_command_surface
test_public_flow_has_no_bat_launcher_reference
test_bare_launcher_never_dispatches_sync
test_unknown_command_prints_current_commands_only
```

- [ ] **Step 2: Delete migrated legacy functions** from `haws.sh`, including old setup menus, direct `.gitmodules` editor flow, legacy clean-sync behavior, duplicate link implementations, automatic Second Brain commit/push behavior, and the missing `tools/notify.sh` command.

- [ ] **Step 3: Keep source selection inside Settings**. Adding or removing a source edits the Settings draft and applies a reviewed `.gitmodules` change; it does not open an editor and immediately run `git submodule sync`.

- [ ] **Step 4: Verify Bash invocation on all platform branches** using fake `uname`, `cmd.exe`, `cygpath`, and `ln` executables. On Windows the documented invocation is `bash haws.sh`; double-click `.bat` behavior is no longer part of the product.

- [ ] **Step 5: Delete `.bat` files only after parity tests pass**, then remove `*.bat text eol=crlf` and retain `*.cmd` only if a tracked `.cmd` file still needs it.

- [ ] **Step 6: Run the full suite and syntax validation**

Run: `bash tests/cli/run.sh && bash -n haws.sh runtime/*.sh .githooks/* tests/cli/*.sh`

Expected: exit 0 on every fixture; repository search finds no live reference to the deleted launchers outside historical design/plan material.

- [ ] **Step 7: Commit launcher retirement**

```bash
git add haws.sh runtime tests/cli .gitattributes
git add -u SETUP.bat 1-CLICK-SYNC.bat
git commit -m "refactor(cli): retire legacy launchers"
```

### Task 9: Acceptance Verification and Migration Audit

**Files:**
- Modify only if a test exposes a defect: files owned by Tasks 1-8
- Do not modify: `README.md`, skill content, agent-specific compatibility, or Second Brain content

**Interfaces:**
- Consumes: final public CLI and the isolated test harness.
- Produces: reproducible acceptance evidence for human review; no remote state.

- [ ] **Step 1: Run the complete integration suite from a clean fixture**

Run: `bash tests/cli/run.sh`

Expected: First Install, Settings, Sync, Status, Doctor, Uninstall, and platform suites all pass.

- [ ] **Step 2: Prove read-only commands are read-only**

Run the test helper's repository/home snapshot before and after `status`, `status --details`, and `doctor`.

Expected: identical file hashes, Git config, Git status, ownership state, and fake network-call log.

- [ ] **Step 3: Prove device-local environment preservation**

Seed `ai-configs/environments.disabled` with `cursor` and `codex`, run state migration and a canceled Settings session, and compare SHA-256 before/after. Then save an unrelated Auto Update change and confirm the environment file remains byte-identical.

- [ ] **Step 4: Prove migration from the legacy installation**

Seed validated `.haws_manifest` links plus one modified/unverifiable destination. Run migration, preview uninstall, and confirm only validated artifacts become owned while the unverifiable destination is preserved and reported.

- [ ] **Step 5: Prove no forbidden remote work occurred**

Inspect the fake Git log for the full suite. Expected: no `push`; no network command during bare launch, Settings cancellation, later local-only Save & Apply, Status, Doctor, or default Uninstall preview.

- [ ] **Step 6: Audit scope and references**

Run: `rg -n "SETUP\.bat|1-CLICK-SYNC\.bat|tools/notify\.sh|COMMAND=\"\$\{1:-sync\}\"" --glob '!docs/superpowers/**' .`

Expected: no live product references. Confirm `.gitmodules` entries and all pre-existing `ai-configs/` adapter files are still present.

- [ ] **Step 7: Review the final diff without pushing**

Run: `git status --short && git diff --check && git diff --stat`

Expected: only approved CLI redesign files are changed; no remote command is run. Present test evidence and migration limitations to the user for human acceptance before any integration or push decision.

## Plan Self-Review

- Spec coverage: First Install, Home, Settings defaults and controls, source/skill provenance, local state, ownership, sync locking and safeguards, Status, Doctor, Uninstall, device-local environment preservation, `.bat` retirement, and deferred scope each map to an implementation task and an acceptance test.
- Placeholder scan: the plan contains no deferred implementation placeholders; deferred product topics are explicitly excluded by the approved design specification.
- Interface consistency: state, catalog, UI, integration, operations, and health APIs are introduced before consumers; result and classification values match the design specification.
- Migration safety: no step runs live setup/sync/Second Brain sync for inspection, pushes a remote, deletes unproven user artifacts, or overwrites `ai-configs/environments.disabled` during migration.

## Approval Gate

This plan authorizes no implementation. After the user approves it, execute Task 1 onward in an isolated Git worktree, preserve unrelated working-tree changes, run only fixture-based migration tests until an explicit live test is agreed, and do not push any remote.
