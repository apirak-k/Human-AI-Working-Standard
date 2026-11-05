package settings

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func testStore(t *testing.T) Store {
	t.Helper()
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", "")
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return NewStore(root)
}

func put(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestLoadDefaultsAliasesAndCRLF(t *testing.T) {
	s := testStore(t)
	state, err := s.Load()
	if err != nil || state.Config != (Config{true, true}) {
		t.Fatalf("defaults: %+v, %v", state, err)
	}
	if _, err := os.Stat(s.Dir); !os.IsNotExist(err) {
		t.Fatal("Load created state")
	}
	put(t, s.Path("settings.tsv"), "schema_version\t1\r\nauto_update\toff\r\nauto_update_brain\toff\r\nsecond_brain\ton\r\nsecond_brain_remote\tgit@example.org:private/brain.git\r\nauto_update_skills\ton\r\nauto_update\toff\r\n")
	state, err = s.Load()
	if err != nil || state.Config != (Config{true, false}) {
		t.Fatalf("aliases: %+v, %v", state, err)
	}
}

func TestLoadRejectsMalformedAndUnsafeFiles(t *testing.T) {
	for _, content := range []string{"schema_version\t2\n", "unknown\ton\n", "auto_update\ttrue\n", "auto_update_brain\toff\textra\n", "second_brain_remote\t-file\n", "second_brain\tmaybe\n", strings.Repeat("x", (1<<20)+1)} {
		t.Run(content[:min(len(content), 30)], func(t *testing.T) {
			s := testStore(t)
			put(t, s.Path("settings.tsv"), content)
			if _, err := s.Load(); err == nil {
				t.Fatal("accepted invalid settings")
			}
		})
	}
	for _, name := range []string{"settings.tsv", "skills.disabled"} {
		t.Run(name+" symlink", func(t *testing.T) {
			s := testStore(t)
			target := filepath.Join(s.Root, "private")
			put(t, target, "")
			if err := os.MkdirAll(s.Dir, 0700); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(target, s.Path(name)); err != nil {
				t.Fatal(err)
			}
			if _, err := s.Load(); err == nil {
				t.Fatal("followed symlink")
			}
			if err := s.Save(State{Config: DefaultConfig()}); err == nil {
				t.Fatal("saved through symlink")
			}
		})
	}
}

func TestRoundTripPreservesPrivateFilesAndCompatibilityPaths(t *testing.T) {
	s := testStore(t)
	put(t, filepath.Join(s.Root, "config", "environments.disabled"), " # comment\r\n codex # disabled\r\nunknown\r\n")
	put(t, filepath.Join(s.Root, "skills.disabled"), "# legacy\r\nsource::my-skill\r\nmy-other-skill\n")
	put(t, s.Path("ownership.tsv"), "private ownership\n")
	put(t, s.Path("install.complete"), "private marker\n")
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(state.DisabledEnvironments, []string{"codex"}) || !reflect.DeepEqual(state.DisabledSkills, []string{"my-other-skill", "source::my-skill"}) {
		t.Fatalf("legacy lists: %+v", state)
	}
	state.Config = Config{false, true}
	state.DisabledEnvironments = []string{"gemini", "claude", "claude"}
	state.DisabledSkills = []string{"new::skill"}
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	got, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if got.Config != (Config{false, true}) || !reflect.DeepEqual(got.DisabledEnvironments, []string{"claude", "gemini"}) || !reflect.DeepEqual(got.DisabledSkills, []string{"new::skill"}) {
		t.Fatalf("roundtrip: %+v", got)
	}
	for name, want := range map[string]string{"ownership.tsv": "private ownership\n", "install.complete": "private marker\n"} {
		data, err := os.ReadFile(s.Path(name))
		if err != nil || string(data) != want {
			t.Fatalf("changed %s", name)
		}
	}
	data, _ := os.ReadFile(filepath.Join(s.Root, "skills.disabled"))
	if string(data) != "# legacy\r\nsource::my-skill\r\nmy-other-skill\n" {
		t.Fatal("rewrote legacy skill baseline")
	}
}

func TestSaveFailurePreservesPreviousState(t *testing.T) {
	s := testStore(t)
	initial := State{Config: DefaultConfig(), DisabledSkills: []string{"original"}, DisabledEnvironments: []string{"codex"}}
	if err := s.Save(initial); err != nil {
		t.Fatal(err)
	}
	files := []string{s.Path("settings.tsv"), s.Path("skills.disabled"), filepath.Join(s.Root, "ai-configs", "environments.disabled")}
	before := make(map[string]string)
	for _, path := range files {
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		before[path] = string(data)
	}
	loaded, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	loaded.Config.AutoUpdateSkills = false
	loaded.DisabledSkills = []string{"unsafe\ninjection"}
	if err := s.Save(loaded); err == nil {
		t.Fatal("accepted unsafe list entry")
	}
	loaded.DisabledSkills = []string{"changed"}
	if err := os.Mkdir(s.Path("sync.lock"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := s.Save(loaded); err == nil {
		t.Fatal("ignored active lock")
	}
	for path, want := range before {
		data, err := os.ReadFile(path)
		if err != nil || string(data) != want {
			t.Fatalf("failed save changed %s", path)
		}
	}
}

func TestSaveRejectsStaleDraft(t *testing.T) {
	s := testStore(t)
	if err := s.Save(State{Config: DefaultConfig()}); err != nil {
		t.Fatal(err)
	}
	first, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	stale, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	first.Config.AutoUpdateBrain = false
	if err := s.Save(first); err != nil {
		t.Fatal(err)
	}
	stale.DisabledSkills = []string{"should-not-save"}
	if err := s.Save(stale); err == nil {
		t.Fatal("overwrote newer state")
	}
	got, err := s.Load()
	if err != nil || got.Config.AutoUpdateBrain || len(got.DisabledSkills) != 0 {
		t.Fatalf("stale save affected state: %+v, %v", got, err)
	}
}

func TestStagingWriteFailurePreservesAllFiles(t *testing.T) {
	s := testStore(t)
	if err := s.Save(State{Config: DefaultConfig(), DisabledSkills: []string{"original"}}); err != nil {
		t.Fatal(err)
	}
	before, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	environmentDir := filepath.Join(s.Root, "ai-configs")
	if err := os.Chmod(environmentDir, 0500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(environmentDir, 0700) })
	probe, err := os.CreateTemp(environmentDir, "permission-probe")
	if err == nil {
		_ = probe.Close()
		_ = os.Remove(probe.Name())
		t.Skip("filesystem permissions do not restrict this process")
	}
	changed := before
	changed.Config.AutoUpdateBrain = false
	changed.DisabledSkills = []string{"changed"}
	changed.DisabledEnvironments = []string{"claude"}
	if err := s.Save(changed); err == nil {
		t.Fatal("Save succeeded with an unwritable destination")
	}
	after, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if after.Config != before.Config || !reflect.DeepEqual(after.DisabledSkills, before.DisabledSkills) || !reflect.DeepEqual(after.DisabledEnvironments, before.DisabledEnvironments) {
		t.Fatalf("failed write changed state: %+v", after)
	}
	for path, want := range before.loaded {
		got, err := os.ReadFile(path)
		if want.exists && (err != nil || string(got) != want.data) {
			t.Fatalf("failed write changed %s", path)
		}
	}
	entries, err := os.ReadDir(s.Dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if entry.Name() == "sync.lock" || strings.HasPrefix(entry.Name(), ".haws-settings-") {
			t.Fatalf("left temporary state %s", entry.Name())
		}
	}
}

func TestCommitFailureRollsBackEarlierReplacement(t *testing.T) {
	s := testStore(t)
	put(t, filepath.Join(s.Root, "first"), "first old\n")
	put(t, filepath.Join(s.Root, "first-stage"), "first new\n")
	put(t, filepath.Join(s.Root, "first-backup"), "first old\n")
	put(t, filepath.Join(s.Root, "second-stage"), "second new\n")
	// The second destination changed to a directory after staging completed.
	if err := os.Mkdir(filepath.Join(s.Root, "second"), 0700); err != nil {
		t.Fatal(err)
	}
	parent, err := os.OpenRoot(s.Root)
	if err != nil {
		t.Fatal(err)
	}
	defer parent.Close()
	err = commitStateFiles([]replacement{
		{path: filepath.Join(s.Root, "first"), parent: parent, name: "first", stage: "first-stage", backup: "first-backup", before: fileState{exists: true, data: "first old\n"}},
		{path: filepath.Join(s.Root, "second"), parent: parent, name: "second", stage: "second-stage", before: fileState{exists: true, data: "second old\n"}},
	})
	if err == nil {
		t.Fatal("commit accepted changed destination")
	}
	data, err := os.ReadFile(filepath.Join(s.Root, "first"))
	if err != nil || string(data) != "first old\n" {
		t.Fatalf("earlier replacement was not rolled back: %q, %v", data, err)
	}
	info, err := os.Stat(filepath.Join(s.Root, "second"))
	if err != nil || !info.IsDir() {
		t.Fatal("changed destination was overwritten")
	}
}

func TestRelativeStateAndPackageEnvironmentOverride(t *testing.T) {
	s := testStore(t)
	t.Setenv("HAWS_STATE_DIR", "isolated/state")
	t.Setenv("HAWS_PACKAGE_DIR", s.Root)
	override := filepath.Join(s.Root, "data", "environments.disabled")
	t.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", override)
	s = NewStore(s.Root)
	if s.Dir != filepath.Join(s.Root, "isolated", "state") {
		t.Fatalf("state override: %s", s.Dir)
	}
	put(t, override, "claude\n")
	put(t, filepath.Join(s.Root, "ai-configs", "environments.disabled"), "codex\n")
	state, err := s.Load()
	if err != nil || !reflect.DeepEqual(state.DisabledEnvironments, []string{"claude"}) {
		t.Fatalf("package override: %+v, %v", state, err)
	}
	state.DisabledEnvironments = nil
	if err := s.Save(state); err != nil {
		t.Fatal(err)
	}
	got, err := s.Load()
	if err != nil || len(got.DisabledEnvironments) != 0 {
		t.Fatalf("empty override: %+v, %v", got, err)
	}
}

func TestRefusesSymlinkedStateAncestor(t *testing.T) {
	s := testStore(t)
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(s.Root, ".haws")); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Load(); err == nil {
		t.Fatal("Load followed state ancestor")
	}
	if err := s.Save(State{Config: DefaultConfig()}); err == nil {
		t.Fatal("Save followed state ancestor")
	}
	entries, err := os.ReadDir(outside)
	if err != nil || len(entries) != 0 {
		t.Fatal("modified outside state")
	}
}
