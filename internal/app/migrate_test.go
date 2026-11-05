package app

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/migration"
)

func migrationFixture(t *testing.T) (string, string, string) {
	t.Helper()
	legacyRoot := t.TempDir()
	if output, err := exec.Command("git", "init", legacyRoot).CombinedOutput(); err != nil {
		t.Fatalf("initialize legacy checkout: %v: %s", err, output)
	}
	if err := os.WriteFile(filepath.Join(legacyRoot, "haws.sh"), []byte("legacy runtime\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(legacyRoot, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	state := filepath.Join(stateDir, "settings.tsv")
	if err := os.WriteFile(state, []byte("schema_version\t1\nauto_update_skills\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	brainDir := filepath.Join(legacyRoot, "secondbrain")
	if err := os.Mkdir(brainDir, 0o700); err != nil {
		t.Fatal(err)
	}
	brain := filepath.Join(brainDir, "private.md")
	if err := os.WriteFile(brain, []byte("private note\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	packageRoot := t.TempDir()
	if err := os.WriteFile(filepath.Join(packageRoot, "package-manifest.json"), []byte("{}"), 0o600); err != nil {
		t.Fatal(err)
	}
	return packageRoot, legacyRoot, state + "\n" + brain
}

func TestRunMigrationPreviewsAndSavesReferenceAfterConfirmation(t *testing.T) {
	packageRoot, legacyRoot, dataPaths := migrationFixture(t)
	stateAndBrain := strings.Split(dataPaths, "\n")
	preview, err := migration.BuildProfile(legacyRoot, "", "")
	if err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := RunMigration(packageRoot, []string{"--from", legacyRoot}, strings.NewReader("y\n"), &output, &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "No files will be copied, moved, or deleted") || !strings.Contains(output.String(), strconv.Quote(preview.LegacyRoot)) {
		t.Fatalf("migration preview omitted data safety or source path: %q", output.String())
	}
	profile, exists, err := migration.LoadPackageProfile(packageRoot)
	if err != nil || !exists {
		t.Fatalf("migration profile exists=%v err=%v", exists, err)
	}
	if profile.LegacyRoot == "" || profile.StateDir == "" || profile.SecondBrainDir == "" {
		t.Fatalf("incomplete migration profile: %#v", profile)
	}
	for i, want := range []string{"schema_version\t1\nauto_update_skills\toff\n", "private note\n"} {
		contents, err := os.ReadFile(stateAndBrain[i])
		if err != nil || string(contents) != want {
			t.Fatalf("legacy data %q changed: %q, %v", stateAndBrain[i], contents, err)
		}
	}
}

func TestRunMigrationCancellationAndClearPreserveLegacyData(t *testing.T) {
	packageRoot, legacyRoot, dataPaths := migrationFixture(t)
	stateAndBrain := strings.Split(dataPaths, "\n")
	var output bytes.Buffer
	if err := RunMigration(packageRoot, []string{"--from", legacyRoot}, strings.NewReader("n\n"), &output, &output); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := migration.LoadPackageProfile(packageRoot); err != nil || exists {
		t.Fatalf("cancelled migration persisted a profile: exists=%v err=%v", exists, err)
	}
	if err := RunMigration(packageRoot, []string{"--from", legacyRoot, "--yes"}, strings.NewReader(""), &output, &output); err != nil {
		t.Fatal(err)
	}
	if err := RunMigration(packageRoot, []string{"--clear"}, strings.NewReader("n\n"), &output, &output); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := migration.LoadPackageProfile(packageRoot); err != nil || !exists {
		t.Fatalf("cancelled clear removed profile: exists=%v err=%v", exists, err)
	}
	if err := RunMigration(packageRoot, []string{"--clear", "--yes"}, strings.NewReader(""), &output, &output); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := migration.LoadPackageProfile(packageRoot); err != nil || exists {
		t.Fatalf("confirmed clear left profile: exists=%v err=%v", exists, err)
	}
	for i, want := range []string{"schema_version\t1\nauto_update_skills\toff\n", "private note\n"} {
		contents, err := os.ReadFile(stateAndBrain[i])
		if err != nil || string(contents) != want {
			t.Fatalf("clearing migration changed legacy data %q: %q, %v", stateAndBrain[i], contents, err)
		}
	}
}

func TestRunMigrationRejectsInvalidInstallationWithoutWritingProfile(t *testing.T) {
	packageRoot, _, _ := migrationFixture(t)
	var output bytes.Buffer
	if err := RunMigration(packageRoot, []string{"--from", t.TempDir(), "--yes"}, strings.NewReader(""), &output, &output); err == nil {
		t.Fatal("RunMigration accepted an invalid legacy installation")
	}
	if _, exists, err := migration.LoadPackageProfile(packageRoot); err != nil || exists {
		t.Fatalf("invalid migration persisted a profile: exists=%v err=%v", exists, err)
	}
}

func TestRunMigrationWizardUsesCheckoutAndKeepsFollowingConfirmationInput(t *testing.T) {
	packageRoot, legacyRoot, _ := migrationFixture(t)
	var output bytes.Buffer
	input := strings.NewReader(legacyRoot + "\ny\n")
	if err := RunMigrationWizard(packageRoot, input, &output, &output); err != nil {
		t.Fatal(err)
	}
	profile, exists, err := migration.LoadPackageProfile(packageRoot)
	if err != nil || !exists || profile.LegacyRoot == "" {
		t.Fatalf("migration wizard profile = %#v, exists=%v, err=%v", profile, exists, err)
	}
	if !strings.Contains(output.String(), "Path to your existing HAWS checkout") || !strings.Contains(output.String(), "Migration reference saved") {
		t.Fatalf("wizard did not show its prompt and result: %q", output.String())
	}
}

func TestRunMigrationWizardBlankPathCancelsWithoutCreatingState(t *testing.T) {
	packageRoot, _, _ := migrationFixture(t)
	var output bytes.Buffer
	if err := RunMigrationWizard(packageRoot, strings.NewReader("\n"), &output, &output); err != nil {
		t.Fatal(err)
	}
	if _, exists, err := migration.LoadPackageProfile(packageRoot); err != nil || exists {
		t.Fatalf("cancelled wizard wrote a profile: exists=%v err=%v", exists, err)
	}
	if !strings.Contains(output.String(), "Migration cancelled") {
		t.Fatalf("cancellation was not shown: %q", output.String())
	}
}

func TestRunMigrationCanClearReferenceAfterLegacyCheckoutBreaks(t *testing.T) {
	packageRoot, legacyRoot, _ := migrationFixture(t)
	var output bytes.Buffer
	if err := RunMigration(packageRoot, []string{"--from", legacyRoot, "--yes"}, strings.NewReader(""), &output, &output); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(filepath.Join(legacyRoot, "haws.sh"), filepath.Join(legacyRoot, "haws.sh.moved")); err != nil {
		t.Fatal(err)
	}
	if err := RunMigration(packageRoot, []string{"--clear", "--yes"}, strings.NewReader(""), &output, &output); err != nil {
		t.Fatalf("clear broken migration reference: %v", err)
	}
	if _, exists, err := migration.LoadPackageProfileForClear(packageRoot); err != nil || exists {
		t.Fatalf("broken migration reference remains: exists=%v err=%v", exists, err)
	}
	if !strings.Contains(output.String(), "Legacy migration reference removed") {
		t.Fatalf("reference recovery result missing: %q", output.String())
	}
}
