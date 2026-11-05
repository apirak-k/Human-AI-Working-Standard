package app

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

func recoveryProgress(t *testing.T, root, plan, result string) {
	t.Helper()
	if err := settings.NewStore(root).WriteProgress(plan, result); err != nil {
		t.Fatal(err)
	}
}

func recoveryRead(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return strings.ReplaceAll(string(data), "\r\n", "\n")
}

func recoveryLocalRepo(t *testing.T, root string) string {
	t.Helper()
	dir := filepath.Join(root, "local-remote")
	if err := os.Mkdir(dir, 0700); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"init", "-b", "main"}, {"config", "user.name", "Fixture"}, {"config", "user.email", "fixture@example.invalid"}} {
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("fixture git %v: %v: %s", args, err, out)
		}
	}
	if err := os.WriteFile(filepath.Join(dir, "SKILL.md"), []byte("---\nname: recovery-fixture\ndescription: Local recovery skill\n---\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"add", "SKILL.md"}, {"commit", "-m", "Fixture"}} {
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("fixture git %v: %v: %s", args, err, out)
		}
	}
	return dir
}

func TestSettingsRecoveryCancelPreservesPendingApprovedPlan(t *testing.T) {
	for _, input := range []string{"q\n", "5\n1\nq\n6\napply\n"} {
		t.Run(strings.ReplaceAll(input, "\n", "/"), func(t *testing.T) {
			root, calls, resultPath := settingsHostFixture(t, false, "0")
			plan := "setting\tauto_update\toff\nadd-source\tsources\thttps://github.com/example/demo\tskills/packs/demo\nintegration\tupdate\tcomponent integration\n"
			result := "settings\tcompleted\nadd-source\tpending\nintegration\tpending\n"
			recoveryProgress(t, root, plan, result)
			before := nativeSettingsSnapshot(t, root)
			var output strings.Builder
			if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader(input), &output, io.Discard); err != nil {
				t.Fatal(err)
			}
			assertNativeSettingsNoLegacyCalls(t, calls)
			if !reflect.DeepEqual(before, nativeSettingsSnapshot(t, root)) {
				t.Fatal("unapproved Settings input overwrote pending actions or state")
			}
			if !strings.Contains(output.String(), plan) || !strings.Contains(output.String(), result) {
				t.Fatalf("recovery omitted the exact approved plan/result %q: %s", resultPath, output.String())
			}
		})
	}
}

func TestSettingsRecoveryCannotRetryUnsavedSettings(t *testing.T) {
	root, calls, _ := settingsHostFixture(t, false, "0")
	recoveryProgress(t, root, "setting\tauto_update\ton\nintegration\tupdate\tcomponent integration\n", "settings\tpending\nintegration\tpending\n")
	before := nativeSettingsSnapshot(t, root)
	var output strings.Builder
	err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("r\nq\n"), &output, io.Discard)
	if err == nil || !strings.Contains(strings.ToLower(err.Error()), "draft") {
		t.Fatalf("unsaved settings retry must require an explicit new draft, got %v", err)
	}
	assertNativeSettingsNoLegacyCalls(t, calls)
	if !reflect.DeepEqual(before, nativeSettingsSnapshot(t, root)) {
		t.Fatal("Retry of unsaved settings mutated the incomplete plan")
	}
	if !strings.Contains(strings.ToLower(output.String()), "settings") || !strings.Contains(strings.ToLower(output.String()), "pending") {
		t.Fatalf("missing explanation for refused unsaved settings retry: %s", output.String())
	}
}

