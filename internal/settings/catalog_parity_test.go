package settings

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
	"testing"
)

// The shell is an independent compatibility oracle, never a native dependency.
// All catalog and Git inputs live in t.TempDir; no command fetches a remote.
func parityFixture(t *testing.T) (string, Store) {
	t.Helper()
	// Preserve the host Bash executable before isolating HOME.
	if os.Getenv("HAWS_TEST_BASH") == "" {
		if home, err := os.UserHomeDir(); err == nil {
			candidate := filepath.Join(home, ".local", "bin", "bash")
			if info, err := os.Stat(candidate); err == nil && !info.IsDir() {
				t.Setenv("HAWS_TEST_BASH", candidate)
			}
		}
	}
	root := t.TempDir()
	root, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	for key, value := range map[string]string{
		"HOME": root, "HAWS_REPO_DIR": root, "HAWS_STATE_DIR": filepath.Join(root, "state"),
		"HAWS_SOURCE_ONLY": "1", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.DevNull,
		"GIT_TERMINAL_PROMPT": "0", "HAWS_TEST_ALLOW_LOCAL_SOURCES": "0",
	} {
		t.Setenv(key, value)
	}
	// Ignore inherited Git routing, which could otherwise escape the fixture.
	for _, key := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR"} {
		value, exists := os.LookupEnv(key)
		if err := os.Unsetenv(key); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			if exists {
				_ = os.Setenv(key, value)
			}
		})
	}
	return root, NewStore(root)
}

func parityShell(t *testing.T, root, operation string) string {
	t.Helper()
	_, current, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("locate catalog oracle")
	}
	script := filepath.Join(filepath.Dir(current), "..", "..", "haws.sh")
	var bash string
	candidates := []string{os.Getenv("HAWS_TEST_BASH"), "/opt/homebrew/bin/bash", "/usr/local/bin/bash"}
	if home, err := os.UserHomeDir(); err == nil {
		candidates = append(candidates, filepath.Join(home, ".local", "bin", "bash"))
	}
	if path, err := exec.LookPath("bash"); err == nil {
		candidates = append(candidates, path)
	}
	for _, candidate := range candidates {
		if candidate != "" && exec.Command(candidate, "-c", "((BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2)))").Run() == nil {
			bash = candidate
			break
		}
	}
	if bash == "" {
		t.Fatal("catalog parity tests require Bash 4.2+; set HAWS_TEST_BASH")
	}
	cmd := exec.CommandContext(context.Background(), bash, "-c", `
source "$1"
SCRIPT_DIR="$2"
unset HAWS_CATALOG_SOURCES_CACHE HAWS_CATALOG_SKILLS_CACHE
case "$3" in
  skills) catalog_skills ;;
  sources)
    while IFS=$'\t' read -r source_id source_path source_url revision; do
      source_dir="$(_catalog_runtime_source_dir "$source_path")"
      printf '%s\t%s\t%s\t%s\n' "$source_id" "$source_path" "$source_url" "$source_dir"
    done < <(_catalog_skill_sources)
    ;;
  baseline)
    _catalog_load_disabled_skill_keys baseline
    for key in "${!HAWS_CATALOG_DISABLED_SKILL_KEYS[@]}"; do printf '%s\n' "$key"; done
    ;;
esac
`, "catalog-parity", script, root, operation)
	cmd.Dir = root
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("shell catalog %s: %v\n%s", operation, err, output)
	}
	return strings.TrimSuffix(string(output), "\n")
}

