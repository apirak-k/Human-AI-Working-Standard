package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/migration"
)

func TestRunPreservesSupportedLegacyArgumentsAndExitStatus(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	writeArgsRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"doctor", "--json"}, strings.NewReader(""), &stdout, &stderr); code != 7 {
		t.Fatalf("run() exit = %d, want legacy exit 7 (stderr %q)", code, stderr.String())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != "doctor\n--json\n" {
		t.Fatalf("legacy args = %q", args)
	}
}

func TestRunPreservesSyncAndUninstallOptionsAcrossGoHost(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{name: "sync clean", args: []string{"sync", "--clean"}, want: "sync\n--clean\n"},
		{name: "uninstall dry run", args: []string{"uninstall", "--dry-run"}, want: "uninstall\n--dry-run\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			argsPath := filepath.Join(root, "args.txt")
			writeArgsRuntime(t, root, argsPath)
			t.Setenv("HAWS_ROOT", root)
			var stdout, stderr bytes.Buffer
			if code := run(tc.args, strings.NewReader(""), &stdout, &stderr); code != 7 {
				t.Fatalf("run() exit = %d, want legacy exit 7 (stderr %q)", code, stderr.String())
			}
			args, err := os.ReadFile(argsPath)
			if err != nil {
				t.Fatal(err)
			}
			if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != tc.want {
				t.Fatalf("legacy args = %q, want %q", normalized, tc.want)
			}
		})
	}
}

func TestRunDirectRepairPreviewsBeforeAnySync(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	writeDoctorRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"repair"}, strings.NewReader("n\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("repair exit = %d, stderr = %q", code, stderr.String())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != "doctor\n--deep\n" {
		t.Fatalf("repair legacy args = %q, want diagnostics only", args)
	}
	if !strings.Contains(stdout.String(), "Repair plan") || !strings.Contains(stdout.String(), "No changes were made") {
		t.Fatalf("repair did not preview and cancel safely: %q", stdout.String())
	}
}

func TestRunPrintsVersionWithoutFindingCheckout(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--version"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("run() exit = %d, stderr %q", code, stderr.String())
	}
	if stdout.String() != "HAWS dev\n" {
		t.Fatalf("version output = %q, want %q", stdout.String(), "HAWS dev\n")
	}
}

func TestRunExecutesNativeSyncTargetWithoutReenteringTheShellHost(t *testing.T) {
	root := t.TempDir()
	brain := filepath.Join(root, "secondbrain")
	if err := os.MkdirAll(brain, 0700); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command("git", "init", brain).CombinedOutput(); err != nil {
		t.Fatalf("initialize local Second Brain: %v: %s", err, output)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "secondbrain"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Sync target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tSecond Brain is local-only\n"; got != want {
		t.Fatalf("native Sync result = %q, want %q", got, want)
	}
}

func TestRunSkipsNativeBrainSyncWhenDisabled(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update_brain\toff\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "secondbrain"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Sync target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tAuto Update is disabled\n"; got != want {
		t.Fatalf("native Sync result = %q, want %q", got, want)
	}
}

