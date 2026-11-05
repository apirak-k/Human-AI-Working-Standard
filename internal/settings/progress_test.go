package settings

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestSavePreservesUnchangedSelectionBytes(t *testing.T) {
	s := testStore(t)
	environment := filepath.Join(s.Root, "ai-configs", "environments.disabled")
	environmentData := "# user comments\r\n codex # disabled\r\nunknown-environment\r\n"
	skillData := "# skill comments\r\nmy-source::skill\r\nmy-source::skill\r\n"
	put(t, environment, environmentData)
	put(t, s.Path("skills.disabled"), skillData)
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	state.Config.AutoUpdateBrain = false
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	for path, want := range map[string]string{environment: environmentData, s.Path("skills.disabled"): skillData} {
		got, err := os.ReadFile(path)
		if err != nil || string(got) != want {
			t.Fatalf("untouched selection changed %s: %q, %v", path, got, err)
		}
	}
	got, err := s.Load()
	if err != nil || got.Config.AutoUpdateBrain {
		t.Fatalf("setting did not save: %+v, %v", got, err)
	}
}

func TestNewStoreReanchorsStateInsideTrustedRootAlias(t *testing.T) {
	s := testStore(t)
	aliasParent := t.TempDir()
	alias := filepath.Join(aliasParent, "checkout-alias")
	if err := os.Symlink(s.Root, alias); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_STATE_DIR", filepath.Join(alias, "isolated", "state"))
	aliased := NewStore(alias)
	if aliased.Dir != filepath.Join(s.Root, "isolated", "state") {
		t.Fatalf("state still uses root alias: %s", aliased.Dir)
	}
	if err := aliased.Save(State{Config: DefaultConfig()}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(s.Root, "isolated", "state", "settings.tsv")); err != nil {
		t.Fatal(err)
	}
	external := filepath.Join(aliasParent, "external-alias")
	if err := os.Symlink(s.Root, external); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_STATE_DIR", filepath.Join(external, "other-state"))
	if err := NewStore(alias).Save(State{Config: DefaultConfig()}); err == nil {
		t.Fatal("followed an unrelated state ancestor alias")
	}
}

func TestWriteProgressDoesNotMarkInstallationComplete(t *testing.T) {
	s := testStore(t)
	installed, err := s.InstallComplete()
	if err != nil || installed {
		t.Fatalf("fresh status: %v, %v", installed, err)
	}
	if _, err := os.Stat(s.Dir); !os.IsNotExist(err) {
		t.Fatal("status created state")
	}
	if err := s.WriteProgress("integration\tapply\n", "settings\tcompleted\nintegration\tpending\n"); err != nil {
		t.Fatal(err)
	}
	for name, want := range map[string]string{"settings.plan": "integration\tapply\n", "apply.result": "settings\tcompleted\nintegration\tpending\n"} {
		data, err := os.ReadFile(s.Path(name))
		if err != nil || string(data) != want {
			t.Fatalf("progress %s: %q, %v", name, data, err)
		}
	}
	installed, err = s.InstallComplete()
	if err != nil || installed {
		t.Fatalf("pending progress installed: %v, %v", installed, err)
	}
}

