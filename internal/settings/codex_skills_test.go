package settings

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func codexSkillFixture(t *testing.T, skillName string) (Store, string, string) {
	t.Helper()
	root := t.TempDir()
	home := t.TempDir()
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("CODEX_HOME", "")
	catalogFile(t, root, ".gitmodules", "[submodule \"demo\"]\n\tpath = skills/packs/demo\n\turl = https://github.com/example/demo.git\n")
	entrypoint := "skills/packs/demo/" + skillName + "/SKILL.md"
	catalogFile(t, root, entrypoint, "---\nname: "+skillName+"\ndescription: fixture\n---\n\nSkill.\n")
	return NewStore(root), home, filepath.Join(root, filepath.FromSlash(filepath.Dir(entrypoint)))
}

func TestSyncCodexSkillLinksCreatesAndReusesOwnedLink(t *testing.T) {
	store, home, source := codexSkillFixture(t, "demo")

	first, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil {
		t.Fatal(err)
	}
	if first.Linked != 1 || first.Preserved != 0 || first.PluginOwned != 0 {
		t.Fatalf("first result = %+v", first)
	}
	dest := filepath.Join(home, ".agents", "skills", "demo")
	if got, err := os.Readlink(dest); err != nil || got != source {
		t.Fatalf("link target = %q, %v; want %q", got, err, source)
	}
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	firstLedger, err := os.ReadFile(ledger)
	linkKind := "symlink"
	if runtime.GOOS == "windows" {
		linkKind = "junction"
	}
	if err != nil || !strings.Contains(string(firstLedger), "skills\t"+linkKind+"\t"+dest+"\t"+source+"\t"+source+"\tschema=2") {
		t.Fatalf("ownership ledger = %q, %v", firstLedger, err)
	}

	second, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || second.Linked != 1 {
		t.Fatalf("second result = %+v, %v; want idempotent link", second, err)
	}
	secondLedger, err := os.ReadFile(ledger)
	if err != nil || string(secondLedger) != string(firstLedger) {
		t.Fatalf("repeat changed ownership ledger: %q, %v", secondLedger, err)
	}
}

