package settings

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func claudeCommandFixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	source := filepath.Join(root, "HAWS source")
	home := filepath.Join(root, "home")
	state := filepath.Join(root, "state")
	if err := os.MkdirAll(filepath.Join(source, "skills", "custom", "demo"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "skills", "custom", "demo", "SKILL.md"), []byte("---\nname: demo\ndescription: Run demo quickly.\n---\nSkill body.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return source, home, state
}

func TestSyncClaudeCommandsGeneratesAndUpdatesOwnedCommands(t *testing.T) {
	source, home, state := claudeCommandFixture(t)
	result, err := SyncClaudeCommands(context.Background(), source, home, state, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Targets != 1 || result.Generated != 1 || result.Preserved != 0 {
		t.Fatalf("initial result = %+v", result)
	}
	target := filepath.Join(home, ".claude", "commands", "demo.md")
	want := "---\ndescription: Run demo quickly.\n---\nExecute the demo skill workflow defined in ~/.claude/skills/demo/SKILL.md.\n"
	if contents, err := os.ReadFile(target); err != nil || string(contents) != want {
		t.Fatalf("generated command = %q, %v; want %q", contents, err, want)
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), "agents\tgenerated-file\t"+target+"\t") {
		t.Fatalf("command ownership = %q, %v", ledger, err)
	}

	if err := os.WriteFile(filepath.Join(source, "skills", "custom", "demo", "SKILL.md"), []byte("---\nname: demo\ndescription: Updated command.\n---\nSkill body.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	updated, err := SyncClaudeCommands(context.Background(), source, home, state, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Targets != 1 || updated.Generated != 1 {
		t.Fatalf("update result = %+v", updated)
	}
	if contents, err := os.ReadFile(target); err != nil || !strings.Contains(string(contents), "description: Updated command.") {
		t.Fatalf("updated command = %q, %v", contents, err)
	}
}

func TestSyncClaudeCommandsPreservesUnownedAndEditedFiles(t *testing.T) {
	source, home, state := claudeCommandFixture(t)
	target := filepath.Join(home, ".claude", "commands", "demo.md")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("Personal command.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	unowned, err := SyncClaudeCommands(context.Background(), source, home, state, "", false)
	if err != nil || unowned.Preserved != 1 || unowned.Generated != 0 {
		t.Fatalf("unowned command result = %+v, %v", unowned, err)
	}
	if contents, err := os.ReadFile(target); err != nil || string(contents) != "Personal command.\n" {
		t.Fatalf("unowned command = %q, %v", contents, err)
	}

	if err := os.Remove(target); err != nil {
		t.Fatal(err)
	}
	if _, err := SyncClaudeCommands(context.Background(), source, home, state, "", false); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, []byte("User edit.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	edited, err := SyncClaudeCommands(context.Background(), source, home, state, "", false)
	if err != nil || edited.Preserved != 1 || edited.Generated != 0 {
		t.Fatalf("edited command result = %+v, %v", edited, err)
	}
	if contents, err := os.ReadFile(target); err != nil || string(contents) != "User edit.\n" {
		t.Fatalf("edited command = %q, %v", contents, err)
	}
}

func TestSyncClaudeCommandsAdoptsOnlyAnExactLegacyCommand(t *testing.T) {
	source, home, state := claudeCommandFixture(t)
	target := filepath.Join(home, ".claude", "commands", "demo.md")
	legacy := filepath.Join(home, ".haws_manifest.prev")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, claudeCommandContent("demo", "Run demo quickly."), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(legacy, []byte("skill:device-source::demo\tdemo\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	preserved, err := SyncClaudeCommands(context.Background(), source, home, state, legacy, false)
	if err != nil || preserved.Preserved != 1 || preserved.Adopted != 0 {
		t.Fatalf("without migration = %+v, %v", preserved, err)
	}
	adopted, err := SyncClaudeCommands(context.Background(), source, home, state, legacy, true)
	if err != nil {
		t.Fatal(err)
	}
	if adopted.Targets != 1 || adopted.Adopted != 1 || adopted.Generated != 1 {
		t.Fatalf("legacy adoption = %+v", adopted)
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), target) {
		t.Fatalf("adopted ownership = %q, %v", ledger, err)
	}
}

