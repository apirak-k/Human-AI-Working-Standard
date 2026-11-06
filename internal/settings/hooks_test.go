package settings

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func gitHooksFixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := fixtureRepo(t)
	hook := filepath.Join(root, ".githooks", "commit-msg")
	fixtureFile(t, hook, "#!/bin/sh\nexit 0\n")
	if err := os.Chmod(hook, 0o755); err != nil {
		t.Fatal(err)
	}
	fixtureGit(t, root, "config", "--local", "core.hooksPath", "unused-test-hooks")
	fixtureGit(t, root, "add", ".githooks/commit-msg")
	fixtureGit(t, root, "commit", "-m", "add advisory hook")
	fixtureGit(t, root, "config", "--local", "--unset-all", "core.hooksPath")
	return root, filepath.Join(root, ".haws", "state"), hook
}

func TestSyncGitHooksInstallsOwnershipAndIsIdempotent(t *testing.T) {
	root, stateDir, _ := gitHooksFixture(t)
	first, err := SyncGitHooks(context.Background(), root, stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	if !first.Configured || !first.Updated || first.Adopted || first.Preserved {
		t.Fatalf("initial hook result = %+v", first)
	}
	if got := fixtureGit(t, root, "status", "--porcelain=v1", "--", ".githooks/commit-msg"); got != "" {
		t.Fatalf("install dirtied the tracked hook file: %q", got)
	}
	if got := fixtureGit(t, root, "config", "--local", "--get-all", "core.hooksPath"); got != ".githooks" {
		t.Fatalf("core.hooksPath = %q; want .githooks", got)
	}
	ledger, err := os.ReadFile(filepath.Join(stateDir, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), "hooks\tgit-config\t"+filepath.Join(root, ".githooks")+"\t__HAWS_UNSET__\t.githooks\tschema=2") {
		t.Fatalf("hook ownership = %q, %v", ledger, err)
	}
	status, err := GitHooksStatus(context.Background(), root)
	if err != nil || !strings.Contains(status, "Status: [ACTIVE & ADVISORY]") {
		t.Fatalf("hook status = %q, %v", status, err)
	}

	repeated, err := SyncGitHooks(context.Background(), root, stateDir, false)
	if err != nil {
		t.Fatal(err)
	}
	if !repeated.Configured || !repeated.Skipped || repeated.Updated {
		t.Fatalf("repeat hook result = %+v", repeated)
	}
	after, err := os.ReadFile(filepath.Join(stateDir, "ownership.tsv"))
	if err != nil || string(after) != string(ledger) {
		t.Fatalf("repeat hook ownership changed = %q, %v", after, err)
	}
}

func TestSyncGitHooksPreservesUnownedConfiguration(t *testing.T) {
	for _, tc := range []struct {
		name string
		path string
	}{
		{name: "custom path", path: "custom-hooks"},
		{name: "unowned HAWS path", path: ".githooks"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root, stateDir, _ := gitHooksFixture(t)
			fixtureGit(t, root, "config", "--local", "core.hooksPath", tc.path)
			result, err := SyncGitHooks(context.Background(), root, stateDir, false)
			if err != nil || !result.Preserved || result.Updated || result.Adopted {
				t.Fatalf("unowned hooks result = %+v, %v", result, err)
			}
			if got := fixtureGit(t, root, "config", "--local", "--get-all", "core.hooksPath"); got != tc.path {
				t.Fatalf("core.hooksPath changed = %q; want %q", got, tc.path)
			}
			if _, err := os.Stat(filepath.Join(stateDir, "ownership.tsv")); !os.IsNotExist(err) {
				t.Fatalf("unowned hooks created ownership ledger: %v", err)
			}
		})
	}
}

func TestSyncGitHooksAdoptsOnlyExactTrackedLegacyHook(t *testing.T) {
	t.Run("exact tracked hook", func(t *testing.T) {
		root, stateDir, _ := gitHooksFixture(t)
		fixtureGit(t, root, "config", "--local", "core.hooksPath", ".githooks")
		result, err := SyncGitHooks(context.Background(), root, stateDir, true)
		if err != nil || !result.Configured || !result.Adopted || result.Updated {
			t.Fatalf("legacy hook adoption = %+v, %v", result, err)
		}
		if _, err := os.Stat(filepath.Join(stateDir, "ownership.tsv")); err != nil {
			t.Fatalf("adopted hook ownership missing: %v", err)
		}
	})

	t.Run("modified tracked hook", func(t *testing.T) {
		root, stateDir, hook := gitHooksFixture(t)
		fixtureGit(t, root, "config", "--local", "core.hooksPath", ".githooks")
		if err := os.WriteFile(hook, []byte("#!/bin/sh\n# changed after commit\nexit 0\n"), 0o755); err != nil {
			t.Fatal(err)
		}
		result, err := SyncGitHooks(context.Background(), root, stateDir, true)
		if err != nil || !result.Preserved || result.Adopted {
			t.Fatalf("modified hook adoption = %+v, %v", result, err)
		}
		if _, err := os.Stat(filepath.Join(stateDir, "ownership.tsv")); !os.IsNotExist(err) {
			t.Fatalf("modified hook created ownership ledger: %v", err)
		}
	})
}

func TestSyncGitHooksRejectsInvalidLedgerBeforeChangingGitConfig(t *testing.T) {
	root, stateDir, _ := gitHooksFixture(t)
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(stateDir, "ownership.tsv"), 0o700); err != nil {
		t.Fatal(err)
	}
	if _, err := SyncGitHooks(context.Background(), root, stateDir, false); err == nil {
		t.Fatal("invalid ownership ledger was accepted")
	}
	if _, err := fixtureGitOutput(t, root, "config", "--local", "--get-all", "core.hooksPath"); err == nil {
		t.Fatal("Git hook configuration changed after invalid-ledger failure")
	}
}

func TestSyncGitHooksRequiresRepositoryRoot(t *testing.T) {
	parent := fixtureRepo(t)
	nested := filepath.Join(parent, "nested")
	hook := filepath.Join(nested, ".githooks", "commit-msg")
	fixtureFile(t, hook, "#!/bin/sh\nexit 0\n")
	stateDir := filepath.Join(nested, ".haws", "state")
	if _, err := SyncGitHooks(context.Background(), nested, stateDir, false); err == nil {
		t.Fatal("hook setup accepted a subdirectory of another Git checkout")
	}
	if _, err := fixtureGitOutput(t, parent, "config", "--local", "--get-all", "core.hooksPath"); err == nil {
		t.Fatal("hook setup changed the enclosing repository configuration")
	}
}

func TestSyncGitHooksRollsBackConfigWhenOwnershipCannotBeRecorded(t *testing.T) {
	root, stateDir, _ := gitHooksFixture(t)
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	ledgerPath := filepath.Join(stateDir, "ownership.tsv")
	if err := os.WriteFile(ledgerPath, []byte(strings.Repeat("x", maxSkillOwnershipBytes)), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := SyncGitHooks(context.Background(), root, stateDir, false); err == nil || !strings.Contains(err.Error(), "ownership ledger exceeds size limit") {
		t.Fatal("ownership ledger overflow was written")
	}
	if _, err := fixtureGitOutput(t, root, "config", "--local", "--get-all", "core.hooksPath"); err == nil {
		t.Fatal("Git hook configuration was not rolled back after ownership failure")
	}
}
