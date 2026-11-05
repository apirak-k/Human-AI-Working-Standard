package settings

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func catalogFile(t *testing.T, root, name, body string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestCatalogPreservesSourceIdentityAndDisabledAliases(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	catalogFile(t, root, ".gitmodules", "[submodule \"demo\"]\npath = skills/packs/demo\nurl = https://github.com/example/demo.git\n")
	catalogFile(t, root, "skills/packs/demo/alpha/SKILL.md", "---\nname: alpha\ndescription: Alpha skill\n---\n")
	catalogFile(t, root, "skills/packs/demo/beta/skill.md", "---\nname: beta\ndescription: >\n  Beta first line\n  Not included\n---\n")
	catalogFile(t, root, "skills/custom/local/SKILL.md", "---\nname: alpha\n---\nLocal skill\n")
	catalogFile(t, root, "skills/skills.disabled", "alpha\n")
	store := NewStore(root)
	sources, err := store.Sources(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(sources) != 2 || sources[0].ID != "demo::skills/packs/demo" {
		t.Fatalf("sources: %+v", sources)
	}
	skills, err := store.Skills(context.Background(), sources, []string{"demo::skills/packs/demo::alpha", "beta/skill.md"})
	if err != nil {
		t.Fatal(err)
	}
	if len(skills) != 3 || skills[0].Enabled || skills[1].Enabled || !skills[2].Enabled {
		t.Fatalf("skills: %+v", skills)
	}
	if skills[1].Description != "Beta first line" {
		t.Fatal(skills[1].Description)
	}
	baseline, err := store.BaselineDisabledSkills()
	if err != nil || len(baseline) != 1 || baseline[0] != "alpha" {
		t.Fatalf("baseline %v, %v", baseline, err)
	}
}

func TestCatalogUsesDeviceMirrorAndFiltersEntrypoints(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	catalogFile(t, root, "state/skill-sources/registry.tsv", "demo\tskills/packs/demo\thttps://github.com/example/demo\n")
	catalogFile(t, root, "state/skill-sources/skills/packs/demo/one/SKILL.md", "---\nname: real\n---\n")
	catalogFile(t, root, "state/skill-sources/skills/packs/demo/.openclaw/two/SKILL.md", "---\nname: filtered\n---\n")
	catalogFile(t, root, "state/skill-sources/skills/packs/demo/three/SKILL.md", "---\nname: real\n---\n")
	store := NewStore(root)
	sources, err := store.Sources(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	skills, err := store.Skills(context.Background(), sources, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(sources) != 1 || sources[0].ID != "device-demo::skills/packs/demo" || len(skills) != 1 || skills[0].Name != "real" {
		t.Fatalf("sources=%+v skills=%+v", sources, skills)
	}
}

func TestSkillMetadataBoundsUnicodeByCharacters(t *testing.T) {
	contents := []byte("---\nname: unicode\ndescription: " + strings.Repeat("ก", 70) + "\n---\n")
	_, description := skillMetadata(contents, "fallback")
	want := strings.Repeat("ก", 57) + "..."
	if description != want {
		t.Fatalf("Unicode description = %q, want %q", description, want)
	}
}