func TestSyncCodexSkillLinksPreservesUnownedDestination(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	dest := filepath.Join(home, ".agents", "skills", "demo")
	if err := os.MkdirAll(dest, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(dest, "user.txt")
	if err := os.WriteFile(marker, []byte("user data"), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Preserved != 1 || result.Linked != 0 {
		t.Fatalf("result = %+v, %v; want preserved user destination", result, err)
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != "user data" {
		t.Fatalf("user destination changed: %q, %v", got, err)
	}
	if _, err := os.Lstat(filepath.Join(home, ".haws", "skills-ownership.tsv")); !os.IsNotExist(err) {
		t.Fatalf("unowned destination acquired an ownership ledger: %v", err)
	}
}

func TestSyncCodexSkillLinksRepairsOwnedLinkAndPreservesOtherRows(t *testing.T) {
	store, home, source := codexSkillFixture(t, "demo")
	dest := filepath.Join(home, ".agents", "skills", "demo")
	oldSource := filepath.Join(t.TempDir(), "old-demo")
	if err := os.MkdirAll(oldSource, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(oldSource, dest); err != nil {
		t.Fatal(err)
	}
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	other := "agents\tgenerated-file\t" + filepath.Join(home, ".agents", "AGENTS.md") + "\t" + source + "\tfingerprint\tschema=2\n"
	owned := "skills\tsymlink\t" + dest + "\t" + oldSource + "\t" + oldSource + "\tschema=2\n"
	if err := os.WriteFile(ledger, []byte(other+owned), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Linked != 1 {
		t.Fatalf("result = %+v, %v; want repaired link", result, err)
	}
	got, err := os.Readlink(dest)
	if err != nil || got != source {
		t.Fatalf("repaired link = %q, %v; want %q", got, err, source)
	}
	updated, err := os.ReadFile(ledger)
	linkKind := "symlink"
	if runtime.GOOS == "windows" {
		linkKind = "junction"
	}
	newOwned := "skills\t" + linkKind + "\t" + dest + "\t" + source + "\t" + source + "\tschema=2\n"
	if err != nil || !strings.Contains(string(updated), other) || !strings.Contains(string(updated), newOwned) || strings.Contains(string(updated), owned) {
		t.Fatalf("ledger did not preserve unrelated rows and refresh ownership: %q, %v", updated, err)
	}
}

func TestSyncCodexSkillLinksDefersToPonytailPluginAndPrunesOnlyOwnedLink(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "ponytail")
	first, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || first.Linked != 1 {
		t.Fatalf("initial result = %+v, %v", first, err)
	}
	dest := filepath.Join(home, ".agents", "skills", "ponytail")
	catalogFile(t, home, ".codex/plugins/cache/plugin/skills/ponytail/SKILL.md", "plugin skill\n")

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.PluginOwned != 1 || result.Linked != 0 || result.Pruned != 1 {
		t.Fatalf("plugin result = %+v, %v", result, err)
	}
	if _, err := os.Lstat(dest); !os.IsNotExist(err) {
		t.Fatalf("HAWS-owned link remained beside Codex plugin skill: %v", err)
	}
	ledger, err := os.ReadFile(filepath.Join(home, ".haws", "skills-ownership.tsv"))
	if err != nil || strings.Contains(string(ledger), dest) {
		t.Fatalf("plugin-owned link ownership remained in ledger: %q, %v", ledger, err)
	}
}

func TestSyncCodexSkillLinksPrunesStaleOwnedLinksAndLedgerRows(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	destination := filepath.Join(home, ".agents", "skills", "removed")
	oldSource := filepath.Join(t.TempDir(), "removed")
	if err := os.MkdirAll(oldSource, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(oldSource, destination); err != nil {
		t.Fatal(err)
	}
	linkKind := "symlink"
	if runtime.GOOS == "windows" {
		linkKind = "junction"
	}
	owned := "skills\t" + linkKind + "\t" + destination + "\t" + oldSource + "\t" + oldSource + "\tschema=2\n"
	malformed := "skills\tunknown-kind\t" + destination + "\t" + oldSource + "\tfingerprint\tschema=1\n"
	other := "agents\tgenerated-file\t" + filepath.Join(home, ".agents", "AGENTS.md") + "\t" + oldSource + "\tfingerprint\tschema=2\n"
	globalLedger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(globalLedger), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(globalLedger, []byte(owned+malformed+other), 0600); err != nil {
		t.Fatal(err)
	}
	stateLedger := store.Path("ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(stateLedger), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(stateLedger, []byte(owned+other), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Pruned != 1 {
		t.Fatalf("result = %+v, %v; want one stale link pruned", result, err)
	}
	if _, err := os.Lstat(destination); !os.IsNotExist(err) {
		t.Fatalf("stale owned link remains: %v", err)
	}
	for _, ledger := range []string{globalLedger, stateLedger} {
		updated, err := os.ReadFile(ledger)
		if err != nil || strings.Contains(string(updated), owned) || !strings.Contains(string(updated), other) {
			t.Fatalf("ledger %s was not safely pruned: %q, %v", ledger, updated, err)
		}
		if ledger == globalLedger && !strings.Contains(string(updated), malformed) {
			t.Fatalf("malformed ownership row was lost: %q", updated)
		}
	}
}

func TestSyncCodexSkillLinksPreservesEditedStaleLinkAndOwnership(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	destination := filepath.Join(home, ".agents", "skills", "removed")
	foreign := filepath.Join(t.TempDir(), "foreign")
	oldSource := filepath.Join(t.TempDir(), "removed")
	for _, path := range []string{foreign, oldSource} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(foreign, destination); err != nil {
		t.Fatal(err)
	}
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	row := "skills\tsymlink\t" + destination + "\t" + oldSource + "\t" + oldSource + "\tschema=2\n"
	if err := os.WriteFile(ledger, []byte(row), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Pruned != 0 || result.Preserved != 1 {
		t.Fatalf("result = %+v, %v; want changed stale link preserved", result, err)
	}
	if got, err := os.Readlink(destination); err != nil || got != foreign {
		t.Fatalf("edited stale link changed to %q: %v", got, err)
	}
	updated, err := os.ReadFile(ledger)
	if err != nil || !strings.Contains(string(updated), row) {
		t.Fatalf("ownership for edited stale link was lost: %q, %v", updated, err)
	}
}

func TestSyncCodexSkillLinksPreservesUnownedStaleDirectory(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	destination := filepath.Join(home, ".agents", "skills", "removed")
	if err := os.MkdirAll(destination, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(destination, "user.txt")
	if err := os.WriteFile(marker, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Pruned != 0 {
		t.Fatalf("result = %+v, %v; want unowned stale directory untouched", result, err)
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != "keep" {
		t.Fatalf("unowned stale directory changed: %q, %v", got, err)
	}
}

func TestSyncCodexSkillLinksRejectsSymlinkedSkillsParent(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	outside := t.TempDir()
	if err := os.MkdirAll(filepath.Join(outside, "skills", "removed"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(home, ".agents")); err != nil {
		t.Fatal(err)
	}

	if _, err := SyncCodexSkillLinks(context.Background(), store, home); err == nil {
		t.Fatal("symlinked Codex skills parent was accepted")
	}
	if _, err := os.Lstat(filepath.Join(outside, "skills", "demo")); !os.IsNotExist(err) {
		t.Fatalf("active link escaped through symlinked parent: %v", err)
	}
}

func TestSyncClaudeSkillLinksCreatesAndReusesOwnedLink(t *testing.T) {
	store, home, source := codexSkillFixture(t, "demo")
	first, err := SyncClaudeSkillLinks(context.Background(), store, home)
	if err != nil || first.Linked != 1 || first.Pruned != 0 {
		t.Fatalf("first result = %+v, %v", first, err)
	}
	destination := filepath.Join(home, ".claude", "skills", "demo")
	if got, err := os.Readlink(destination); err != nil || got != source {
		t.Fatalf("Claude link target = %q, %v; want %q", got, err, source)
	}
	second, err := SyncClaudeSkillLinks(context.Background(), store, home)
	if err != nil || second.Linked != 1 || second.AlreadyLinked != 1 {
		t.Fatalf("second result = %+v, %v; want idempotent link", second, err)
	}
}

func TestSyncClaudeSkillLinksPrunesOnlyStaleClaudeOwnedLink(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	retiredSource := filepath.Join(t.TempDir(), "retired")
	if err := os.MkdirAll(retiredSource, 0700); err != nil {
		t.Fatal(err)
	}
	claudeDestination := filepath.Join(home, ".claude", "skills", "retired")
	codexDestination := filepath.Join(home, ".agents", "skills", "retired")
	for _, destination := range []string{claudeDestination, codexDestination} {
		if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(retiredSource, destination); err != nil {
			t.Fatal(err)
		}
	}
	linkKind := "symlink"
	if runtime.GOOS == "windows" {
		linkKind = "junction"
	}
	claudeRow := "skills\t" + linkKind + "\t" + claudeDestination + "\t" + retiredSource + "\t" + retiredSource + "\tschema=2\n"
	codexRow := "skills\t" + linkKind + "\t" + codexDestination + "\t" + retiredSource + "\t" + retiredSource + "\tschema=2\n"
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(ledger, []byte(claudeRow+codexRow), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncClaudeSkillLinks(context.Background(), store, home)
	if err != nil || result.Pruned != 1 {
		t.Fatalf("result = %+v, %v; want one Claude link pruned", result, err)
	}
	if _, err := os.Lstat(claudeDestination); !os.IsNotExist(err) {
		t.Fatalf("stale Claude link remains: %v", err)
	}
	if got, err := os.Readlink(codexDestination); err != nil || got != retiredSource {
		t.Fatalf("Codex link changed during Claude sync: %q, %v", got, err)
	}
	updated, err := os.ReadFile(ledger)
	if err != nil || strings.Contains(string(updated), claudeDestination) || !strings.Contains(string(updated), codexRow) {
		t.Fatalf("ledger did not retain only the unrelated Codex row: %q, %v", updated, err)
	}
}

func TestSyncCodexSkillLinksUsesSourceSuffixForDuplicateNames(t *testing.T) {
	root := t.TempDir()
	home := t.TempDir()
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	catalogFile(t, root, ".gitmodules", "[submodule \"one\"]\n\tpath = skills/packs/one\n\turl = https://github.com/example/one.git\n"+
		"[submodule \"two\"]\n\tpath = skills/packs/two\n\turl = https://github.com/example/two.git\n")
	for _, source := range []string{"one", "two"} {
		catalogFile(t, root, "skills/packs/"+source+"/shared/SKILL.md", "---\nname: shared\n---\nSkill.\n")
	}
	store := NewStore(root)

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Linked != 2 {
		t.Fatalf("result = %+v, %v; want both source-qualified links", result, err)
	}
	for _, source := range []string{"one", "two"} {
		destination := filepath.Join(home, ".agents", "skills", "shared ["+source+"]")
		got, err := os.Readlink(destination)
		want := filepath.Join(root, "skills", "packs", source, "shared")
		if err != nil || got != want {
			t.Fatalf("link for %s = %q, %v; want %q", source, got, err, want)
		}
	}
}

func TestSyncCodexSkillLinksSkipsDisabledEnvironment(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	catalogFile(t, store.Root, "ai-configs/environments.disabled", "codex\n")

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result != (CodexSkillSyncResult{}) {
		t.Fatalf("disabled Codex result = %+v, %v; want no changes", result, err)
	}
	if _, err := os.Lstat(filepath.Join(home, ".agents", "skills", "demo")); !os.IsNotExist(err) {
		t.Fatalf("disabled Codex skill was linked: %v", err)
	}
}

func TestSyncCodexSkillLinksPreservesEditedOwnedLink(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	destination := filepath.Join(home, ".agents", "skills", "demo")
	foreign := filepath.Join(t.TempDir(), "foreign")
	oldSource := filepath.Join(t.TempDir(), "old-source")
	for _, path := range []string{foreign, oldSource} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(foreign, destination); err != nil {
		t.Fatal(err)
	}
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	row := "skills\tsymlink\t" + destination + "\t" + oldSource + "\t" + oldSource + "\tschema=2\n"
	if err := os.WriteFile(ledger, []byte(row), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Preserved != 1 || result.Linked != 0 {
		t.Fatalf("result = %+v, %v; want changed owned link preserved", result, err)
	}
	if got, err := os.Readlink(destination); err != nil || got != foreign {
		t.Fatalf("edited link changed to %q: %v", got, err)
	}
}

func TestSyncCodexSkillLinksPreservesUnownedDestinationWhenPluginOwned(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "ponytail")
	catalogFile(t, home, ".codex/plugins/cache/plugin/skills/ponytail/SKILL.md", "plugin skill\n")
	destination := filepath.Join(home, ".agents", "skills", "ponytail")
	if err := os.MkdirAll(destination, 0700); err != nil {
		t.Fatal(err)
	}
	marker := filepath.Join(destination, "user.txt")
	if err := os.WriteFile(marker, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.PluginOwned != 1 || result.Preserved != 1 {
		t.Fatalf("result = %+v, %v; want plugin precedence and user preservation", result, err)
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != "keep" {
		t.Fatalf("unowned destination changed: %q, %v", got, err)
	}
}

func TestSyncCodexSkillLinksRejectsSymlinkedOwnershipLedger(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	outside := filepath.Join(t.TempDir(), "ledger.tsv")
	if err := os.WriteFile(outside, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, ledger); err != nil {
		t.Fatal(err)
	}
	if _, err := SyncCodexSkillLinks(context.Background(), store, home); err == nil {
		t.Fatal("symlinked ownership ledger was accepted")
	}
	if _, err := os.Lstat(filepath.Join(home, ".agents", "skills", "demo")); !os.IsNotExist(err) {
		t.Fatalf("skill link was created despite unsafe ledger: %v", err)
	}
}

func TestSyncCodexSkillLinksUsesGlobalLedgerOverStaleCheckoutLedger(t *testing.T) {
	store, home, source := codexSkillFixture(t, "demo")
	destination := filepath.Join(home, ".agents", "skills", "demo")
	if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(source, destination); err != nil {
		t.Fatal(err)
	}
	oldSource := filepath.Join(t.TempDir(), "old-source")
	if err := os.MkdirAll(oldSource, 0700); err != nil {
		t.Fatal(err)
	}
	stateLedger := store.Path("ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(stateLedger), 0700); err != nil {
		t.Fatal(err)
	}
	oldRow := "skills\tsymlink\t" + destination + "\t" + oldSource + "\t" + oldSource + "\tschema=2\n"
	if err := os.WriteFile(stateLedger, []byte(oldRow), 0600); err != nil {
		t.Fatal(err)
	}
	globalLedger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(globalLedger), 0700); err != nil {
		t.Fatal(err)
	}
	currentRow := "skills\tsymlink\t" + destination + "\t" + source + "\t" + source + "\tschema=2\n"
	if err := os.WriteFile(globalLedger, []byte(currentRow), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Linked != 1 || result.AlreadyLinked != 1 {
		t.Fatalf("result = %+v, %v; want current global ownership", result, err)
	}
}

func TestSyncCodexSkillLinksPreservesUnrecognizedOwnershipRows(t *testing.T) {
	store, home, _ := codexSkillFixture(t, "demo")
	ledger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		t.Fatal(err)
	}
	row := "skills\tunknown-kind\t/other/path\t/other/source\tfingerprint\tschema=1\n"
	if err := os.WriteFile(ledger, []byte(row), 0600); err != nil {
		t.Fatal(err)
	}

	result, err := SyncCodexSkillLinks(context.Background(), store, home)
	if err != nil || result.Linked != 1 {
		t.Fatalf("result = %+v, %v; want unrelated row preserved and skill linked", result, err)
	}
	updated, err := os.ReadFile(ledger)
	if err != nil || !strings.Contains(string(updated), row) {
		t.Fatalf("unrecognized row was lost: %q, %v", updated, err)
	}
}