func TestSettingsRecoveryExplicitDiscardKeepsPersonalFiles(t *testing.T) {
	for _, edit := range []bool{false, true} {
		name, input := "discard-then-cancel", "d\nq\n"
		if edit {
			name, input = "discard-then-apply-new-config", "d\n5\n1\nq\n6\napply\n"
		}
		t.Run(name, func(t *testing.T) {
			root, calls, resultPath := settingsHostFixture(t, false, "0")
			plan := "setting\tauto_update\toff\nadd-source\tsources\thttps://github.com/example/demo\tskills/packs/demo\nintegration\tupdate\tcomponent integration\n"
			recoveryProgress(t, root, plan, "settings\tcompleted\nadd-source\tpending\nintegration\tpending\n")
			private := filepath.Join(root, "personal-notes")
			if err := os.WriteFile(private, []byte("private notes\n"), 0600); err != nil {
				t.Fatal(err)
			}
			if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader(input), io.Discard, io.Discard); err != nil {
				t.Fatal(err)
			}
			assertNativeSettingsNoLegacyCalls(t, calls)
			if got := recoveryRead(t, private); got != "private notes\n" {
				t.Fatalf("discard changed personal files: %q", got)
			}
			result := recoveryRead(t, resultPath)
			if strings.Contains(result, "\tpending") {
				t.Fatalf("discard left abandoned actions pending: %q", result)
			}
			if !edit && (!strings.Contains(result, "add-source\tdiscarded") || !strings.Contains(result, "settings\tcompleted")) {
				t.Fatalf("discard lost completed/abandoned status: %q", result)
			}
			newPlan := recoveryRead(t, filepath.Join(filepath.Dir(resultPath), "settings.plan"))
			if edit && (newPlan == plan || strings.Contains(newPlan, "add-source")) {
				t.Fatalf("explicit discard did not replace old plan with config edit: %q", newPlan)
			}
		})
	}
}

func TestSettingsRecoveryRetriesApprovedLocalActions(t *testing.T) {
	for _, mode := range []string{"repository-success", "repository-failure", "repository-sync-failure", "brain-success"} {
		t.Run(mode, func(t *testing.T) {
			syncStatus := "0"
			if mode == "repository-sync-failure" {
				syncStatus = "7"
			}
			root, calls, resultPath := settingsHostFixture(t, false, syncStatus)
			t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
			remote := recoveryLocalRepo(t, root)
			kind, action := "add-source", "add-source\tsources\t"+remote+"\tskills/packs/demo\n"
			if mode == "brain-success" {
				kind, action = "brain", "brain-connect\tremote\t"+remote+"\n"
			}
			if mode == "repository-failure" {
				action = "add-source\tsources\t" + filepath.Join(root, "missing-local-repo") + "\tskills/packs/demo\n"
			}
			completedPlan, completedResult := "", ""
			if mode == "brain-success" {
				// A completed earlier action must survive recovery without being replayed.
				completedPlan = "add-source\tsources\t" + filepath.Join(root, "already-completed-unavailable-remote") + "\tskills/packs/previous\n"
				completedResult = "add-source\tcompleted\n"
			}
			plan := "setting\tauto_update\toff\n" + completedPlan + action + "integration\tupdate\tcomponent integration\n"
			beforeResult := "settings\tcompleted\n" + completedResult + kind + "\tpending\nintegration\tpending\n"
			recoveryProgress(t, root, plan, beforeResult)
			var output strings.Builder
			err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("r\n"), &output, io.Discard)
			if mode == "repository-failure" {
				if err == nil {
					t.Fatalf("missing repository retry reported success: %s", output.String())
				}
				assertNativeSettingsNoLegacyCalls(t, calls)
				if got := recoveryRead(t, resultPath); got != beforeResult {
					t.Fatalf("failed retry lost pending or completed statuses: %q", got)
				}
				return
			}
			if mode == "repository-sync-failure" {
				var status interface{ ExitCode() int }
				if !errors.As(err, &status) || status.ExitCode() != 7 {
					t.Fatalf("retry error %v, want Sync status 7", err)
				}
			} else if err != nil {
				t.Fatalf("retry failed: %v\n%s", err, output.String())
			}
			if got := recoveryRead(t, calls); got != "sync\n" {
				t.Fatalf("retry legacy calls %q, want one authoritative Sync", got)
			}
			status := "completed"
			if mode == "repository-sync-failure" {
				status = "pending"
			}
			want := "settings\tcompleted\n" + completedResult + kind + "\tcompleted\nintegration\t" + status + "\n"
			if got := recoveryRead(t, resultPath); got != want {
				t.Fatalf("retry progress = %q, want %q", got, want)
			}
			if got := recoveryRead(t, filepath.Join(filepath.Dir(resultPath), "settings.plan")); got != plan {
				t.Fatal("retry replaced the previously approved plan")
			}
			if mode == "brain-success" {
				got, err := settings.BrainRemote(context.Background(), settings.BrainDirectory(root))
				if err != nil || got != remote {
					t.Fatalf("retried brain remote %q, %v", got, err)
				}
			} else if registry := recoveryRead(t, filepath.Join(filepath.Dir(resultPath), "skill-sources", "registry.tsv")); !strings.Contains(registry, "demo\tskills/packs/demo\t"+remote) {
				t.Fatalf("retry did not register approved local source: %q", registry)
			}
		})
	}
}

