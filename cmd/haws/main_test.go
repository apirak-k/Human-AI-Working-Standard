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

func TestRunPreparesRegisteredDeviceSourceAndLeavesUnknownSourceForLegacyFallback(t *testing.T) {
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

func TestRunExecutesNativeCodexSkillLinker(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	path := filepath.Join(root, "skills", "custom", "demo", "SKILL.md")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("---\nname: demo\n---\nSkill.\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HOME", home)
	t.Setenv("CODEX_HOME", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-codex-skills"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Codex skill linker exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "1\t0\t0\t0\t0\n"; got != want {
		t.Fatalf("native Codex skill result = %q, want %q", got, want)
	}
	destination := filepath.Join(home, ".agents", "skills", "demo")
	target, err := os.Readlink(destination)
	if err != nil || target != filepath.Join(root, "skills", "custom", "demo") {
		t.Fatalf("native Codex skill link = %q, %v", target, err)
	}
}

func TestRunExecutesNativeClaudeSkillLinker(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	path := filepath.Join(root, "skills", "custom", "demo", "SKILL.md")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("---\nname: demo\n---\nSkill.\n"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HOME", home)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-claude-skills"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Claude skill linker exit = %d, stderr = %q", code, stderr.String())
	}
	if got, want := stdout.String(), "1\t0\t0\t0\t0\n"; got != want {
		t.Fatalf("native Claude skill result = %q, want %q", got, want)
	}
	destination := filepath.Join(home, ".claude", "skills", "demo")
	target, err := os.Readlink(destination)
	if err != nil || target != filepath.Join(root, "skills", "custom", "demo") {
		t.Fatalf("native Claude skill link = %q, %v", target, err)
	}
}

func TestRunExecutesNativeGeminiSkillsJSONLifecycle(t *testing.T) {
	root := t.TempDir()
	config := filepath.Join(root, "skills.json")
	manifest := filepath.Join(root, "state", "gemini-skills-ownership.json")
	candidate := filepath.Join(root, "candidate.json")
	if err := os.MkdirAll(filepath.Dir(manifest), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(config, []byte("{\n  \"entries\": [{\"path\": \"/user\"}]\n}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(candidate, []byte("{\"entries\":[{\"path\":\"/haws/skill\"}]}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	invoke := func(args ...string) (string, string, int) {
		t.Helper()
		var stdout, stderr bytes.Buffer
		code := run(append([]string{"--haws-gemini-skills-json"}, args...), strings.NewReader(""), &stdout, &stderr)
		return stdout.String(), stderr.String(), code
	}
	stdout, stderr, code := invoke("apply", config, manifest, candidate)
	if code != 0 || stderr != "" || stdout != "OK: merged 1 new HAWS Antigravity skill entries; preserved 1 existing entries.\n" {
		t.Fatalf("native apply = (%q, %q, %d)", stdout, stderr, code)
	}
	if stdout, stderr, code = invoke("verify", config, manifest); code != 0 || stderr != "" || !strings.Contains(stdout, "readable") {
		t.Fatalf("native verify = (%q, %q, %d)", stdout, stderr, code)
	}
	stdout, stderr, code = invoke("uninstall", config, manifest)
	if code != 0 || stderr != "" || stdout != "OK: removed 1 HAWS Antigravity skill entries; preserved 1 other entries.\n" {
		t.Fatalf("native uninstall = (%q, %q, %d)", stdout, stderr, code)
	}
	configBytes, err := os.ReadFile(config)
	if err != nil || !strings.Contains(string(configBytes), `"/user"`) || strings.Contains(string(configBytes), `"/haws/skill"`) {
		t.Fatalf("uninstall config = %q, %v", configBytes, err)
	}
}

func TestRunExecutesNativeCodexAgentLifecycle(t *testing.T) {
	source := filepath.Join(t.TempDir(), "HAWS source with spaces")
	if err := os.MkdirAll(filepath.Join(source, "agents"), 0o700); err != nil {
		t.Fatal(err)
	}
	roles := []string{"backend-engineer", "frontend-engineer", "organizer", "researcher", "tester"}
	for _, role := range roles {
		body := "---\nname: " + role + "\ndescription: Canonical " + role + " requirements.\n---\n\nRole.\n"
		if err := os.WriteFile(filepath.Join(source, "agents", role+".md"), []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	home := filepath.Join(t.TempDir(), "Codex home with spaces")
	t.Setenv("HAWS_ROOT", "")
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_SYNC_ROOT", source)
	t.Setenv("CODEX_HOME", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"codex-agents", "install", "--source", source, "--codex-home", home}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Codex agent install exit = %d, stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	if !strings.Contains(stdout.String(), "install 5 Codex profiles") || stderr.Len() != 0 {
		t.Fatalf("native Codex agent install output = (%q, %q)", stdout.String(), stderr.String())
	}
	for _, role := range roles {
		if _, err := os.Stat(filepath.Join(home, "agents", role+".toml")); err != nil {
			t.Fatalf("native install did not create %s profile: %v", role, err)
		}
	}

	stdout.Reset()
	stderr.Reset()
	if code := run([]string{"--haws-codex-agents", "install", "--source", source, "--codex-home", home, "--emit-ownership"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Codex agent ownership result exit = %d, stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	rows := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	if len(rows) != len(roles)+1 || !strings.HasPrefix(rows[len(rows)-1], "manifest\t") {
		t.Fatalf("native ownership rows = %q; want five profiles and a manifest", stdout.String())
	}
	for index, row := range rows[:len(roles)] {
		fields := strings.Split(row, "\t")
		if len(fields) != 5 || fields[0] != "profile" || fields[1] != roles[index] {
			t.Fatalf("ownership row = %q; want profile row for %s", row, roles[index])
		}
	}

	stdout.Reset()
	stderr.Reset()
	if code := run([]string{"--haws-codex-agents", "uninstall", "--source", source, "--codex-home", home}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Codex agent uninstall exit = %d, stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	for _, role := range roles {
		if _, err := os.Stat(filepath.Join(home, "agents", role+".toml")); !os.IsNotExist(err) {
			t.Fatalf("native uninstall left %s profile: %v", role, err)
		}
	}
}

func TestRunExecutesNativeAgentFileProjection(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	home := filepath.Join(t.TempDir(), "agent home")
	if err := os.MkdirAll(filepath.Join(root, "agents"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(home, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "agents", "backend-engineer.md"), []byte("Canonical agent.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HOME", home)
	var stdout, stderr bytes.Buffer
	args := []string{"--haws-sync-agent-files", "--source", root, "--home", home, "--state-dir", stateDir, "--claude", "--gemini"}
	if code := run(args, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native agent file projection exit = %d, stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	fields := strings.Split(strings.TrimSpace(stdout.String()), "\t")
	if len(fields) != 7 || fields[0] != "2" {
		t.Fatalf("native agent file result = %q; want seven fields and two targets", stdout.String())
	}
	for _, destination := range []string{
		filepath.Join(home, ".claude", "agents", "backend-engineer.md"),
		filepath.Join(home, ".gemini", "config", "agents", "backend-engineer", "agent.md"),
	} {
		contents, err := os.ReadFile(destination)
		if err != nil || string(contents) != "Canonical agent.\n" {
			t.Fatalf("native projection %s = %q, %v", destination, contents, err)
		}
	}
}

func TestRunExecutesNativeClaudeCommandProjection(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	home := filepath.Join(t.TempDir(), "Claude home with spaces")
	skillDir := filepath.Join(root, "skills", "custom", "demo")
	if err := os.MkdirAll(skillDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(home, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(skillDir, "SKILL.md"), []byte("---\nname: demo\ndescription: Run demo.\n---\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_SYNC_ROOT", root)
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HOME", home)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--haws-sync-claude-commands"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("native Claude command projection exit = %d, stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	if got, want := strings.TrimSpace(stdout.String()), "1\t1\t0\t0"; got != want {
		t.Fatalf("native Claude command result = %q; want %q", got, want)
	}
	target := filepath.Join(home, ".claude", "commands", "demo.md")
	contents, err := os.ReadFile(target)
	want := "---\ndescription: Run demo.\n---\nExecute the demo skill workflow defined in ~/.claude/skills/demo/SKILL.md.\n"
	if err != nil || string(contents) != want {
		t.Fatalf("generated Claude command = %q, %v; want %q", contents, err, want)
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
