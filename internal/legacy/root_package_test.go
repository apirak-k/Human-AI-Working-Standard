package legacy

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestPackagedRuntimeStopsGitDiscoveringParentCheckout(t *testing.T) {
	parent := t.TempDir()
	if output, err := exec.Command("git", "init", parent).CombinedOutput(); err != nil {
		t.Fatalf("init parent: %v: %s", err, output)
	}
	root := filepath.Join(parent, "package", "runtime")
	for _, name := range []string{"ANTI_PATTERNS.md", "USER_PREFERENCES.md", "WORKFLOW.md"} {
		file := filepath.Join(root, "secondbrain", name)
		if err := os.MkdirAll(filepath.Dir(file), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte("seed"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	t.Setenv("GIT_CEILING_DIRECTORIES", "")
	if _, err := preparePackageRoot(root); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command("git", "-C", root, "rev-parse", "--show-toplevel")
	if output, err := cmd.CombinedOutput(); err == nil {
		t.Fatalf("discovered parent checkout: %s", output)
	}
}

func TestExplicitPackageRootResolvesRuntime(t *testing.T) {
	pkg := t.TempDir()
	if err := os.WriteFile(filepath.Join(pkg, "haws.sh"), []byte("launcher"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pkg, "package-manifest.json"), []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	root := filepath.Join(pkg, "runtime")
	if err := os.MkdirAll(filepath.Join(root, "secondbrain"), 0700); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"haws.sh", "secondbrain/ANTI_PATTERNS.md", "secondbrain/USER_PREFERENCES.md", "secondbrain/WORKFLOW.md"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte("fixture"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("HAWS_ROOT", pkg)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("GIT_CEILING_DIRECTORIES", "")
	got, err := FindRoot()
	if err != nil || got != root {
		t.Fatalf("FindRoot = %q, %v; want %q", got, err, root)
	}
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	got, err = FindRoot()
	if err != nil || got != root || os.Getenv("HAWS_STATE_DIR") != filepath.Join(pkg, "data", "state") {
		t.Fatalf("explicit runtime did not initialize package data: %q %v", got, err)
	}
}

func TestSeedCreationPreservesExistingFileAndCleansFailedStaging(t *testing.T) {
	dir := t.TempDir()
	dest := filepath.Join(dir, "seed.md")
	if err := os.WriteFile(dest, []byte("personal"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := writeSeed(dest, []byte("default")); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(dest); err != nil || string(got) != "personal" {
		t.Fatalf("existing seed = %q, %v", got, err)
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Fatalf("left staging files: %v", entries)
	}
}
