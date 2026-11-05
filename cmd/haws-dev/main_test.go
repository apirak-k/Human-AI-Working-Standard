package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestSyncRuntimeUsesCurrentCodeAndExcludesPersonalPaths(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source")
	runtimeRoot := filepath.Join(root, "sandbox", "runtime")
	if err := os.MkdirAll(source, 0o755); err != nil {
		t.Fatal(err)
	}
	gitTest(t, source, "init", "-q")
	gitTest(t, source, "config", "user.name", "HAWS test")
	gitTest(t, source, "config", "user.email", "haws-test@example.invalid")
	gitTest(t, source, "config", "core.autocrlf", "false")
	writeTestFile(t, source, ".gitignore", ".haws/\nsecondbrain/notes/\n")
	writeTestFile(t, source, "haws.sh", "#!/bin/sh\necho current\n")
	writeTestFile(t, source, "tracked.txt", "base\n")
	gitTest(t, source, "add", ".gitignore", "haws.sh", "tracked.txt")
	gitTest(t, source, "commit", "-qm", "base")
	globalConfig := filepath.Join(root, "global.gitconfig")
	writeTestFile(t, root, "global.gitconfig", "[core]\n\tautocrlf = true\n")
	t.Setenv("GIT_CONFIG_GLOBAL", globalConfig)
	if err := syncRuntime(source, runtimeRoot); err != nil {
		t.Fatalf("syncRuntime() first run: %v", err)
	}

	writeTestFile(t, source, "tracked.txt", "latest development edit\n")
	writeTestFile(t, source, "untracked.go", "package fixture\n")
	writeTestFile(t, source, ".haws/state/personal.txt", "private state\n")
	writeTestFile(t, source, "secondbrain/notes/private.md", "private note\n")
	if err := syncRuntime(source, runtimeRoot); err != nil {
		t.Fatalf("syncRuntime() with working changes: %v", err)
	}

	if got := readTestFile(t, runtimeRoot, "tracked.txt"); got != "latest development edit\n" {
		t.Fatalf("tracked source copied = %q", got)
	}
	if got := readTestFile(t, runtimeRoot, "untracked.go"); got != "package fixture\n" {
		t.Fatalf("untracked source copied = %q", got)
	}
	for _, privatePath := range []string{".haws/state/personal.txt", "secondbrain/notes/private.md"} {
		if _, err := os.Lstat(filepath.Join(runtimeRoot, privatePath)); !os.IsNotExist(err) {
			t.Fatalf("personal path %q was copied into the runtime: err=%v", privatePath, err)
		}
	}
}

func TestSyncRuntimeKeepsSandboxFilesOutsideSourceControl(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source")
	runtimeRoot := filepath.Join(root, "sandbox", "runtime")
	if err := os.MkdirAll(source, 0o755); err != nil {
		t.Fatal(err)
	}
	gitTest(t, source, "init", "-q")
	gitTest(t, source, "config", "user.name", "HAWS test")
	gitTest(t, source, "config", "user.email", "haws-test@example.invalid")
	gitTest(t, source, "config", "core.autocrlf", "false")
	writeTestFile(t, source, "haws.sh", "#!/bin/sh\n")
	writeTestFile(t, source, "tracked.txt", "base\n")
	gitTest(t, source, "add", "haws.sh", "tracked.txt")
	gitTest(t, source, "commit", "-qm", "base")
	if err := syncRuntime(source, runtimeRoot); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, runtimeRoot, "sandbox-only.txt", "persists between runs\n")
	writeTestFile(t, source, "tracked.txt", "new source\n")
	if err := syncRuntime(source, runtimeRoot); err != nil {
		t.Fatal(err)
	}
	if got := readTestFile(t, runtimeRoot, "sandbox-only.txt"); got != "persists between runs\n" {
		t.Fatalf("sandbox-only file = %q", got)
	}
	if got := readTestFile(t, runtimeRoot, "tracked.txt"); got != "new source\n" {
		t.Fatalf("refreshed source = %q", got)
	}
}

