package settings

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func globalPointerFixture(t *testing.T) (string, string, string, string) {
	t.Helper()
	root := t.TempDir()
	home := filepath.Join(t.TempDir(), "home with spaces")
	state := filepath.Join(root, ".haws", "state")
	brain := filepath.Join(root, "secondbrain")
	if err := os.MkdirAll(filepath.Join(home, ".claude"), 0o755); err != nil {
		t.Fatal(err)
	}
	return root, home, state, brain
}

func TestSyncGlobalPointersGeneratesAndRefreshesOwnedBlock(t *testing.T) {
	root, home, state, brain := globalPointerFixture(t)
	first, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, false)
	if err != nil {
		t.Fatal(err)
	}
	if first.Targets != 1 || first.Updated != 1 || first.Preserved != 0 {
		t.Fatalf("initial result = %+v", first)
	}
	target := filepath.Join(home, ".claude", "CLAUDE.md")
	want := globalPointerContent(root, brain)
	contents, err := os.ReadFile(target)
	if err != nil || !bytes.Equal(contents, want) {
		t.Fatalf("generated pointer = %q, %v; want %q", contents, err, want)
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), "pointers\tpointer-block\t"+target+"\tcreated\t") {
		t.Fatalf("pointer ownership = %q, %v", ledger, err)
	}
	repeated, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, false)
	if err != nil || repeated.Updated != 0 || repeated.Skipped != 1 {
		t.Fatalf("unchanged pointer result = %+v, %v", repeated, err)
	}
	if unchanged, err := os.ReadFile(target); err != nil || !bytes.Equal(unchanged, contents) {
		t.Fatalf("unchanged pointer changed = %q, %v", unchanged, err)
	}

	updatedBrain := filepath.Join(root, "private brain")
	updated, err := SyncGlobalPointers(context.Background(), root, home, state, updatedBrain, []string{"claude"}, false, false)
	if err != nil {
		t.Fatal(err)
	}
	contents, err = os.ReadFile(target)
	want = append([]byte("\n"), globalPointerContent(root, updatedBrain)...)
	if err != nil || !bytes.Equal(contents, want) {
		t.Fatalf("refreshed pointer = %q, %v", contents, err)
	}
	if updated.Updated != 1 || bytes.Count(contents, []byte(globalPointerStart)) != 1 {
		t.Fatalf("refresh result = %+v; pointer contains duplicate blocks", updated)
	}
	repeated, err = SyncGlobalPointers(context.Background(), root, home, state, updatedBrain, []string{"claude"}, false, false)
	if err != nil || repeated.Updated != 0 || repeated.Skipped != 1 {
		t.Fatalf("refreshed pointer repeat result = %+v, %v", repeated, err)
	}
	if unchanged, err := os.ReadFile(target); err != nil || !bytes.Equal(unchanged, contents) {
		t.Fatalf("refreshed pointer changed on repeat = %q, %v", unchanged, err)
	}
}

func TestSyncGlobalPointersPreservesSurroundingContentAndEditedBlocks(t *testing.T) {
	root, home, state, brain := globalPointerFixture(t)
	target := filepath.Join(home, ".claude", "CLAUDE.md")
	userText := []byte("Personal instructions.\n")
	if err := os.WriteFile(target, userText, 0o600); err != nil {
		t.Fatal(err)
	}
	first, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, false)
	if err != nil || first.Updated != 1 {
		t.Fatalf("append result = %+v, %v", first, err)
	}
	contents, err := os.ReadFile(target)
	want := append(append([]byte{}, userText...), append([]byte("\n"), globalPointerContent(root, brain)...)...)
	if err != nil || !bytes.Equal(contents, want) {
		t.Fatalf("appended pointer = %q, %v; want %q", contents, err, want)
	}
	if err := os.WriteFile(target, []byte(strings.Replace(string(contents), "- Core Standard: ", "- User Core Standard: ", 1)), 0o600); err != nil {
		t.Fatal(err)
	}
	editedBefore, err := os.ReadFile(target)
	if err != nil {
		t.Fatal(err)
	}
	edited, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, false)
	if err != nil || edited.Preserved != 1 || edited.Updated != 0 {
		t.Fatalf("edited block result = %+v, %v", edited, err)
	}
	if after, err := os.ReadFile(target); err != nil || !bytes.Equal(after, editedBefore) {
		t.Fatalf("edited pointer changed = %q, %v", after, err)
	}
}