func TestRunMigrationUsesInstalledPackageWithoutLegacyRootDiscovery(t *testing.T) {
	packageRoot := t.TempDir()
	if err := os.WriteFile(filepath.Join(packageRoot, "package-manifest.json"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	legacyRoot := t.TempDir()
	if output, err := exec.Command("git", "init", legacyRoot).CombinedOutput(); err != nil {
		t.Fatalf("initialize legacy checkout: %v: %s", err, output)
	}
	if err := os.WriteFile(filepath.Join(legacyRoot, "haws.sh"), []byte("legacy"), 0o600); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(legacyRoot, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_APP_DIR", packageRoot)
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_ROOT", filepath.Join(t.TempDir(), "not-a-checkout"))
	var stdout, stderr bytes.Buffer
	if code := run([]string{"migrate", "--from", legacyRoot, "--yes"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("migrate exit = %d, stderr=%q stdout=%q", code, stderr.String(), stdout.String())
	}
	profile, exists, err := migration.LoadPackageProfile(packageRoot)
	if err != nil || !exists || profile.LegacyRoot == "" {
		t.Fatalf("migration profile = %#v, exists=%v, err=%v", profile, exists, err)
	}
}

func TestRunRejectsUnknownAction(t *testing.T) {
	root := t.TempDir()
	writeUnknownRuntime(t, root)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"unknown"}, strings.NewReader(""), &stdout, &stderr); code != 1 {
		t.Fatalf("run() exit = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "Usage:") {
		t.Fatalf("legacy usage missing: %q", stderr.String())
	}
}

func TestRunRequiresAValidCheckout(t *testing.T) {
	t.Setenv("HAWS_ROOT", t.TempDir())
	var stdout, stderr bytes.Buffer
	if code := run(nil, strings.NewReader(""), &stdout, &stderr); code != 1 {
		t.Fatalf("run() exit = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "does not contain haws.sh") {
		t.Fatalf("checkout error missing: %q", stderr.String())
	}
}

func TestRunStartsSetupOnFirstLaunchThenShowsHome(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	argsPath := filepath.Join(root, "actions.txt")
	writeSetupRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HOME", t.TempDir())
	var stdout, stderr bytes.Buffer
	if code := run(nil, strings.NewReader("q\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("first-run exit = %d, stderr=%q stdout=%q", code, stderr.String(), stdout.String())
	}
	if !strings.Contains(stdout.String(), "First launch detected") || !strings.Contains(stdout.String(), "HAWS — Human-AI Working Standard") {
		t.Fatalf("first run did not go through Setup and then Home: %q", stdout.String())
	}
	if _, err := os.Stat(argsPath); !os.IsNotExist(err) {
		t.Fatalf("native Setup invoked legacy runtime: %v", err)
	}
	if !strings.Contains(stdout.String(), "HAWS Setup") {
		t.Fatal("native Setup was not shown")
	}
}

func TestRunOpensHomeForExistingSettingsWithoutRepeatingSetup(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	argsPath := filepath.Join(root, "actions.txt")
	writeSetupRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	var stdout, stderr bytes.Buffer
	if code := run(nil, strings.NewReader("q\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("existing-install exit = %d, stderr=%q", code, stderr.String())
	}
	if !strings.Contains(stdout.String(), "HAWS — Human-AI Working Standard") || strings.Contains(stdout.String(), "First launch detected") {
		t.Fatalf("existing install did not open Home directly: %q", stdout.String())
	}
	if _, err := os.Stat(argsPath); !os.IsNotExist(err) {
		t.Fatalf("Setup was invoked for an existing installation: err=%v", err)
	}
}

func writeArgsRuntime(t *testing.T, root, argsPath string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Setenv("HAWS_TEST_ARGS", argsPath)
		batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %2>> \"%HAWS_TEST_ARGS%\"\r\nexit /b 7\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + argsPath + "\"\nexit 7\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}

func writeUnknownRuntime(t *testing.T, root string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		batch := "@echo off\r\necho Usage: unknown 1>&2\r\nexit /b 1\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/bin/sh\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\necho 'Usage: unknown' >&2\nexit 1\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}

func writeDoctorRuntime(t *testing.T, root, argsPath string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Setenv("HAWS_TEST_ARGS", argsPath)
		batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %2>> \"%HAWS_TEST_ARGS%\"\r\necho doctor-preview\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" >> '" + argsPath + "'\necho doctor-preview\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}

func writeSetupRuntime(t *testing.T, root, argsPath string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Setenv("HAWS_TEST_ARGS", argsPath)
		batch := "@echo off\r\necho %1>> \"%HAWS_TEST_ARGS%\"\r\n" +
			"if /I \"%1\"==\"setup\" (if not exist \"%HAWS_STATE_DIR%\" mkdir \"%HAWS_STATE_DIR%\" & echo schema=1> \"%HAWS_STATE_DIR%\\install.complete\")\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"" + argsPath + "\"\n" +
		"if [ \"$1\" = setup ]; then mkdir -p \"$HAWS_STATE_DIR\"; printf 'schema=1\\n' > \"$HAWS_STATE_DIR/install.complete\"; fi\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS == "windows" {
		return
	}
	fakeBin := filepath.Join(root, "bin")
	if err := os.MkdirAll(fakeBin, 0o700); err != nil {
		t.Fatal(err)
	}
	fakeBash := "#!/bin/sh\nif [ \"$1\" = -c ]; then exit 0; fi\nexec /bin/sh \"$@\"\n"
	if err := os.WriteFile(filepath.Join(fakeBin, "bash"), []byte(fakeBash), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", fakeBin+string(os.PathListSeparator)+os.Getenv("PATH"))
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	contents, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(contents)
}
