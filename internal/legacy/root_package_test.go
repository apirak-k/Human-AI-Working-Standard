package legacy

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/migration"
)

func TestPackagedRuntimeStopsGitDiscoveringParentCheckout(t *testing.T) {
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_ROOT", "")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", "")
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
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("GIT_CEILING_DIRECTORIES", "")
	got, err := FindRoot()
	wantRoot, resolveErr := filepath.EvalSymlinks(root)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	if err != nil || got != wantRoot {
		t.Fatalf("FindRoot = %q, %v; want %q", got, err, wantRoot)
	}
	wantPackage, resolveErr := filepath.EvalSymlinks(pkg)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	got, err = FindRoot()
	if err != nil || got != wantRoot || os.Getenv("HAWS_STATE_DIR") != filepath.Join(wantPackage, "data", "state") {
		t.Fatalf("explicit runtime did not initialize package data: %q %v", got, err)
	}
}

func TestVersionedPackageRuntimeKeepsSharedPackageData(t *testing.T) {
	pkg := t.TempDir()
	if err := os.WriteFile(filepath.Join(pkg, "package-manifest.json"), []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	legacySettings := filepath.Join(pkg, "runtime", "ai-configs", "environments.disabled")
	if err := os.MkdirAll(filepath.Dir(legacySettings), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(legacySettings, []byte("gemini\n"), 0600); err != nil {
		t.Fatal(err)
	}
	runtimeRoot := filepath.Join(pkg, "versions", "v1.2.3", "runtime")
	for _, name := range []string{"haws.sh", "secondbrain/ANTI_PATTERNS.md", "secondbrain/USER_PREFERENCES.md", "secondbrain/WORKFLOW.md"} {
		filename := filepath.Join(runtimeRoot, name)
		if err := os.MkdirAll(filepath.Dir(filename), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, []byte("new package seed"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	brain := filepath.Join(pkg, "data", "secondbrain")
	if err := os.MkdirAll(brain, 0700); err != nil {
		t.Fatal(err)
	}
	personal := filepath.Join(brain, "USER_PREFERENCES.md")
	if err := os.WriteFile(personal, []byte("personal content"), 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", "")
	t.Setenv("HAWS_ROOT", "")
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	t.Setenv("GIT_CEILING_DIRECTORIES", "")

	got, err := ConfigurePackageRuntime(pkg, runtimeRoot)
	wantRuntime, resolveErr := filepath.EvalSymlinks(runtimeRoot)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	if err != nil || got != wantRuntime {
		t.Fatalf("ConfigurePackageRuntime() = %q, %v; want %q", got, err, wantRuntime)
	}
	initialCeiling := os.Getenv("GIT_CEILING_DIRECTORIES")
	wantPackage, resolveErr := filepath.EvalSymlinks(pkg)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	wantBrain := filepath.Join(wantPackage, "data", "secondbrain")
	if os.Getenv("HAWS_STATE_DIR") != filepath.Join(wantPackage, "data", "state") || os.Getenv("HAWS_SECOND_BRAIN_DIR") != wantBrain {
		t.Fatalf("package state paths = %q / %q", os.Getenv("HAWS_STATE_DIR"), os.Getenv("HAWS_SECOND_BRAIN_DIR"))
	}
	settingsPath := filepath.Join(wantPackage, "data", "state", "environments.disabled")
	if os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE") != settingsPath {
		t.Fatalf("disabled environments path = %q; want %q", os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE"), settingsPath)
	}
	if contents, err := os.ReadFile(settingsPath); err != nil || string(contents) != "gemini\n" {
		t.Fatalf("migrated settings = %q, %v", contents, err)
	}
	if contents, err := os.ReadFile(legacySettings); err != nil || string(contents) != "gemini\n" {
		t.Fatalf("legacy settings source = %q, %v; expected it to remain", contents, err)
	}
	if got, err := FindRoot(); err != nil || got != wantRuntime {
		t.Fatalf("FindRoot() after runtime selection = %q, %v; want %q", got, err, wantRuntime)
	}
	if got := os.Getenv("GIT_CEILING_DIRECTORIES"); got != initialCeiling {
		t.Fatalf("repeated runtime selection grew GIT_CEILING_DIRECTORIES: %q -> %q", initialCeiling, got)
	}
	if contents, err := os.ReadFile(personal); err != nil || string(contents) != "personal content" {
		t.Fatalf("personal Second Brain content = %q, %v", contents, err)
	}
}

func TestConfiguredMigrationProfileReusesLegacyStateAndSecondBrain(t *testing.T) {
	pkg := t.TempDir()
	if err := os.WriteFile(filepath.Join(pkg, "package-manifest.json"), []byte("{}"), 0o600); err != nil {
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
	if err := os.MkdirAll(filepath.Join(stateDir, "skill-sources"), 0o700); err != nil {
		t.Fatal(err)
	}
	settings := filepath.Join(stateDir, "settings.tsv")
	if err := os.WriteFile(settings, []byte("schema_version\t1\nauto_update_skills\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	brainDir := filepath.Join(legacyRoot, "secondbrain")
	if err := os.Mkdir(brainDir, 0o700); err != nil {
		t.Fatal(err)
	}
	personal := filepath.Join(brainDir, "personal.md")
	if err := os.WriteFile(personal, []byte("keep me"), 0o600); err != nil {
		t.Fatal(err)
	}
	runtimeRoot := filepath.Join(pkg, "runtime")
	for _, name := range []string{"haws.sh", "secondbrain/ANTI_PATTERNS.md", "secondbrain/USER_PREFERENCES.md", "secondbrain/WORKFLOW.md"} {
		filename := filepath.Join(runtimeRoot, name)
		if err := os.MkdirAll(filepath.Dir(filename), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, []byte("package seed"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	profile, err := migration.BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	if err := migration.SavePackageProfile(pkg, profile); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_ROOT", "")
	t.Setenv("HAWS_REPO_DIR", "")
	t.Setenv("HAWS_STATE_DIR", filepath.Join(pkg, "data", "state"))
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(pkg, "data", "secondbrain"))
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", filepath.Join(pkg, "data", "state", "environments.disabled"))
	t.Setenv("GIT_CEILING_DIRECTORIES", "")
	if _, err := ConfigurePackageRuntime(pkg, runtimeRoot); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("HAWS_REPO_DIR") != profile.LegacyRoot || os.Getenv("HAWS_STATE_DIR") != profile.StateDir || os.Getenv("HAWS_SECOND_BRAIN_DIR") != profile.SecondBrainDir {
		t.Fatalf("migration paths were not activated: repo=%q state=%q brain=%q", os.Getenv("HAWS_REPO_DIR"), os.Getenv("HAWS_STATE_DIR"), os.Getenv("HAWS_SECOND_BRAIN_DIR"))
	}
	if os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE") != filepath.Join(profile.StateDir, "environments.disabled") {
		t.Fatalf("disabled-environment settings still use package data: %q", os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE"))
	}
	if contents, err := os.ReadFile(settings); err != nil || string(contents) != "schema_version\t1\nauto_update_skills\toff\n" {
		t.Fatalf("legacy settings changed: %q, %v", contents, err)
	}
	if contents, err := os.ReadFile(personal); err != nil || string(contents) != "keep me" {
		t.Fatalf("legacy personal data changed: %q, %v", contents, err)
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

func TestPackageRuntimeDoesNotWriteThroughSecondBrainSymlink(t *testing.T) {
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_ROOT", "")
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", "")
	pkg := t.TempDir()
	if err := os.WriteFile(filepath.Join(pkg, "package-manifest.json"), []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	runtimeRoot := filepath.Join(pkg, "runtime")
	for _, name := range []string{"haws.sh", "secondbrain/ANTI_PATTERNS.md", "secondbrain/USER_PREFERENCES.md", "secondbrain/WORKFLOW.md"} {
		filename := filepath.Join(runtimeRoot, name)
		if err := os.MkdirAll(filepath.Dir(filename), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, []byte("seed"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	external := t.TempDir()
	brain := filepath.Join(pkg, "data", "secondbrain")
	if err := os.MkdirAll(filepath.Dir(brain), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, brain); err != nil {
		t.Skipf("creating a directory symlink is unavailable: %v", err)
	}
	if _, err := ConfigurePackageRuntime(pkg, runtimeRoot); err == nil {
		t.Fatal("ConfigurePackageRuntime() accepted a symlinked Second Brain directory")
	}
	if entries, err := os.ReadDir(external); err != nil || len(entries) != 0 {
		t.Fatalf("external Second Brain path changed: entries=%v err=%v", entries, err)
	}
}