func TestSyncGlobalPointersAdoptsOnlyAnExactLegacyBlock(t *testing.T) {
	root, home, state, brain := globalPointerFixture(t)
	target := filepath.Join(home, ".claude", "CLAUDE.md")
	want := globalPointerContent(root, brain)
	if err := os.WriteFile(target, want, 0o600); err != nil {
		t.Fatal(err)
	}
	adopted, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, true, false)
	if err != nil {
		t.Fatal(err)
	}
	if adopted.Targets != 1 || adopted.Adopted != 1 || adopted.Skipped != 1 || adopted.Updated != 0 {
		t.Fatalf("adoption result = %+v", adopted)
	}
	if contents, err := os.ReadFile(target); err != nil || !bytes.Equal(contents, want) {
		t.Fatalf("adopted pointer changed = %q, %v", contents, err)
	}
}

func TestSyncGlobalPointersPreservesUnownedMarkedBlock(t *testing.T) {
	root, home, state, brain := globalPointerFixture(t)
	target := filepath.Join(home, ".claude", "CLAUDE.md")
	userBlock := []byte(globalPointerStart + "\n# User block\n" + globalPointerEnd + "\n")
	if err := os.WriteFile(target, userBlock, 0o600); err != nil {
		t.Fatal(err)
	}
	result, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, false)
	if err != nil || result.Preserved != 1 || result.Updated != 0 {
		t.Fatalf("unowned marked block result = %+v, %v", result, err)
	}
	if contents, err := os.ReadFile(target); err != nil || !bytes.Equal(contents, userBlock) {
		t.Fatalf("unowned marked block changed = %q, %v", contents, err)
	}
}

func TestSyncGlobalPointersRecoveryRequiresPointerToPredateMigration(t *testing.T) {
	root, home, state, brain := globalPointerFixture(t)
	target := filepath.Join(home, ".claude", "CLAUDE.md")
	if err := os.MkdirAll(state, 0o700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(state, "ownership-ledger-v2")
	if err := os.WriteFile(marker, []byte("schema=2\tupgraded_at=2024-01-01T00:00:00Z\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	old := time.Date(2020, 1, 1, 0, 0, 0, 0, time.UTC)
	newer := time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC)
	if err := os.Chtimes(marker, newer, newer); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, globalPointerContent(root, brain), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(target, old, old); err != nil {
		t.Fatal(err)
	}
	result, err := SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, true)
	if err != nil || result.Adopted != 1 || result.Updated != 0 {
		t.Fatalf("old pointer recovery = %+v, %v", result, err)
	}

	if err := os.Remove(filepath.Join(state, "ownership.tsv")); err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	if err := os.WriteFile(target, globalPointerContent(root, brain), 0o600); err != nil {
		t.Fatal(err)
	}
	newest := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	if err := os.Chtimes(target, newest, newest); err != nil {
		t.Fatal(err)
	}
	result, err = SyncGlobalPointers(context.Background(), root, home, state, brain, []string{"claude"}, false, true)
	if err != nil || result.Adopted != 0 || result.Updated != 1 {
		t.Fatalf("new pointer recovery = %+v, %v", result, err)
	}
}

func TestGlobalPointerTargetsUseCodexOverridePrecedence(t *testing.T) {
	home := t.TempDir()
	codex := filepath.Join(home, ".codex")
	if err := os.MkdirAll(codex, 0o755); err != nil {
		t.Fatal(err)
	}
	agents := filepath.Join(codex, "AGENTS.md")
	override := filepath.Join(codex, "AGENTS.override.md")
	if err := os.WriteFile(agents, []byte("base"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(override, []byte("override"), 0o600); err != nil {
		t.Fatal(err)
	}
	targets, err := globalPointerTargets(home, []string{"codex"})
	if err != nil || len(targets) != 1 || targets[0].path != override {
		t.Fatalf("Codex pointer target = %+v, %v; want %s", targets, err, override)
	}
}
