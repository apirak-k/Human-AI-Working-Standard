package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

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

func TestNativeSyncPreparationTimeoutLeavesRoomForShellDeadline(t *testing.T) {
	t.Setenv("HAWS_SYNC_TIMEOUT_SECONDS", "10")
	if got, want := nativeSyncPreparationTimeout(), 9750*time.Millisecond; got != want {
		t.Fatalf("configured preparation timeout = %s, want %s", got, want)
	}
	t.Setenv("HAWS_SYNC_TIMEOUT_SECONDS", "invalid")
	if got, want := nativeSyncPreparationTimeout(), 29750*time.Millisecond; got != want {
		t.Fatalf("default preparation timeout = %s, want %s", got, want)
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
	t.Setenv("HAWS_SYNC_ROOT", "")
	t.Setenv("HAWS_ROOT", root)
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
	t.Setenv("HAWS_SYNC_ROOT", "")
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "secondbrain"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Sync target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tAuto Update is disabled\n"; got != want {
		t.Fatalf("native Sync result = %q, want %q", got, want)
	}
}

func TestRunExecutesNativeHawsRootSyncTarget(t *testing.T) {
	root, seed, remote := nativeHawsSyncFixture(t)
	if err := os.WriteFile(filepath.Join(seed, "release.txt"), []byte("new release\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, seed, "add", "release.txt")
	gitForNativeSync(t, seed, "commit", "-m", "advance remote")
	gitForNativeSync(t, seed, "push", "origin", "main")
	want := gitForNativeSync(t, seed, "rev-parse", "HEAD")
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", filepath.Join(root, ".haws", "state"))
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/777-haws")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")
	t.Setenv("HAWS_SYNC_TIMEOUT_SECONDS", "10")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "haws"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native HAWS target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "updated\t"+want+"\tfinal HEAD equals candidate\n"; got != want {
		t.Fatalf("native HAWS result = %q, want %q", got, want)
	}
	if got := gitForNativeSync(t, root, "rev-parse", "HEAD"); got != want {
		t.Fatalf("HAWS root HEAD = %s, want %s", got, want)
	}
	if got := gitForNativeSync(t, remote, "rev-parse", "refs/heads/main"); got != want {
		t.Fatalf("HAWS remote HEAD = %s, want %s", got, want)
	}
	if got := gitForNativeSync(t, root, "for-each-ref", "refs/haws-sync"); got != "" {
		t.Fatalf("native candidate ref leaked: %s", got)
	}
}

func TestRunExecutesNativeRegisteredSourceSyncTarget(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, root, "init", "-b", "main")
	gitForNativeSync(t, root, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, root, "config", "user.name", "Test")
	const sourcePath = "skills/packs/demo"
	sourceDir := filepath.Join(root, filepath.FromSlash(sourcePath))
	if err := os.MkdirAll(sourceDir, 0700); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, sourceDir, "init", "-b", "main")
	gitForNativeSync(t, sourceDir, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, sourceDir, "config", "user.name", "Test")
	if err := os.WriteFile(filepath.Join(sourceDir, "SKILL.md"), []byte("---\nname: demo\ndescription: fixture\n---\n\nBaseline.\n"), 0600); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, sourceDir, "add", "SKILL.md")
	gitForNativeSync(t, sourceDir, "commit", "-m", "baseline")
	remote := filepath.Join(t.TempDir(), "demo.git")
	gitForNativeSync(t, filepath.Dir(remote), "init", "--bare", remote)
	gitForNativeSync(t, sourceDir, "remote", "add", "origin", remote)
	gitForNativeSync(t, sourceDir, "push", "-u", "origin", "main")
	gitForNativeSync(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")
	if err := os.WriteFile(filepath.Join(root, ".gitmodules"), []byte("[submodule \"demo\"]\n\tpath = "+sourcePath+"\n\turl = https://example.invalid/demo.git\n"), 0600); err != nil {
		t.Fatal(err)
	}
	seed := filepath.Join(t.TempDir(), "seed")
	gitForNativeSync(t, filepath.Dir(seed), "clone", remote, seed)
	gitForNativeSync(t, seed, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, seed, "config", "user.name", "Test")
	if err := os.WriteFile(filepath.Join(seed, "SKILL.md"), []byte("---\nname: demo\ndescription: fixture\n---\n\nUpdated.\n"), 0600); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, seed, "add", "SKILL.md")
	gitForNativeSync(t, seed, "commit", "-m", "advance source")
	gitForNativeSync(t, seed, "push", "origin", "main")
	want := gitForNativeSync(t, seed, "rev-parse", "HEAD")

	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_REPO_DIR", "")
	t.Setenv("HAWS_STATE_DIR", filepath.Join(root, ".haws", "state"))
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/777-source")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")
	t.Setenv("HAWS_SYNC_TIMEOUT_SECONDS", "10")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "demo::" + sourcePath}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native source target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, expected := stdout.String(), "updated\t"+want+"\tfinal HEAD equals candidate\n"; got != expected {
		t.Fatalf("native source result = %q, want %q", got, expected)
	}
	if got := gitForNativeSync(t, sourceDir, "rev-parse", "HEAD"); got != want {
		t.Fatalf("source HEAD = %s, want %s", got, want)
	}
	if got := gitForNativeSync(t, remote, "rev-parse", "refs/heads/main"); got != want {
		t.Fatalf("source Sync changed upstream HEAD to %s, want %s", got, want)
	}
	if got := gitForNativeSync(t, sourceDir, "for-each-ref", "refs/haws-sync"); got != "" {
		t.Fatalf("native source candidate ref leaked: %s", got)
	}
}

