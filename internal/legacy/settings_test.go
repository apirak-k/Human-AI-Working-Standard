package legacy

import (
	"os"
	"path/filepath"
	"testing"
)

func TestAutoUpdateEnabledDefaultsAndRespectsSkillSettingPrecedence(t *testing.T) {
	root := t.TempDir()
	if enabled, err := AutoUpdateEnabled(root); err != nil || !enabled {
		t.Fatalf("missing settings = %v, %v; want enabled", enabled, err)
	}
	settingsDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(settingsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	filename := filepath.Join(settingsDir, "settings.tsv")
	tests := []struct {
		name    string
		content string
		want    bool
	}{
		{name: "legacy off", content: "schema_version\t1\nauto_update\toff\n", want: false},
		{name: "explicit skills overrides legacy", content: "schema_version\t1\nauto_update_skills\toff\nauto_update\ton\n", want: false},
		{name: "legacy does not override explicit skills", content: "schema_version\t1\nauto_update\toff\nauto_update_skills\ton\n", want: true},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if err := os.WriteFile(filename, []byte(test.content), 0o600); err != nil {
				t.Fatal(err)
			}
			got, err := AutoUpdateEnabled(root)
			if err != nil || got != test.want {
				t.Fatalf("AutoUpdateEnabled() = %v, %v; want %v", got, err, test.want)
			}
		})
	}
}

func TestAutoUpdateEnabledRejectsMalformedOrUnownedSettings(t *testing.T) {
	root := t.TempDir()
	settingsDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(settingsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	filename := filepath.Join(settingsDir, "settings.tsv")
	for _, content := range []string{
		"schema_version\t2\n",
		"auto_update_skills\tmaybe\n",
		"unknown\tvalue\n",
		"auto_update\toff\textra\n",
	} {
		if err := os.WriteFile(filename, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := AutoUpdateEnabled(root); err == nil {
			t.Fatalf("AutoUpdateEnabled() accepted malformed settings %q", content)
		}
	}
	if err := os.Remove(filename); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "outside-settings")
	if err := os.WriteFile(target, []byte("auto_update_skills\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filename); err != nil {
		t.Skipf("symlink creation unavailable: %v", err)
	}
	if _, err := AutoUpdateEnabled(root); err == nil {
		t.Fatal("AutoUpdateEnabled() followed an unowned settings symlink")
	}
}

func TestAutoUpdateEnabledResolvesRelativeStateDirectoryFromCheckout(t *testing.T) {
	root := t.TempDir()
	stateDir := filepath.Join(root, "custom-state")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("auto_update_skills\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_STATE_DIR", "custom-state")
	if got, err := AutoUpdateEnabled(root); err != nil || got {
		t.Fatalf("relative state directory setting = %v, %v; want disabled", got, err)
	}
}

func TestAutoUpdateEnabledUsesLegacyRemoteValidationRules(t *testing.T) {
	root := t.TempDir()
	settingsDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(settingsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	filename := filepath.Join(settingsDir, "settings.tsv")
	for _, remote := range []string{"git@github.com:owner/repo.git", "https://example.test/brain"} {
		if err := os.WriteFile(filename, []byte("second_brain_remote\t"+remote+"\nauto_update_skills\toff\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		if enabled, err := AutoUpdateEnabled(root); err != nil || enabled {
			t.Fatalf("valid remote %q = %v, %v; want skills disabled", remote, enabled, err)
		}
	}
	for _, remote := range []string{"git@github.com:", "://", "https://", "https://example\x01.test/brain"} {
		if err := os.WriteFile(filename, []byte("second_brain_remote\t"+remote+"\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		if _, err := AutoUpdateEnabled(root); err == nil {
			t.Fatalf("invalid remote %q was accepted", remote)
		}
	}
}
