package settings

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func agentFileFixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	source := filepath.Join(root, "HAWS source")
	home := filepath.Join(root, "home")
	state := filepath.Join(root, "state")
	if err := os.MkdirAll(filepath.Join(source, "agents"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(source, "agents", "backend-engineer.md"), []byte("Canonical agent.\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return source, home, state
}

func TestSyncAgentFilesProjectsClaudeAndGeminiAndRecordsOwnership(t *testing.T) {
	source, home, state := agentFileFixture(t)
	result, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude", "gemini"}, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Targets != 2 || result.Preserved != 0 || result.Linked+result.Hardlinked+result.Copied != 2 {
		t.Fatalf("initial result = %+v", result)
	}
	for _, target := range []string{
		filepath.Join(home, ".claude", "agents", "backend-engineer.md"),
		filepath.Join(home, ".gemini", "config", "agents", "backend-engineer", "agent.md"),
	} {
		contents, err := os.ReadFile(target)
		if err != nil || string(contents) != "Canonical agent.\n" {
			t.Fatalf("projected file %s = %q, %v", target, contents, err)
		}
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil {
		t.Fatal(err)
	}
	rows := strings.Split(strings.TrimSpace(string(ledger)), "\n")
	if len(rows) != 2 {
		t.Fatalf("ownership rows = %q; want one per projection", rows)
	}
	for _, row := range rows {
		fields := strings.Split(row, "\t")
		if len(fields) != 6 || fields[0] != "agents" || fields[5] != "schema=2" ||
			(fields[1] != "symlink" && fields[1] != "hardlink" && fields[1] != "generated-file") {
			t.Fatalf("invalid ownership row %q", row)
		}
	}

	second, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude", "gemini"}, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if second.Targets != 2 || second.Preserved != 0 || second.Already+second.Copied != 2 {
		t.Fatalf("repeat result = %+v", second)
	}
	ledger, err = os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || len(strings.Split(strings.TrimSpace(string(ledger)), "\n")) != 2 {
		t.Fatalf("repeated ownership ledger = %q, %v; want one row per projection", ledger, err)
	}
}

func TestSyncAgentFilesPreservesUnownedAndEditedDestinations(t *testing.T) {
	source, home, state := agentFileFixture(t)
	claude := filepath.Join(home, ".claude", "agents", "backend-engineer.md")
	if err := os.MkdirAll(filepath.Dir(claude), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(claude, []byte("Personal Claude agent.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	gemini := filepath.Join(home, ".gemini", "config", "agents", "backend-engineer", "agent.md")
	if err := os.MkdirAll(filepath.Dir(gemini), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(gemini, []byte("Generated before user edit.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256([]byte("Generated before user edit.\n"))
	row := strings.Join([]string{"agents", "generated-file", gemini, filepath.Join(source, "agents", "backend-engineer.md"), hex.EncodeToString(hash[:]), "schema=2"}, "\t") + "\n"
	if err := os.MkdirAll(state, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "ownership.tsv"), []byte(row), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(gemini, []byte("Edited by user.\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude", "gemini"}, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Targets != 2 || result.Preserved != 2 {
		t.Fatalf("preservation result = %+v", result)
	}
	for path, want := range map[string]string{claude: "Personal Claude agent.\n", gemini: "Edited by user.\n"} {
		got, err := os.ReadFile(path)
		if err != nil || string(got) != want {
			t.Fatalf("preserved %s = %q, %v; want %q", path, got, err, want)
		}
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || strings.Contains(string(ledger), "claude/agents") || !strings.Contains(string(ledger), gemini) {
		t.Fatalf("ownership after preserve = %q, %v", ledger, err)
	}
}

func TestSyncAgentFilesPreservesUnownedAndEditedLinks(t *testing.T) {
	source, home, state := agentFileFixture(t)
	sourceFile := filepath.Join(source, "agents", "backend-engineer.md")
	external := filepath.Join(t.TempDir(), "personal-agent.md")
	if err := os.WriteFile(external, []byte("Personal agent.\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	claude := filepath.Join(home, ".claude", "agents", "backend-engineer.md")
	gemini := filepath.Join(home, ".gemini", "config", "agents", "backend-engineer", "agent.md")
	for _, target := range []string{claude, gemini} {
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(external, claude); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if err := os.Symlink(sourceFile, gemini); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if err := os.MkdirAll(state, 0o700); err != nil {
		t.Fatal(err)
	}
	row := strings.Join([]string{"agents", "symlink", gemini, sourceFile, sourceFile, "schema=2"}, "\t") + "\n"
	if err := os.WriteFile(filepath.Join(state, "ownership.tsv"), []byte(row), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(gemini); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, gemini); err != nil {
		t.Fatal(err)
	}

	result, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude", "gemini"}, "", false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Targets != 2 || result.Preserved != 2 {
		t.Fatalf("preserved link result = %+v", result)
	}
	for _, target := range []string{claude, gemini} {
		if got, err := os.Readlink(target); err != nil || got != external {
			t.Fatalf("preserved link %s = %q, %v", target, got, err)
		}
	}
}

func TestSyncAgentFilesAdoptsOnlyExactLegacyManifestTargets(t *testing.T) {
	source, home, state := agentFileFixture(t)
	legacy := filepath.Join(home, ".haws_manifest.prev")
	if err := os.WriteFile(legacy, []byte("agent:backend-engineer\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(home, ".claude", "agents", "backend-engineer.md")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	sourceFile := filepath.Join(source, "agents", "backend-engineer.md")
	if err := copyFileForAgentTest(sourceFile, target); err != nil {
		t.Fatal(err)
	}

	preserved, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude"}, legacy, false)
	if err != nil || preserved.Preserved != 1 || preserved.Adopted != 0 {
		t.Fatalf("without adoption = %+v, %v", preserved, err)
	}
	adopted, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude"}, legacy, true)
	if err != nil {
		t.Fatal(err)
	}
	if adopted.Adopted != 1 || adopted.Targets != 1 || adopted.Linked+adopted.Hardlinked+adopted.Copied != 1 {
		t.Fatalf("legacy adoption = %+v", adopted)
	}
	contents, err := os.ReadFile(target)
	if err != nil || string(contents) != "Canonical agent.\n" {
		t.Fatalf("adopted target = %q, %v", contents, err)
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), target) {
		t.Fatalf("adopted ownership = %q, %v", ledger, err)
	}
}

func TestSyncAgentFilesAdoptsAnExactLegacyHardlink(t *testing.T) {
	source, home, state := agentFileFixture(t)
	legacy := filepath.Join(home, ".haws_manifest.prev")
	if err := os.WriteFile(legacy, []byte("agent:backend-engineer\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(home, ".claude", "agents", "backend-engineer.md")
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		t.Fatal(err)
	}
	sourceFile := filepath.Join(source, "agents", "backend-engineer.md")
	if err := os.Link(sourceFile, target); err != nil {
		t.Skipf("hardlink unavailable: %v", err)
	}

	result, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude"}, legacy, true)
	if err != nil {
		t.Fatal(err)
	}
	if result.Adopted != 1 || result.Already != 1 || result.Targets != 1 {
		t.Fatalf("hardlink adoption = %+v", result)
	}
	if !sameAgentFile(sourceFile, target) {
		t.Fatal("legacy hardlink was replaced")
	}
	ledger, err := os.ReadFile(filepath.Join(state, "ownership.tsv"))
	if err != nil || !strings.Contains(string(ledger), "agents\thardlink\t"+target+"\t") {
		t.Fatalf("hardlink ownership = %q, %v", ledger, err)
	}
}

func TestSyncAgentFilesRejectsSymlinkedParentsAndLedger(t *testing.T) {
	source, home, state := agentFileFixture(t)
	linkedParent := filepath.Join(home, ".claude")
	external := filepath.Join(t.TempDir(), "external")
	if err := os.MkdirAll(external, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, linkedParent); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude"}, "", false); err == nil {
		t.Fatal("sync accepted a symlinked Claude parent")
	}

	if err := os.Remove(linkedParent); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(state, 0o700); err != nil {
		t.Fatal(err)
	}
	ledgerTarget := filepath.Join(t.TempDir(), "ledger.tsv")
	if err := os.WriteFile(ledgerTarget, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(ledgerTarget, filepath.Join(state, "ownership.tsv")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := SyncAgentFiles(context.Background(), source, home, state, []string{"claude"}, "", false); err == nil {
		t.Fatal("sync accepted a symlinked ownership ledger")
	}
}

func copyFileForAgentTest(source, destination string) error {
	contents, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	return os.WriteFile(destination, contents, 0o600)
}