func TestRunPreparesRegisteredDeviceSourceAndSignalsLegacyGitlinkFallback(t *testing.T) {
	root := t.TempDir()
	seed := t.TempDir()
	gitForNativeSync(t, seed, "init", "-b", "main")
	gitForNativeSync(t, seed, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, seed, "config", "user.name", "Test")
	if err := os.WriteFile(filepath.Join(seed, "SKILL.md"), []byte("---\nname: demo\ndescription: fixture\n---\n\nSkill.\n"), 0600); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, seed, "add", "SKILL.md")
	gitForNativeSync(t, seed, "commit", "-m", "baseline")
	remote := filepath.Join(t.TempDir(), "demo.git")
	gitForNativeSync(t, filepath.Dir(remote), "init", "--bare", remote)
	gitForNativeSync(t, seed, "remote", "add", "origin", remote)
	gitForNativeSync(t, seed, "push", "-u", "origin", "main")
	gitForNativeSync(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")

	stateDir := filepath.Join(root, ".haws", "state")
	registryDir := filepath.Join(stateDir, "skill-sources")
	if err := os.MkdirAll(registryDir, 0700); err != nil {
		t.Fatal(err)
	}
	const sourcePath = "skills/packs/demo"
	if err := os.WriteFile(filepath.Join(registryDir, "registry.tsv"), []byte("demo\t"+sourcePath+"\t"+remote+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", "")
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	t.Setenv("HAWS_SYNC_PREFETCH_MODE", "1")
	t.Setenv("HAWS_SYNC_TIMEOUT_SECONDS", "10")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-prepare-source", "device-demo::" + sourcePath}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("registered source preparation exit = %d, stderr = %q", code, stderr.String())
	}
	checkout := filepath.Join(registryDir, filepath.FromSlash(sourcePath))
	if got := gitForNativeSync(t, checkout, "remote", "get-url", "origin"); got != remote {
		t.Fatalf("prepared origin = %q, want %q", got, remote)
	}
	stdout.Reset()
	stderr.Reset()
	if code := run([]string{"--haws-prepare-source", "demo::" + sourcePath}, strings.NewReader(""), &stdout, &stderr); code != 2 {
		t.Fatalf("Gitlink fallback exit = %d, want 2 (stderr %q)", code, stderr.String())
	}
}

func TestRunSkipsNativeHawsRootSyncWhenDisabled(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update_skills\toff\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HAWS_PACKAGE_DIR", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "haws"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native HAWS target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tAuto Update is disabled\n"; got != want {
		t.Fatalf("native HAWS result = %q, want %q", got, want)
	}
}

func TestRunSkipsNativeSourceSyncWhenDisabled(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update_skills\toff\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_REPO_DIR", "")
	t.Setenv("HAWS_STATE_DIR", stateDir)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "demo::skills/packs/demo"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native source target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tAuto Update is disabled\n"; got != want {
		t.Fatalf("native source result = %q, want %q", got, want)
	}
}

func TestRunSkipsNativeHawsRootSyncForInstalledPackage(t *testing.T) {
	t.Setenv("HAWS_SYNC_ROOT", t.TempDir())
	t.Setenv("HAWS_PACKAGE_DIR", t.TempDir())
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-target", "haws"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native HAWS target exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "skipped\t-\tHAWS app update is managed by Go\n"; got != want {
		t.Fatalf("native HAWS result = %q, want %q", got, want)
	}
}

func nativeHawsSyncFixture(t *testing.T) (root, seed, remote string) {
	t.Helper()
	root = t.TempDir()
	gitForNativeSync(t, root, "init", "-b", "main")
	gitForNativeSync(t, root, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, root, "config", "user.name", "Test")
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/usr/bin/env bash\n"), 0600); err != nil {
		t.Fatal(err)
	}
	gitForNativeSync(t, root, "add", "haws.sh")
	gitForNativeSync(t, root, "commit", "-m", "baseline")
	remote = filepath.Join(t.TempDir(), "haws.git")
	gitForNativeSync(t, filepath.Dir(remote), "init", "--bare", remote)
	gitForNativeSync(t, root, "remote", "add", "origin", remote)
	gitForNativeSync(t, root, "push", "-u", "origin", "main")
	gitForNativeSync(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")
	seed = filepath.Join(t.TempDir(), "seed")
	gitForNativeSync(t, filepath.Dir(seed), "clone", remote, seed)
	gitForNativeSync(t, seed, "config", "user.email", "test@example.invalid")
	gitForNativeSync(t, seed, "config", "user.name", "Test")
	return root, seed, remote
}

func gitForNativeSync(t *testing.T, dir string, args ...string) string {
	t.Helper()
	command := exec.Command("git", append([]string{"-C", dir}, args...)...)
	output, err := command.CombinedOutput()
	if err != nil {
		t.Fatalf("git -C %s %v: %v: %s", dir, args, err, output)
	}
	return strings.TrimSpace(string(output))
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
