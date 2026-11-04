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