func TestSettingsRecoveryPreflightsAllRepositoryActionsBeforeMutation(t *testing.T) {
	root, calls, resultPath := settingsHostFixture(t, false, "0")
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	remote := recoveryLocalRepo(t, root)
	plan := "setting\tauto_update\toff\n" +
		"add-source\tsources\t" + remote + "\tskills/packs/first\n" +
		"add-source\tsources\t" + remote + "\tskills/packs/first\n" +
		"integration\tupdate\tcomponent integration\n"
	result := "settings\tcompleted\nadd-source\tpending\nadd-source\tpending\nintegration\tpending\n"
	recoveryProgress(t, root, plan, result)
	var output strings.Builder
	err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("r\n"), &output, io.Discard)
	if err == nil {
		t.Fatalf("invalid later action did not abort recovery: %s", output.String())
	}
	for _, path := range []string{
		filepath.Join(settings.NewStore(root).Dir, "skill-sources"),
		filepath.Join(root, "skills", "packs", "first"),
	} {
		if _, err := os.Lstat(path); !os.IsNotExist(err) {
			t.Fatalf("recovery mutated an earlier repository before preflighting the full approved plan: %s (%v)", path, err)
		}
	}
	if got := recoveryRead(t, resultPath); got != result {
		t.Fatalf("failed preflight changed pending progress: %q", got)
	}
	assertNativeSettingsNoLegacyCalls(t, calls)
}

