package migration

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func legacyFixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, ".git"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("legacy runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		t.Fatal(err)
	}
	state := filepath.Join(stateDir, "settings.tsv")
	if err := os.WriteFile(state, []byte("schema_version\t1\nauto_update\toff\n"), 0600); err != nil {
		t.Fatal(err)
	}
	brainDir := filepath.Join(root, "secondbrain")
	if err := os.Mkdir(brainDir, 0700); err != nil {
		t.Fatal(err)
	}
	brain := filepath.Join(brainDir, "personal.md")
	if err := os.WriteFile(brain, []byte("private note"), 0600); err != nil {
		t.Fatal(err)
	}
	return root, state, brain
}

func packageFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "package-manifest.json"), []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestBuildProfileReferencesExistingLegacyDataWithoutCopying(t *testing.T) {
	root, state, brain := legacyFixture(t)
	profile, err := BuildProfile(root, "", "")
	if err != nil {
		t.Fatal(err)
	}
	resolvedRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	resolvedState, err := filepath.EvalSymlinks(filepath.Dir(state))
	if err != nil {
		t.Fatal(err)
	}
	resolvedBrain, err := filepath.EvalSymlinks(filepath.Dir(brain))
	if err != nil {
		t.Fatal(err)
	}
	if profile.LegacyRoot != resolvedRoot || profile.StateDir != resolvedState || profile.SecondBrainDir != resolvedBrain {
		t.Fatalf("profile = %#v", profile)
	}
	if contents, err := os.ReadFile(state); err != nil || string(contents) != "schema_version\t1\nauto_update\toff\n" {
		t.Fatalf("legacy settings changed: %q, %v", contents, err)
	}
	if contents, err := os.ReadFile(brain); err != nil || string(contents) != "private note" {
		t.Fatalf("legacy Second Brain changed: %q, %v", contents, err)
	}
}

func TestBuildProfileAcceptsExplicitExistingStateAndBrainDirectories(t *testing.T) {
	root, _, _ := legacyFixture(t)
	stateDir := t.TempDir()
	brainDir := t.TempDir()
	profile, err := BuildProfile(root, stateDir, brainDir)
	if err != nil {
		t.Fatal(err)
	}
	resolvedState, err := filepath.EvalSymlinks(stateDir)
	if err != nil {
		t.Fatal(err)
	}
	resolvedBrain, err := filepath.EvalSymlinks(brainDir)
	if err != nil {
		t.Fatal(err)
	}
	if profile.StateDir != resolvedState || profile.SecondBrainDir != resolvedBrain {
		t.Fatalf("profile = %#v; explicit directories were not preserved", profile)
	}
}

func TestBuildProfileRejectsIncompleteLegacyInstallation(t *testing.T) {
	root := t.TempDir()
	if err := os.Mkdir(filepath.Join(root, ".git"), 0700); err != nil {
		t.Fatal(err)
	}
	if _, err := BuildProfile(root, "", ""); err == nil {
		t.Fatal("BuildProfile() accepted a directory without haws.sh and state")
	}
}

func TestSaveProfileIsCreateOnlyAndLoadValidatesIt(t *testing.T) {
	legacyRoot, _, _ := legacyFixture(t)
	profile, err := BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	packageRoot := packageFixture(t)
	if err := SavePackageProfile(packageRoot, profile); err != nil {
		t.Fatal(err)
	}
	loaded, exists, err := LoadPackageProfile(packageRoot)
	if err != nil || !exists || loaded != profile {
		t.Fatalf("LoadPackageProfile() = %#v, %v, %v", loaded, exists, err)
	}
	profilePath := ProfilePath(packageRoot)
	original, err := os.ReadFile(profilePath)
	if err != nil {
		t.Fatal(err)
	}
	err = SavePackageProfile(packageRoot, profile)
	if !errors.Is(err, ErrProfileExists) {
		t.Fatalf("second SavePackageProfile() error = %v; want ErrProfileExists", err)
	}
	if contents, err := os.ReadFile(profilePath); err != nil || string(contents) != string(original) {
		t.Fatalf("existing profile changed: %q, %v", contents, err)
	}
}

