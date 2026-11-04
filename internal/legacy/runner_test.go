package legacy

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

func TestFindRootUsesExplicitCheckout(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/bin/sh\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	got, err := FindRoot()
	if err != nil {
		t.Fatalf("FindRoot() error = %v", err)
	}
	if got != root {
		t.Fatalf("FindRoot() = %q, want %q", got, root)
	}
}

func TestFindRootRejectsMissingRuntime(t *testing.T) {
	t.Setenv("HAWS_ROOT", t.TempDir())
	if _, err := FindRoot(); err == nil {
		t.Fatal("FindRoot() succeeded without haws.sh")
	}
}

func TestRunRejectsUnknownAction(t *testing.T) {
	err := Run(context.Background(), t.TempDir(), tui.Action("custom"), nil, io.Discard, io.Discard)
	if err == nil {
		t.Fatal("Run() accepted an unknown action")
	}
}
