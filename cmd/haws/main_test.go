package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunRejectsExtraArguments(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run([]string{"sync", "settings"}, strings.NewReader(""), &stdout, &stderr); code != 2 {
		t.Fatalf("run() exit = %d, want 2", code)
	}
	if !strings.Contains(stderr.String(), "Usage:") {
		t.Fatalf("usage missing from stderr: %q", stderr.String())
	}
}

func TestRunPrintsVersionWithoutFindingCheckout(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--version"}, strings.NewReader(""), &stdout, &stderr); code != 0 {
		t.Fatalf("run() exit = %d, stderr %q", code, stderr.String())
	}
	if stdout.String() != "HAWS dev\n" {
		t.Fatalf("version output = %q, want %q", stdout.String(), "HAWS dev\n")
	}
}

func TestRunRejectsUnknownAction(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/bin/sh\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"unknown"}, strings.NewReader(""), &stdout, &stderr); code != 1 {
		t.Fatalf("run() exit = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "unsupported HAWS action") {
		t.Fatalf("unknown action error missing: %q", stderr.String())
	}
}

func TestRunRequiresAValidCheckout(t *testing.T) {
	t.Setenv("HAWS_ROOT", t.TempDir())
	var stdout, stderr bytes.Buffer
	if code := run(nil, strings.NewReader(""), &stdout, &stderr); code != 1 {
		t.Fatalf("run() exit = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "does not contain haws.sh") {
		t.Fatalf("checkout error missing: %q", stderr.String())
	}
}