func TestSettingsRecoveryDirectSyncFinalizesFailedInitialInstall(t *testing.T) {
	root, calls, resultPath := settingsHostFixture(t, false, "7")
	for _, name := range []string{"settings.tsv", "install.complete"} {
		if err := os.Remove(filepath.Join(filepath.Dir(resultPath), name)); err != nil {
			t.Fatal(err)
		}
	}
	if err := RunSettings(context.Background(), root, []string{"setup"}, strings.NewReader("2\n5\n1\nq\n6\napply\n"), io.Discard, io.Discard); err == nil {
		t.Fatal("initial failed Sync reported success")
	}
	t.Setenv("HAWS_TEST_SYNC_EXIT", "0")
	if err := RunSync(context.Background(), nil, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	if installed, err := settings.NewStore(root).InstallComplete(); err != nil || !installed {
		t.Fatalf("successful direct Sync did not finalize installation: %v, %v", installed, err)
	}
	if got := recoveryRead(t, calls); got != "sync\nsync\n" {
		t.Fatalf("initial plus recovery Sync calls = %q", got)
	}
}

func TestSettingsRecoveryDirectSyncCannotCompletePendingNativeActions(t *testing.T) {
	root, _, resultPath := settingsHostFixture(t, false, "0")
	if err := os.Remove(filepath.Join(filepath.Dir(resultPath), "install.complete")); err != nil {
		t.Fatal(err)
	}
	recoveryProgress(t, root, "add-source\tsources\thttps://github.com/example/demo\tskills/packs/demo\nintegration\tupdate\tcomponent integration\n", "settings\tcompleted\nadd-source\tpending\nintegration\tpending\n")
	_ = RunSync(context.Background(), nil, strings.NewReader(""), io.Discard, io.Discard)
	if installed, err := settings.NewStore(root).InstallComplete(); err != nil || installed {
		t.Fatalf("direct Sync completed pending repository work: installed %v, %v", installed, err)
	}
	if got := recoveryRead(t, resultPath); !strings.Contains(got, "add-source\tpending") {
		t.Fatalf("direct Sync lost pending native action: %q", got)
	}
	if got := recoveryRead(t, resultPath); !strings.Contains(got, "integration\tpending") {
		t.Fatalf("direct Sync prematurely completed integration before the source existed: %q", got)
	}
}

func recoveryReplacementSource(t *testing.T) (root, calls, resultPath, approvedURL, replacementURL string) {
	t.Helper()
	root, calls, resultPath = settingsHostFixture(t, false, "0")
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	approvedRoot := filepath.Join(root, "approved")
	if err := os.Mkdir(approvedRoot, 0700); err != nil {
		t.Fatal(err)
	}
	approvedURL = recoveryLocalRepo(t, approvedRoot)
	replacementURL = recoveryLocalRepo(t, root)
	store := settings.NewStore(root)
	checkout := filepath.Join(store.Dir, "skill-sources", "skills", "packs", "demo")
	if err := os.MkdirAll(filepath.Dir(checkout), 0700); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("git", "clone", "--quiet", "--", replacementURL, checkout)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("clone replacement fixture: %v: %s", err, out)
	}
	registry := filepath.Join(store.Dir, "skill-sources", "registry.tsv")
	if err := os.WriteFile(registry, []byte("demo\tskills/packs/demo\t"+replacementURL+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	return
}

func TestSettingsRecoveryRemovalRetainsApprovedRepositoryIdentity(t *testing.T) {
	for _, mode := range []string{"replacement-url", "legacy-missing-url", "matching-approved-url"} {
		t.Run(mode, func(t *testing.T) {
			root, calls, resultPath, approvedURL, replacementURL := recoveryReplacementSource(t)
			row := "remove-source\tsources\tdevice-demo::skills/packs/demo\tskills/packs/demo"
			if mode == "matching-approved-url" {
				row += "\t" + replacementURL
			} else if mode == "replacement-url" {
				row += "\t" + approvedURL
			}
			plan := row + "\nintegration\tupdate\tcomponent integration\n"
			result := "settings\tcompleted\nremove-source\tpending\nintegration\tpending\n"
			recoveryProgress(t, root, plan, result)
			before := nativeSettingsSnapshot(t, root)
			err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("r\n"), io.Discard, io.Discard)
			if mode == "matching-approved-url" {
				if err != nil {
					t.Fatalf("matching approved removal failed: %v", err)
				}
				if got := recoveryRead(t, calls); got != "sync\n" {
					t.Fatalf("matching removal calls = %q, want one Sync", got)
				}
				checkout := filepath.Join(filepath.Dir(resultPath), "skill-sources", "skills", "packs", "demo")
				if _, err := os.Stat(checkout); !os.IsNotExist(err) {
					t.Fatalf("approved source checkout was not removed: %v", err)
				}
				return
			}
			if err == nil {
				t.Error("retry accepted removal without the original approved repository URL")
			}
			if !reflect.DeepEqual(before, nativeSettingsSnapshot(t, root)) {
				t.Error("retry changed replacement checkout, registry, or saved progress")
			}
			assertNativeSettingsNoLegacyCalls(t, calls)
		})
	}
}

func TestSettingsPlanRemovalIncludesApprovedRepositoryURL(t *testing.T) {
	root, _, _, _, replacementURL := recoveryReplacementSource(t)
	draft, err := settings.NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if err := draft.LoadCatalog(context.Background()); err != nil {
		t.Fatal(err)
	}
	draft.RemoveSource("device-demo::skills/packs/demo")
	want := "remove-source\tsources\tdevice-demo::skills/packs/demo\tskills/packs/demo\t" + replacementURL + "\n"
	if plan := settingsPlan(draft, true); !strings.Contains(plan, want) {
		t.Fatalf("saved plan omitted approved removal URL\ngot:\n%s\nwant row:\n%s", plan, want)
	}
}