func TestLoadProfileRejectsSymlinkAndMalformedProfile(t *testing.T) {
	root := packageFixture(t)
	profilePath := ProfilePath(root)
	if err := os.MkdirAll(filepath.Dir(profilePath), 0700); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(t.TempDir(), "outside.json")
	if err := os.WriteFile(target, []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, profilePath); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	if _, _, err := LoadPackageProfile(root); err == nil {
		t.Fatal("LoadPackageProfile() accepted a symlinked profile")
	}
	if err := os.Remove(profilePath); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(profilePath, []byte(`{"schema_version":1,"legacy_root":"relative"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if _, _, err := LoadPackageProfile(root); err == nil {
		t.Fatal("LoadPackageProfile() accepted an invalid profile")
	}
}

func TestApplyPackageProfileEnvironmentPreservesExplicitOverrides(t *testing.T) {
	legacyRoot, _, _ := legacyFixture(t)
	profile, err := BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	packageRoot := packageFixture(t)
	explicitRepo := t.TempDir()
	explicitState := t.TempDir()
	explicitBrain := t.TempDir()
	t.Setenv("HAWS_REPO_DIR", explicitRepo)
	t.Setenv("HAWS_STATE_DIR", filepath.Join(packageRoot, "data", "state"))
	t.Setenv("HAWS_SECOND_BRAIN_DIR", explicitBrain)
	if err := ApplyProfileEnvironmentForPackage(profile, packageRoot); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("HAWS_REPO_DIR") != explicitRepo || os.Getenv("HAWS_STATE_DIR") != profile.StateDir || os.Getenv("HAWS_SECOND_BRAIN_DIR") != explicitBrain {
		t.Fatal("profile did not override package defaults while preserving explicit paths")
	}
	t.Setenv("HAWS_STATE_DIR", explicitState)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", explicitBrain)
	if err := ApplyProfileEnvironmentForPackage(profile, packageRoot); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("HAWS_REPO_DIR") != explicitRepo || os.Getenv("HAWS_STATE_DIR") != explicitState || os.Getenv("HAWS_SECOND_BRAIN_DIR") != explicitBrain {
		t.Fatal("explicit path overrides were replaced")
	}
}

func TestClearProfileRemovesOnlyProfileAndRejectsChangedPreview(t *testing.T) {
	legacyRoot, state, brain := legacyFixture(t)
	profile, err := BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	packageRoot := packageFixture(t)
	if err := SavePackageProfile(packageRoot, profile); err != nil {
		t.Fatal(err)
	}
	changed := profile
	changed.StateDir = filepath.Join(filepath.Dir(state), "different")
	if err := ClearPackageProfile(packageRoot, changed); err == nil {
		t.Fatal("ClearPackageProfile() removed a profile changed after preview")
	}
	if err := ClearPackageProfile(packageRoot, profile); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := LoadPackageProfile(packageRoot); err != nil || exists {
		t.Fatalf("profile still exists after clear: exists=%v err=%v", exists, err)
	}
	if _, err := os.Stat(state); err != nil {
		t.Fatalf("legacy state was removed: %v", err)
	}
	if _, err := os.Stat(brain); err != nil {
		t.Fatalf("legacy Second Brain was removed: %v", err)
	}
	if !strings.Contains(ProfilePath(packageRoot), filepath.Join("data", "state")) {
		t.Fatal("migration profile is not stored in package data")
	}
}

func TestClearProfileCanRecoverAfterLegacyEntrypointDisappears(t *testing.T) {
	legacyRoot, state, brain := legacyFixture(t)
	profile, err := BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	packageRoot := packageFixture(t)
	if err := SavePackageProfile(packageRoot, profile); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(legacyRoot, "haws.sh"), filepath.Join(legacyRoot, "haws.sh.moved")); err != nil {
		t.Fatal(err)
	}
	if _, _, err := LoadPackageProfile(packageRoot); err == nil {
		t.Fatal("normal profile load should report the missing legacy entrypoint")
	}
	stale, exists, err := LoadPackageProfileForClear(packageRoot)
	if err != nil || !exists || stale != profile {
		t.Fatalf("clear preview profile=%#v exists=%v err=%v", stale, exists, err)
	}
	if err := ClearPackageProfile(packageRoot, stale); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := LoadPackageProfileForClear(packageRoot); err != nil || exists {
		t.Fatalf("migration reference remains after recovery clear: exists=%v err=%v", exists, err)
	}
	for _, filename := range []string{state, brain} {
		if _, err := os.Stat(filename); err != nil {
			t.Fatalf("clearing stale profile changed legacy data %q: %v", filename, err)
		}
	}
}
