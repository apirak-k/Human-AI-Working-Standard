package settings

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

const legacySkillBaseline = "# HAWS Disabled Skills (source-aware)\nbaseline-disabled\n"
const legacySkillSelection = "# HAWS Disabled Skills (source-aware)\nlegacy-disabled\n"

func legacySkillFixture(t *testing.T) Store {
	t.Helper()
	s := testStore(t)
	t.Setenv("HAWS_REPO_DIR", s.Root)
	fixtureGit(t, s.Root, "init", "-b", "main")
	fixtureGit(t, s.Root, "config", "user.email", "test@example.invalid")
	fixtureGit(t, s.Root, "config", "user.name", "Test")
	put(t, filepath.Join(s.Root, "skills", "skills.disabled"), legacySkillBaseline)
	fixtureGit(t, s.Root, "add", "skills/skills.disabled")
	fixtureGit(t, s.Root, "commit", "-m", "baseline")
	put(t, filepath.Join(s.Root, "skills", "skills.disabled"), legacySkillSelection)
	return s
}

func TestLegacySkillMigrationRestoresTrackedBaselineAfterSave(t *testing.T) {
	s := legacySkillFixture(t)
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(s.Root, "skills", "skills.disabled")
	if err := s.MigrateLegacySkillState(context.Background(), state); err == nil {
		t.Fatal("migrated without a persisted selection")
	}
	data, _ := os.ReadFile(legacy)
	if string(data) != legacySkillSelection {
		t.Fatal("changed legacy file before Save")
	}
	state.DisabledSkills = []string{"newly-selected-disabled"}
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	indexBefore := fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled")
	if err := s.MigrateLegacySkillState(context.Background(), state); err != nil {
		t.Fatal(err)
	}
	data, err = os.ReadFile(legacy)
	if err != nil || string(data) != legacySkillBaseline {
		t.Fatalf("baseline not restored: %q, %v", data, err)
	}
	if fixtureGit(t, s.Root, "status", "--porcelain", "--", "skills/skills.disabled") != "" {
		t.Fatal("legacy file remains dirty")
	}
	if fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled") != indexBefore {
		t.Fatal("changed Git index")
	}
	persisted, err := s.Load()
	if err != nil || len(persisted.DisabledSkills) != 1 || persisted.DisabledSkills[0] != "newly-selected-disabled" {
		t.Fatalf("lost desired selection: %+v, %v", persisted, err)
	}
}

func TestLegacySkillMigrationPreservesStagedUnownedAndExistingState(t *testing.T) {
	for _, mode := range []string{"staged", "unowned", "existing-state"} {
		t.Run(mode, func(t *testing.T) {
			s := legacySkillFixture(t)
			legacy := filepath.Join(s.Root, "skills", "skills.disabled")
			switch mode {
			case "staged":
				fixtureGit(t, s.Root, "add", "skills/skills.disabled")
			case "unowned":
				put(t, legacy, "# user list\nlegacy-disabled\n")
			case "existing-state":
				put(t, s.Path("skills.disabled"), "device-disabled\n")
			}
			before, err := os.ReadFile(legacy)
			if err != nil {
				t.Fatal(err)
			}
			indexBefore := fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled")
			state, err := s.Load()
			if err != nil {
				t.Fatal(err)
			}
			if err := s.Save(state); err != nil {
				t.Fatal(err)
			}
			if err := s.MigrateLegacySkillState(context.Background(), state); err != nil {
				t.Fatal(err)
			}
			after, err := os.ReadFile(legacy)
			if err != nil || string(after) != string(before) {
				t.Fatalf("changed protected legacy file: %q, %v", after, err)
			}
			if fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled") != indexBefore {
				t.Fatal("changed protected index")
			}
		})
	}
}

func TestLegacySkillMigrationRefusesChangesSinceLoad(t *testing.T) {
	s := legacySkillFixture(t)
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	legacy := filepath.Join(s.Root, "skills", "skills.disabled")
	const updated = "# HAWS Disabled Skills\nchanged-after-preview\n"
	put(t, legacy, updated)
	if err := s.MigrateLegacySkillState(context.Background(), state); err == nil {
		t.Fatal("overwrote changed legacy selection")
	}
	data, err := os.ReadFile(legacy)
	if err != nil || string(data) != updated {
		t.Fatal("lost later legacy change")
	}
}

func TestLegacySkillMigrationRequiresMatchingPersistedSelection(t *testing.T) {
	s := legacySkillFixture(t)
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	put(t, s.Path("skills.disabled"), "different-device-selection\n")
	if err := s.MigrateLegacySkillState(context.Background(), state); err == nil {
		t.Fatal("restored baseline despite mismatched device selection")
	}
	data, err := os.ReadFile(filepath.Join(s.Root, "skills", "skills.disabled"))
	if err != nil || string(data) != legacySkillSelection {
		t.Fatal("lost legacy selection")
	}
}

func TestLegacySkillBaselineUsesTrackedDefaultsWithoutMigrationWrites(t *testing.T) {
	s := legacySkillFixture(t)
	path := filepath.Join(s.Root, "skills", "skills.disabled")
	indexBefore := fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled")
	baseline, err := s.BaselineDisabledSkills()
	if err != nil || len(baseline) != 1 || baseline[0] != "baseline-disabled" {
		t.Fatalf("public reset baseline = %v, %v", baseline, err)
	}
	got, err := s.legacySkillBaseline(context.Background(), path, []byte(legacySkillSelection))
	if err != nil || string(got) != legacySkillBaseline {
		t.Fatalf("reset baseline: %q, %v", got, err)
	}
	data, err := os.ReadFile(path)
	if err != nil || string(data) != legacySkillSelection {
		t.Fatal("baseline read changed legacy file")
	}
	if _, err := os.Stat(s.Dir); !os.IsNotExist(err) {
		t.Fatal("baseline read created state")
	}
	if fixtureGit(t, s.Root, "ls-files", "--stage", "skills/skills.disabled") != indexBefore {
		t.Fatal("baseline read changed index")
	}
}

func TestLegacySkillBaselinePreservesStagedUnownedAndDeviceSelections(t *testing.T) {
	for _, mode := range []string{"staged", "unowned", "device-state"} {
		t.Run(mode, func(t *testing.T) {
			s := legacySkillFixture(t)
			path := filepath.Join(s.Root, "skills", "skills.disabled")
			contents := legacySkillSelection
			switch mode {
			case "staged":
				fixtureGit(t, s.Root, "add", "skills/skills.disabled")
			case "unowned":
				contents = "# user list\nuser-disabled\n"
				put(t, path, contents)
			case "device-state":
				put(t, s.Path("skills.disabled"), "device-disabled\n")
			}
			got, err := s.legacySkillBaseline(context.Background(), path, []byte(contents))
			if err != nil || string(got) != contents {
				t.Fatalf("protected baseline changed: %q, %v", got, err)
			}
		})
	}
}
