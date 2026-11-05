package settings

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestDraftIsReadOnlyAndResetUsesBaseline(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	catalogFile(t, root, "skills/custom/alpha/SKILL.md", "---\nname: alpha\n---\n")
	catalogFile(t, root, "skills/skills.disabled", "alpha\n")
	d, err := NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if d.Dirty() {
		t.Fatal("fresh draft dirty")
	}
	if err := d.LoadCatalog(context.Background()); err != nil {
		t.Fatal(err)
	}
	if d.Dirty() {
		t.Fatal("catalog made draft dirty")
	}
	if err := d.Reset(context.Background()); err != nil {
		t.Fatal(err)
	}
	if d.Skills[0].Enabled {
		t.Fatal("default ignored tracked disabled baseline")
	}
	if _, err := os.Stat("state"); !os.IsNotExist(err) {
		t.Fatalf("draft wrote state: %v", err)
	}
}

func TestDraftSourceChangesValidateWithoutMutation(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	d, err := NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	for _, url := range []string{"http://github.com/a/b", "https://github.com/a/../b", "https://evil.test/a/b", "https://github.com/a/b?x=y"} {
		if err := d.AddSource(context.Background(), url); err == nil {
			t.Fatalf("accepted %q", url)
		}
	}
	if err := d.AddSource(context.Background(), "https://github.com/example/demo.git"); err != nil {
		t.Fatal(err)
	}
	if err := d.AddSource(context.Background(), "https://github.com/example/demo"); err == nil {
		t.Fatal("duplicate accepted")
	}
	if len(d.Repositories()) != 1 || !d.Dirty() {
		t.Fatal("source not drafted")
	}
	d.RemoveSource("url:https://github.com/example/demo.git")
	if d.Dirty() {
		t.Fatal("reverted source still dirty")
	}
}

func TestDraftRetainsDisabledSkillsFromUnavailableSources(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	catalogFile(t, root, "state/skills.disabled", "missing::skills/packs/missing::secret\n")
	catalogFile(t, root, "skills/custom/alpha/SKILL.md", "---\nname: alpha\n---\n")
	d, err := NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.LoadCatalog(context.Background()); err != nil {
		t.Fatal(err)
	}
	d.Skills[0].Enabled = false
	if !sameSelection(d.SavedState().DisabledSkills, []string{"missing::skills/packs/missing::secret", "custom::skills/custom::alpha"}) {
		t.Fatal(d.SavedState().DisabledSkills)
	}
}

func TestDraftResetRebasesNewSkills(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	catalogFile(t, root, "skills/custom/alpha/SKILL.md", "---\nname: alpha\n---\n")
	d, err := NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	if err := d.LoadCatalog(context.Background()); err != nil {
		t.Fatal(err)
	}
	catalogFile(t, root, "skills/custom/beta/SKILL.md", "---\nname: beta\n---\n")
	if err := d.Reset(context.Background()); err != nil {
		t.Fatal(err)
	}
	_ = d.Dirty()
	_ = d.SavedState()
	_ = d.NeedsIntegration(true)
	if len(d.Skills) != 2 {
		t.Fatal(d.Skills)
	}
}