func TestWriteProgressFailurePreservesPreviousPair(t *testing.T) {
	s := testStore(t)
	if err := s.WriteProgress("old plan\n", "settings\tcompleted\n"); err != nil {
		t.Fatal(err)
	}
	private := filepath.Join(s.Root, "private-result")
	put(t, private, "private\n")
	if err := os.Remove(s.Path("apply.result")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(private, s.Path("apply.result")); err != nil {
		t.Fatal(err)
	}
	if err := s.WriteProgress("new plan\n", "settings\tpending\n"); err == nil {
		t.Fatal("progress followed symlink")
	}
	for path, want := range map[string]string{s.Path("settings.plan"): "old plan\n", private: "private\n"} {
		data, err := os.ReadFile(path)
		if err != nil || string(data) != want {
			t.Fatalf("failed progress changed %s", path)
		}
	}
}

func TestCompleteInstallRequiresCompletedProgress(t *testing.T) {
	for _, result := range []string{"", "settings\tcompleted\nrepository\tpending\nintegration\tcompleted\n", "settings\tcompleted\nbrain-connect\tpending\n", "settings\tcompleted\nintegration\tpending\n", "settings\tfailed\n", "malformed\n"} {
		t.Run(result, func(t *testing.T) {
			s := testStore(t)
			put(t, s.Path("uninstalled"), "schema=1\tuninstalled_at=2026-11-05T00:00:00Z\n")
			if result != "" {
				put(t, s.Path("apply.result"), result)
			}
			if err := s.CompleteInstall(); err == nil {
				t.Fatal("marked incomplete apply installed")
			}
			if _, err := os.Stat(s.Path("install.complete")); !os.IsNotExist(err) {
				t.Fatal("created install marker")
			}
			if _, err := os.Stat(s.Path("uninstalled")); err != nil {
				t.Fatal("removed uninstall marker")
			}
		})
	}
}

func TestCompleteInstallWritesCompatibleMarkersAndRemovesUninstalled(t *testing.T) {
	s := testStore(t)
	if err := s.WriteProgress("integration\tapply\n", "settings\tcompleted\nintegration\tcompleted\n"); err != nil {
		t.Fatal(err)
	}
	put(t, s.Path("uninstalled"), "schema=1\tuninstalled_at=2026-11-05T00:00:00Z\n")
	if err := s.CompleteInstall(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(s.Path("uninstalled")); !os.IsNotExist(err) {
		t.Fatal("kept uninstall marker")
	}
	for name, key := range map[string]string{"install.complete": "completed_at=", "integration-ownership-migration-v1": "migrated_at="} {
		data, err := os.ReadFile(s.Path(name))
		if err != nil {
			t.Fatal(err)
		}
		parts := strings.Split(strings.TrimSuffix(string(data), "\n"), "\t")
		if len(parts) != 2 || parts[0] != "schema=1" || !strings.HasPrefix(parts[1], key) {
			t.Fatalf("invalid marker %s: %q", name, data)
		}
		stamp := strings.TrimPrefix(parts[1], key)
		if _, err := time.Parse("2006-01-02T15:04:05Z", stamp); err != nil {
			t.Fatalf("invalid UTC timestamp: %q", stamp)
		}
	}
	installed, err := s.InstallComplete()
	if err != nil || !installed {
		t.Fatalf("completed status: %v, %v", installed, err)
	}
	put(t, s.Path("uninstalled"), "uninstalled\n")
	installed, err = s.InstallComplete()
	if err != nil || installed {
		t.Fatalf("uninstalled status: %v, %v", installed, err)
	}
}

func TestCompleteInstallRetainsExistingMigrationMarker(t *testing.T) {
	s := testStore(t)
	const marker = "schema=1\tmigrated_at=2024-01-02T03:04:05Z\n"
	put(t, s.Path("integration-ownership-migration-v1"), marker)
	if err := s.WriteProgress("settings\tapply\n", "settings\tcompleted\n"); err != nil {
		t.Fatal(err)
	}
	if err := s.CompleteInstall(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(s.Path("integration-ownership-migration-v1"))
	if err != nil || string(data) != marker {
		t.Fatal("replaced migration timestamp")
	}
}

func TestExistingInstallUpdatePreservesMissingOwnershipMigrationMarker(t *testing.T) {
	s := testStore(t)
	put(t, s.Path("install.complete"), "schema=1\tcompleted_at=2024-01-02T03:04:05Z\n")
	if err := s.WriteProgress("setting\tauto_update_skills\toff\n", "settings\tcompleted\n"); err != nil {
		t.Fatal(err)
	}
	if err := s.CompleteInstall(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(s.Path("integration-ownership-migration-v1")); !os.IsNotExist(err) {
		t.Fatalf("existing installation was marked ownership-migrated: %v", err)
	}
	installed, err := s.InstallComplete()
	if err != nil || !installed {
		t.Fatalf("updated installation: %v, %v", installed, err)
	}
}

func TestCompleteInstallRefusesUnsafeMarkers(t *testing.T) {
	for _, name := range []string{"uninstalled", "install.complete", "integration-ownership-migration-v1", "apply.result"} {
		t.Run(name, func(t *testing.T) {
			s := testStore(t)
			if err := s.WriteProgress("settings\tapply\n", "settings\tcompleted\n"); err != nil {
				t.Fatal(err)
			}
			private := filepath.Join(s.Root, "private-marker")
			put(t, private, "private\n")
			if err := os.Remove(s.Path(name)); err != nil && !os.IsNotExist(err) {
				t.Fatal(err)
			}
			if err := os.Symlink(private, s.Path(name)); err != nil {
				t.Fatal(err)
			}
			if err := s.CompleteInstall(); err == nil {
				t.Fatal("accepted symlink marker")
			}
			data, err := os.ReadFile(private)
			if err != nil || string(data) != "private\n" {
				t.Fatal("changed private marker")
			}
			if name == "uninstalled" || name == "install.complete" {
				if _, err := s.InstallComplete(); err == nil {
					t.Fatal("status followed unsafe marker")
				}
			}
		})
	}
	for _, value := range []string{"invalid\n", strings.Repeat("x", (1<<20)+1)} {
		s := testStore(t)
		put(t, s.Path("install.complete"), value)
		if _, err := s.InstallComplete(); err == nil {
			t.Fatal("accepted invalid install marker")
		}
	}
}

func TestProgressHonorsSyncLockAndSizeLimit(t *testing.T) {
	s := testStore(t)
	if err := s.WriteProgress("old plan\n", "settings\tcompleted\n"); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(s.Path("sync.lock"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := s.WriteProgress("new plan\n", "settings\tpending\n"); err == nil {
		t.Fatal("ignored sync lock")
	}
	if err := s.CompleteInstall(); err == nil {
		t.Fatal("completed install while locked")
	}
	if err := os.Remove(s.Path("sync.lock")); err != nil {
		t.Fatal(err)
	}
	if err := s.WriteProgress(strings.Repeat("x", (1<<20)+1), "settings\tcompleted\n"); err == nil {
		t.Fatal("accepted oversized plan")
	}
	data, err := os.ReadFile(s.Path("settings.plan"))
	if err != nil || string(data) != "old plan\n" {
		t.Fatal("failed progress changed plan")
	}
}

func TestCompleteIntegrationPreservesOtherPendingActionsAndMarkerState(t *testing.T) {
	s := testStore(t)
	const before = "settings\tcompleted\r\nbrain-connect\tpending\r\nintegration\tpending\r\nrepository\tpending"
	if err := s.WriteProgress("approved plan\n", before); err != nil {
		t.Fatal(err)
	}
	changed, err := s.CompleteIntegration()
	if err == nil || changed {
		t.Fatalf("integration completed before native actions: %v, %v", changed, err)
	}
	plan, result, err := s.ReadProgress()
	if err != nil || plan != "approved plan\n" || result != before {
		t.Fatalf("changed unrelated progress: %q, %q, %v", plan, result, err)
	}
	if _, err := os.Stat(s.Path("install.complete")); !os.IsNotExist(err) {
		t.Fatal("integration completion finalized installation")
	}
	if err := s.CompleteInstall(); err == nil {
		t.Fatal("pending actions allowed install completion")
	}
	if err := s.WriteProgress("approved plan\n", "settings\tcompleted\r\nintegration\tpending\r\n"); err != nil {
		t.Fatal(err)
	}
	changed, err = s.CompleteIntegration()
	if err != nil || !changed {
		t.Fatal(changed, err)
	}
	changed, err = s.CompleteIntegration()
	if err != nil || changed {
		t.Fatalf("repeated integration completion: %v, %v", changed, err)
	}
}

func TestCompleteIntegrationRefusesSymlinkedStateAncestor(t *testing.T) {
	s := testStore(t)
	outside, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	put(t, filepath.Join(outside, "apply.result"), "integration\tpending\n")
	if err := os.MkdirAll(filepath.Dir(s.Dir), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, s.Dir); err != nil {
		t.Fatal(err)
	}
	changed, err := s.CompleteIntegration()
	if err == nil || changed {
		t.Fatalf("followed state ancestor: %v, %v", changed, err)
	}
	data, err := os.ReadFile(filepath.Join(outside, "apply.result"))
	if err != nil || string(data) != "integration\tpending\n" {
		t.Fatal("modified external progress")
	}
}

func TestCompleteIntegrationHonorsLockAndRefusesSymlinkedResult(t *testing.T) {
	s := testStore(t)
	if err := s.WriteProgress("plan\n", "integration\tpending\n"); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(s.Path("sync.lock"), 0700); err != nil {
		t.Fatal(err)
	}
	if changed, err := s.CompleteIntegration(); err == nil || changed {
		t.Fatal("completed integration under another sync lock")
	}
	if err := os.Remove(s.Path("sync.lock")); err != nil {
		t.Fatal(err)
	}
	private := filepath.Join(s.Root, "private-progress")
	put(t, private, "integration\tpending\n")
	if err := os.Remove(s.Path("apply.result")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(private, s.Path("apply.result")); err != nil {
		t.Fatal(err)
	}
	if changed, err := s.CompleteIntegration(); err == nil || changed {
		t.Fatal("completed integration through result symlink")
	}
	data, err := os.ReadFile(private)
	if err != nil || string(data) != "integration\tpending\n" {
		t.Fatal("modified private progress")
	}
}
