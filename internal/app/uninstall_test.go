package app

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestUninstallerKeepsPackageWhenLegacyUninstallIsCancelled(t *testing.T) {
	root := t.TempDir()
	appRoot := t.TempDir()
	marker := filepath.Join(appRoot, "active-version")
	if err := os.WriteFile(marker, []byte("HAWS_GO_ACTIVE_V1\nactive=base\nprevious=\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	var output strings.Builder
	uninstaller := Uninstaller{
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error { return nil },
	}
	if err := uninstaller.Run(context.Background(), root, appRoot, strings.NewReader(""), &output, io.Discard); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("package marker was removed after cancellation: %v", err)
	}
	if !strings.Contains(output.String(), "cleanup preview") {
		t.Fatalf("uninstall preview missing from output: %q", output.String())
	}
}

func TestUninstallerDoesNotRepeatCleanupForAnOldCompletionMarker(t *testing.T) {
	root := t.TempDir()
	appRoot := t.TempDir()
	marker := filepath.Join(appRoot, "active-version")
	if err := os.WriteFile(marker, []byte("HAWS_GO_ACTIVE_V1\nactive=base\nprevious=\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "uninstalled"), []byte("old completion\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	uninstaller := Uninstaller{
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error { return nil },
	}
	if err := uninstaller.Run(context.Background(), root, appRoot, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("old completion marker caused package cleanup after cancellation: %v", err)
	}
}

func TestUninstallerCleansVerifiedPackageMarkerAfterLegacyCompletion(t *testing.T) {
	root := t.TempDir()
	appRoot := t.TempDir()
	marker := filepath.Join(appRoot, "active-version")
	if err := os.WriteFile(marker, []byte("HAWS_GO_ACTIVE_V1\nactive=base\nprevious=\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(root, ".haws", "state")
	var output strings.Builder
	uninstaller := Uninstaller{
		Legacy: func(_ context.Context, _ string, _ io.Reader, _ io.Writer, _ io.Writer) error {
			if err := os.MkdirAll(stateDir, 0o755); err != nil {
				return err
			}
			return os.WriteFile(filepath.Join(stateDir, "uninstalled"), []byte("complete\n"), 0o600)
		},
	}
	if err := uninstaller.Run(context.Background(), root, appRoot, strings.NewReader(""), &output, io.Discard); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(marker); !os.IsNotExist(err) {
		t.Fatalf("verified package marker remains: %v", err)
	}
	if !strings.Contains(output.String(), "Removed verified active-version marker") {
		t.Fatalf("cleanup result missing from output: %q", output.String())
	}
}

func TestUninstallerContinuesLegacyCleanupButPreservesMalformedGoMarker(t *testing.T) {
	root := t.TempDir()
	appRoot := t.TempDir()
	marker := filepath.Join(appRoot, "active-version")
	if err := os.WriteFile(marker, []byte("user data\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	legacyCalls := 0
	var output strings.Builder
	uninstaller := Uninstaller{
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error {
			legacyCalls++
			return nil
		},
	}
	if err := uninstaller.Run(context.Background(), root, appRoot, strings.NewReader(""), &output, io.Discard); err != nil {
		t.Fatal(err)
	}
	if legacyCalls != 1 {
		t.Fatalf("legacy uninstall calls = %d", legacyCalls)
	}
	contents, err := os.ReadFile(marker)
	if err != nil || string(contents) != "user data\n" {
		t.Fatalf("unowned marker contents = %q, %v", contents, err)
	}
	if !strings.Contains(output.String(), "preserving package files") {
		t.Fatalf("preservation warning missing from output: %q", output.String())
	}
}