func paritySkills(t *testing.T, root string, store Store, disabled []string) {
	t.Helper()
	sources, err := store.Sources(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	skills, err := store.Skills(context.Background(), sources, disabled)
	if err != nil {
		t.Fatal(err)
	}
	var rows []string
	for _, skill := range skills {
		active := 0
		if skill.Enabled {
			active = 1
		}
		rows = append(rows, fmt.Sprintf("%s\t%s\t%s\t%s\t%s\t%d", skill.SourceID, skill.ID, skill.Name, skill.Description, skill.Entrypoint, active))
	}
	if got, want := strings.Join(rows, "\n"), parityShell(t, root, "skills"); got != want {
		t.Errorf("native skills differ from haws.sh\ngot:\n%s\nwant:\n%s", got, want)
	}
}

func paritySources(t *testing.T, root string, store Store) {
	t.Helper()
	sources, err := store.Sources(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	var rows []string
	for _, source := range sources {
		rows = append(rows, strings.Join([]string{source.ID, source.Path, source.URL, source.Dir}, "\t"))
	}
	if got, want := strings.Join(rows, "\n"), parityShell(t, root, "sources"); got != want {
		t.Errorf("native sources differ from haws.sh\ngot:\n%s\nwant:\n%s", got, want)
	}
}

func TestCatalogParityMetadata(t *testing.T) {
	cases := []struct{ name, body string }{
		{"regular", "---\nname: example\ndescription: An ordinary skill\n---\nBody\n"},
		{"quoted", "---\nname: 'quoted-name'\ndescription: \"Quoted description\"\n---\n"},
		{"folded", "---\nname: folded\ndescription: >\n  First description line\n  Second line is not included\n---\n"},
		{"literal", "---\nname: literal\ndescription: |\n  First description line\n  Second line is not included\n---\n"},
		{"empty-description-block", "---\nname: empty-block\ndescription:\n  First description line\n---\n"},
		{"block-modifier", "---\nname: modifier\ndescription: >-\n  First description line\n---\n"},
		{"block-blank-line", "---\nname: blank-block\ndescription: >\n\n  First description line\n---\n"},
		{"missing-name", "---\ndescription: Fallback directory name\n---\n"},
		{"missing-description", "---\nname: body\n---\n# Heading\n\nFirst body paragraph.\n"},
		{"no-frontmatter", "# Heading\n\nFirst body paragraph.\n"},
		{"heading-only", "# Heading\n"},
		{"empty", ""},
		{"crlf", "---\r\nname: windows\r\ndescription: Windows description\r\n---\r\n"},
		{"name-inline-comment", "---\nname: example # explanatory comment\ndescription: Text\n---\n"},
		{"preserve-name-spacing", "---\nname: example  skill\ndescription: Text\n---\n"},
		{"preserve-description-spacing", "---\nname: spaced\ndescription: Text  with   spaces\n---\n"},
		{"leading-blank", "\n---\nname: delayed\ndescription: Frontmatter after blank\n---\nBody\n"},
		{"unclosed-frontmatter", "---\nname: unclosed\ndescription: Still found\n"},
		{"unterminated-name-line", "name: terminal"},
		{"description-first", "---\ndescription: First description\nname: after-description\n---\n"},
		{"long-description", "---\nname: long\ndescription: " + strings.Repeat("a", 90) + "\n---\n"},
		{"unicode-description", "---\nname: unicode\ndescription: " + strings.Repeat("ก", 70) + "\n---\n"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root, store := parityFixture(t)
			catalogFile(t, root, "skills/custom/fallback/SKILL.md", tc.body)
			paritySkills(t, root, store, nil)
		})
	}
}

func TestCatalogParityOrderingAliasesAndExclusions(t *testing.T) {
	root, store := parityFixture(t)
	catalogFile(t, root, ".gitmodules", "[submodule \"demo\"]\npath = skills/packs/demo\nurl = https://example.invalid/demo.git\n")
	for _, path := range []string{"skills/packs/demo/a/SKILL.md", "skills/packs/demo/b/SKILL.md", "skills/custom/a/SKILL.md"} {
		catalogFile(t, root, path, "---\nname: duplicate\ndescription: "+path+"\n---\n")
	}
	paths := []string{
		"full/SKILL.md", "short/SKILL.md", "path/skill.md", "enabled/SKILL.md",
		".openclaw/hidden/SKILL.md", "archify/.agents/skills/hidden/SKILL.md",
		"planning-with-files/hidden/SKILL.md", "planning-with-files/.agents/skills/visible/SKILL.md",
		"planning-with-files/skills/i18n/visible/SKILL.md", "ui-ux-pro-max/hidden/SKILL.md",
		"ui-ux-pro-max/.claude/skills/visible/SKILL.md", "caveman/plugins/hidden/SKILL.md",
	}
	for i, path := range paths {
		catalogFile(t, root, "skills/custom/"+path, fmt.Sprintf("---\nname: skill-%d\ndescription: Fixture skill\n---\n", i))
	}
	for i, name := range []string{"pi-planning-with-files", "planning-with-files-v3", "design-taste-frontend-v1"} {
		catalogFile(t, root, fmt.Sprintf("skills/custom/excluded-%d/SKILL.md", i), "---\nname: "+name+"\n---\n")
	}
	disabled := []string{"custom::skills/custom::skill-0", "skill-1", "path/skill.md"}
	catalogFile(t, root, "state/skills.disabled", strings.Join(disabled, "\n")+"\n")
	paritySources(t, root, store)
	paritySkills(t, root, store, disabled)
}

func TestCatalogParityBaselineDisabledFiles(t *testing.T) {
	root, store := parityFixture(t)
	catalogFile(t, root, "skills/skills.disabled", "# defaults\n alpha # inline\n beta\r\n")
	catalogFile(t, root, "skills.disabled", "gamma\n")
	catalogFile(t, root, "config/skills.disabled", "delta")
	catalogFile(t, root, "state/skills.disabled", "effective-only\n")
	got, err := store.BaselineDisabledSkills()
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Split(parityShell(t, root, "baseline"), "\n")
	slices.Sort(got)
	slices.Sort(want)
	if !slices.Equal(got, want) {
		t.Errorf("baseline disabled keys: got %q, want %q", got, want)
	}
}

func TestCatalogParitySourceMirrorSelection(t *testing.T) {
	for _, mode := range []string{"user-directory", "tracked-gitlink", "package-gitlink", "package-untracked", "registered-device"} {
		t.Run(mode, func(t *testing.T) {
			root, store := parityFixture(t)
			const sourcePath = "skills/packs/demo"
			catalogFile(t, root, ".gitmodules", "[submodule \"demo\"]\npath = "+sourcePath+"\nurl = https://example.invalid/demo.git\n")
			catalogFile(t, root, sourcePath+"/local/SKILL.md", "---\nname: local-skill\ndescription: Local directory\n---\n")
			mirror := filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(sourcePath))
			catalogFile(t, mirror, "mirrored/SKILL.md", "---\nname: mirror-skill\ndescription: Device mirror\n---\n")
			fixtureGit(t, mirror, "init", "-b", "main")
			fixtureGit(t, mirror, "-c", "user.email=test@example.invalid", "-c", "user.name=Test", "add", ".")
			fixtureGit(t, mirror, "-c", "user.email=test@example.invalid", "-c", "user.name=Test", "commit", "-m", "Fixture")
			revision := fixtureGit(t, mirror, "rev-parse", "HEAD")
			switch mode {
			case "tracked-gitlink":
				fixtureGit(t, root, "init", "-b", "main")
				fixtureGit(t, root, "update-index", "--add", "--cacheinfo", "160000,"+revision+","+sourcePath)
			case "package-gitlink":
				catalogFile(t, root, "source-revisions.tsv", sourcePath+"\t"+revision+"\n")
			case "package-untracked":
				catalogFile(t, root, "source-revisions.tsv", "skills/packs/other\t"+revision+"\n")
			case "registered-device":
				catalogFile(t, root, "state/skill-sources/registry.tsv", "demo\t"+sourcePath+"\thttps://example.invalid/demo.git\n")
			}
			paritySources(t, root, store)
			paritySkills(t, root, store, nil)
		})
	}
}

