package settings

import (
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"
)

func codexAgentFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	source := filepath.Join(root, "HAWS source with spaces")
	if err := os.MkdirAll(filepath.Join(source, "agents"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, role := range codexAgentRoles {
		body := "---\nname: " + role + "\ndescription: Canonical " + role + " requirements.\n---\n\nRole instructions.\n"
		if err := os.WriteFile(filepath.Join(source, "agents", role+".md"), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return source, filepath.Join(root, "Codex home with spaces")
}

func TestRunCodexAgentsInstallCheckAndUninstall(t *testing.T) {
	source, home := codexAgentFixture(t)
	result, err := RunCodexAgents("install", source, home, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Profiles) != len(codexAgentRoles) || result.ManifestHash == "" {
		t.Fatalf("install result = %+v", result)
	}
	entries, err := os.ReadDir(result.AgentsDir)
	if err != nil {
		t.Fatal(err)
	}
	want := make([]string, 0, len(codexAgentRoles))
	for _, role := range codexAgentRoles {
		want = append(want, role+".toml")
		profile, err := os.ReadFile(filepath.Join(result.AgentsDir, role+".toml"))
		if err != nil {
			t.Fatal(err)
		}
		text := string(profile)
		for _, required := range []string{
			"name = \"" + role + "\"",
			"description = \"Canonical " + role + " requirements.\"",
			"developer_instructions = ", role + ".md", "HAWS.md", "SKILL.md", "task_report",
		} {
			if !strings.Contains(text, required) {
				t.Errorf("%s.toml does not contain %q", role, required)
			}
		}
		if strings.Contains(text, "\nmodel =") {
			t.Errorf("%s.toml unexpectedly sets a model", role)
		}
	}
	if got := make([]string, 0, len(entries)); len(entries) > 0 {
		for _, entry := range entries {
			got = append(got, entry.Name())
		}
		if !reflect.DeepEqual(got, want) {
			t.Fatalf("profile files = %v; want %v", got, want)
		}
	}
	researcher, err := os.ReadFile(filepath.Join(result.AgentsDir, "researcher.toml"))
	if err != nil || !strings.Contains(string(researcher), "sandbox_mode = \"read-only\"") {
		t.Fatalf("researcher profile = %q, %v; want read-only sandbox", researcher, err)
	}

	checked, err := RunCodexAgents("check", source, home, false)
	if err != nil || !strings.Contains(checked.Message, "5/5") {
		t.Fatalf("check result = %+v, %v", checked, err)
	}

	if err := os.WriteFile(filepath.Join(result.AgentsDir, "personal.toml"), []byte("name = \"personal\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	beforeReinstall := make(map[string][]byte, len(entries))
	for _, entry := range entries {
		beforeReinstall[entry.Name()], err = os.ReadFile(filepath.Join(result.AgentsDir, entry.Name()))
		if err != nil {
			t.Fatal(err)
		}
	}
	if _, err := RunCodexAgents("install", source, home, false); err != nil {
		t.Fatal(err)
	}
	for name, before := range beforeReinstall {
		after, err := os.ReadFile(filepath.Join(result.AgentsDir, name))
		if err != nil || !reflect.DeepEqual(after, before) {
			t.Fatalf("idempotent install changed %s: %v", name, err)
		}
	}
	if _, err := os.Stat(filepath.Join(result.AgentsDir, "personal.toml")); err != nil {
		t.Fatalf("install removed unrelated profile: %v", err)
	}
	if _, err := RunCodexAgents("uninstall", source, home, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(result.ManifestPath); err != nil {
		t.Fatalf("uninstall dry-run removed ownership record: %v", err)
	}

	uninstalled, err := RunCodexAgents("uninstall", source, home, false)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(uninstalled.Message, "uninstall 5") {
		t.Fatalf("uninstall result = %+v", uninstalled)
	}
	entries, err = os.ReadDir(result.AgentsDir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "personal.toml" {
		t.Fatalf("remaining profiles = %v; want personal.toml", entries)
	}
	if _, err := os.Stat(result.ManifestPath); !os.IsNotExist(err) {
		t.Fatalf("ownership manifest remains after uninstall: %v", err)
	}
}

func TestRunCodexAgentsDryRunAndCheckAreReadOnly(t *testing.T) {
	source, home := codexAgentFixture(t)
	if _, err := RunCodexAgents("install", source, home, true); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(home); !os.IsNotExist(err) {
		t.Fatalf("dry-run created Codex home: %v", err)
	}
	if _, err := RunCodexAgents("check", source, home, false); err == nil || !strings.Contains(err.Error(), "missing Codex profiles") {
		t.Fatalf("check error = %v; want missing profiles", err)
	}
	if _, err := os.Stat(home); !os.IsNotExist(err) {
		t.Fatalf("check created Codex home: %v", err)
	}
}

func TestRunCodexAgentsRejectsUserEditsAndPreflightsConflicts(t *testing.T) {
	source, home := codexAgentFixture(t)
	installed, err := RunCodexAgents("install", source, home, false)
	if err != nil {
		t.Fatal(err)
	}
	tester := filepath.Join(installed.AgentsDir, "tester.toml")
	userContent := []byte("name = \"my-tester\"\n")
	if err := os.WriteFile(tester, userContent, 0o644); err != nil {
		t.Fatal(err)
	}
	testerSource := filepath.Join(source, "agents", "tester.md")
	if err := os.WriteFile(testerSource, []byte("---\nname: tester\ndescription: Updated canonical tester requirements.\n---\n\nRole instructions.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	beforeUpgrade, err := os.ReadFile(filepath.Join(installed.AgentsDir, "organizer.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, home, false); err == nil || !strings.Contains(err.Error(), "preserving conflicting or edited profiles") {
		t.Fatalf("install error = %v; want preserved conflict", err)
	}
	afterUpgrade, err := os.ReadFile(filepath.Join(installed.AgentsDir, "organizer.toml"))
	if err != nil || !reflect.DeepEqual(beforeUpgrade, afterUpgrade) {
		t.Fatalf("preflight changed unaffected organizer profile: %v", err)
	}
	if _, err := RunCodexAgents("uninstall", source, home, false); err == nil {
		t.Fatal("uninstall unexpectedly removed an edited profile")
	}
	got, err := os.ReadFile(tester)
	if err != nil || string(got) != string(userContent) {
		t.Fatalf("edited tester profile = %q, %v", got, err)
	}

	conflictHome := filepath.Join(t.TempDir(), "codex")
	conflictDir := filepath.Join(conflictHome, "agents")
	if err := os.MkdirAll(conflictDir, 0o755); err != nil {
		t.Fatal(err)
	}
	userProfile := filepath.Join(conflictDir, "tester.toml")
	if err := os.WriteFile(userProfile, userContent, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, conflictHome, false); err == nil {
		t.Fatal("install unexpectedly replaced a conflicting user profile")
	}
	entries, err := os.ReadDir(conflictDir)
	if err != nil || len(entries) != 1 || entries[0].Name() != "tester.toml" {
		t.Fatalf("conflicting install changed profile directory: %v, %v", entries, err)
	}
}

func TestRunCodexAgentsLeavesIdenticalUnownedProfilesAlone(t *testing.T) {
	source, home := codexAgentFixture(t)
	description := "Canonical tester requirements."
	rolePath := filepath.Join(source, "agents", "tester.md")
	content := codexAgentProfileContent("tester", description, source, rolePath)
	agentsDir, manifestPath, err := CodexAgentPaths(home)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(agentsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	tester := filepath.Join(agentsDir, "tester.toml")
	if err := os.WriteFile(tester, content, 0o644); err != nil {
		t.Fatal(err)
	}
	result, err := RunCodexAgents("install", source, home, false)
	if err != nil {
		t.Fatal(err)
	}
	for _, profile := range result.Profiles {
		if profile.Name == "tester" && profile.Managed {
			t.Fatal("identical pre-existing profile was adopted as HAWS-owned")
		}
	}
	if _, err := RunCodexAgents("uninstall", source, home, false); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(tester); err != nil || !reflect.DeepEqual(got, content) {
		t.Fatalf("uninstall changed identical unowned profile: %v", err)
	}
	if _, err := os.Stat(manifestPath); !os.IsNotExist(err) {
		t.Fatalf("ownership manifest remains after uninstall: %v", err)
	}
}

func TestRunCodexAgentsUpgradesOwnedProfilesAfterCanonicalChanges(t *testing.T) {
	source, home := codexAgentFixture(t)
	if _, err := RunCodexAgents("install", source, home, false); err != nil {
		t.Fatal(err)
	}
	testerSource := filepath.Join(source, "agents", "tester.md")
	previous, err := os.ReadFile(testerSource)
	if err != nil {
		t.Fatal(err)
	}
	updated := strings.Replace(string(previous), "Canonical tester requirements.", "Updated canonical tester requirements.", 1)
	if updated == string(previous) {
		t.Fatal("test fixture description was not found")
	}
	if err := os.WriteFile(testerSource, []byte(updated), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, home, false); err != nil {
		t.Fatal(err)
	}
	profile, err := os.ReadFile(filepath.Join(home, "agents", "tester.toml"))
	if err != nil || !strings.Contains(string(profile), "Updated canonical tester requirements.") {
		t.Fatalf("upgraded profile = %q, %v", profile, err)
	}
	if _, err := RunCodexAgents("check", source, home, false); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("uninstall", source, home, false); err != nil {
		t.Fatal(err)
	}
	for _, role := range codexAgentRoles {
		if _, err := os.Stat(filepath.Join(home, "agents", role+".toml")); !os.IsNotExist(err) {
			t.Fatalf("uninstall left %s profile: %v", role, err)
		}
	}
}

func TestRunCodexAgentsRejectsInvalidManifestAndMissingRoleMetadata(t *testing.T) {
	source, home := codexAgentFixture(t)
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	manifest := filepath.Join(home, "haws-agents.json")
	if err := os.WriteFile(manifest, []byte(`{"version":1,"hashes":{"tester":"not-a-hash"}}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, home, false); err == nil || !strings.Contains(err.Error(), "unrecognized ownership record") {
		t.Fatalf("invalid manifest error = %v", err)
	}
	if err := os.Remove(manifest); err != nil {
		t.Fatal(err)
	}
	role := filepath.Join(source, "agents", "tester.md")
	if err := os.WriteFile(role, []byte("---\nname: organizer\ndescription: wrong role\n---\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, home, false); err == nil || !strings.Contains(err.Error(), "invalid canonical HAWS role") {
		t.Fatalf("invalid role error = %v", err)
	}
}

func TestRunCodexAgentsPreservesLinkedProfileDestinations(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows symlink creation depends on runner privileges")
	}
	source, home := codexAgentFixture(t)
	agentsDir, _, err := CodexAgentPaths(home)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(agentsDir, 0o755); err != nil {
		t.Fatal(err)
	}
	external := filepath.Join(t.TempDir(), "user-profile.toml")
	if err := os.WriteFile(external, []byte("name = \"external\"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	link := filepath.Join(agentsDir, "tester.toml")
	if err := os.Symlink(external, link); err != nil {
		t.Fatal(err)
	}
	if _, err := RunCodexAgents("install", source, home, false); err == nil {
		t.Fatal("install unexpectedly replaced a linked profile")
	}
	if _, err := RunCodexAgents("check", source, home, false); err == nil {
		t.Fatal("check unexpectedly accepted a linked profile")
	}
	if _, err := RunCodexAgents("uninstall", source, home, false); err == nil {
		t.Fatal("uninstall unexpectedly removed a linked profile")
	}
	info, err := os.Lstat(link)
	if err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("linked profile destination = %v, %v", info, err)
	}
	if got, err := os.ReadFile(external); err != nil || string(got) != "name = \"external\"\n" {
		t.Fatalf("external user file changed: %q, %v", got, err)
	}
}