func TestPrepareSandboxRefusesUnownedOrMismatchedDirectories(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "source")
	if err := os.MkdirAll(source, 0o755); err != nil {
		t.Fatal(err)
	}
	gitTest(t, source, "init", "-q")
	writeTestFile(t, source, "haws.sh", "#!/bin/sh\n")
	gitTest(t, source, "add", "haws.sh")
	gitTest(t, source, "config", "user.name", "HAWS test")
	gitTest(t, source, "config", "user.email", "haws-test@example.invalid")
	gitTest(t, source, "config", "core.autocrlf", "false")
	gitTest(t, source, "commit", "-qm", "base")

	unowned := filepath.Join(root, "unowned")
	if err := os.MkdirAll(unowned, 0o755); err != nil {
		t.Fatal(err)
	}
	writeTestFile(t, unowned, "keep.txt", "untouched\n")
	if err := prepareSandbox(source, unowned); err == nil || !strings.Contains(err.Error(), "not empty") {
		t.Fatalf("prepareSandbox(unowned) error = %v", err)
	}
	if got := readTestFile(t, unowned, "keep.txt"); got != "untouched\n" {
		t.Fatalf("unowned file changed to %q", got)
	}

	owned := filepath.Join(root, "owned")
	if err := prepareSandbox(source, owned); err != nil {
		t.Fatal(err)
	}
	otherSource := filepath.Join(root, "other-source")
	if err := os.MkdirAll(otherSource, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := prepareSandbox(otherSource, owned); err == nil || !strings.Contains(err.Error(), "does not match") {
		t.Fatalf("prepareSandbox(mismatched) error = %v", err)
	}
}

func TestResolveSandboxRootResolvesSymlinkedParentsBeforeIsolationCheck(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "checkout")
	if err := os.MkdirAll(source, 0o755); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(root, "checkout-alias")
	if err := os.Symlink(source, alias); err != nil {
		t.Skipf("directory symlinks are unavailable: %v", err)
	}
	resolvedSource, err := filepath.EvalSymlinks(source)
	if err != nil {
		t.Fatal(err)
	}

	sandbox, err := resolveSandboxRoot(filepath.Join(alias, "sandbox"))
	if err != nil {
		t.Fatal(err)
	}
	if !pathsOverlap(resolvedSource, sandbox) {
		t.Fatalf("resolved sandbox %q does not overlap checkout %q", sandbox, resolvedSource)
	}
}

func TestIsolatedEnvironmentOverridesUserDataPathsAndCredentials(t *testing.T) {
	current := []string{
		"HOME=/Users/person", "CODEX_HOME=/Users/person/.codex", "CLAUDE_CONFIG_DIR=/Users/person/.claude",
		"SSH_AUTH_SOCK=/tmp/agent.sock", "GITHUB_TOKEN=private-token", "HAWS_PACKAGE_DIR=/Applications/HAWS",
		"HAWS_TEST_FAIL_BEFORE_RENAME=1", "GIT_DIR=/Users/person/.git", "OPENAI_API_KEY=private-key", "PATH=/usr/bin",
	}
	env := strings.Join(isolatedEnvironment(filepath.Join(os.TempDir(), "haws-sandbox-test"), false), "\n")
	for _, want := range []string{
		"HOME=" + filepath.Join(os.TempDir(), "haws-sandbox-test", "home"),
		"CODEX_HOME=" + filepath.Join(os.TempDir(), "haws-sandbox-test", "home", ".codex"),
		"HAWS_SECOND_BRAIN_DIR=" + filepath.Join(os.TempDir(), "haws-sandbox-test", "data", "secondbrain"),
	} {
		if !strings.Contains(env, want) {
			t.Errorf("isolated environment missing %q", want)
		}
	}
	if got := strings.Join(replaceEnvironment(current, map[string]string{"HOME": "/sandbox", "CODEX_HOME": "/sandbox/.codex"}, nil), "\n"); strings.Contains(got, "person") || strings.Contains(got, "agent.sock") || strings.Contains(got, "private-token") || strings.Contains(got, "private-key") || strings.Contains(got, "HAWS_TEST_") {
		t.Fatalf("user paths, credentials, or inherited HAWS overrides leaked into child environment: %s", got)
	}
}

func gitTest(t *testing.T, directory string, args ...string) {
	t.Helper()
	command := exec.Command("git", append([]string{"-C", directory}, args...)...)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, output)
	}
}

func writeTestFile(t *testing.T, root, relative, contents string) {
	t.Helper()
	path := filepath.Join(root, relative)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readTestFile(t *testing.T, root, relative string) string {
	t.Helper()
	contents, err := os.ReadFile(filepath.Join(root, relative))
	if err != nil {
		t.Fatal(err)
	}
	return string(contents)
}