func TestCatalogParityMalformedDeviceRegistrations(t *testing.T) {
	root, store := parityFixture(t)
	catalogFile(t, root, "state/skill-sources/registry.tsv", strings.Join([]string{
		"good\tskills/packs/good\thttps://example.invalid/good.git",
		"bad name\tskills/packs/bad name\thttps://example.invalid/bad.git",
		"traversal\tskills/packs/../traversal\thttps://example.invalid/bad.git",
		"absolute\t/skills/packs/absolute\thttps://example.invalid/bad.git",
		"mismatch\tskills/packs/other\thttps://example.invalid/bad.git",
		"outside\tskills/custom/outside\thttps://example.invalid/bad.git",
		"empty\tskills/packs/empty\t",
		"option\tskills/packs/option\t--upload-pack=bad",
		"hostonly\tskills/packs/hostonly\thttps://example.invalid",
		"file\tskills/packs/file\tfile:///local/disabled",
		"extra\tskills/packs/extra\thttps://example.invalid/extra.git\tgarbage",
		"one-field",
	}, "\n"))
	catalogFile(t, root, "state/skill-sources/skills/packs/good/SKILL.md", "---\nname: valid\ndescription: Valid registered source\n---\n")
	paritySources(t, root, store)
	paritySkills(t, root, store, nil)
}
