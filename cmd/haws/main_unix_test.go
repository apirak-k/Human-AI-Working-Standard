//go:build !windows

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunHomeRoutesSyncToLegacyAndReturnsToMenu(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + argsPath + "\"\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_STATE_DIR", stateDir)
	var stdout, stderr bytes.Buffer
	if code := run(nil, strings.NewReader("1\nq\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("run() exit = %d, stderr %q", code, stderr.String())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(args) != "sync\n" {
		t.Fatalf("legacy args = %q, want sync", args)
	}
	if !strings.Contains(stdout.String(), "HAWS — Human-AI Working Standard") {
		t.Fatalf("Home TUI missing: %q", stdout.String())
	}
}

func TestRunSetupRoutesToLegacySetup(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args")
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/bin/sh\nprintf '%s' \"$1\" > '"+argsPath+"'\n"), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	var out, stderr bytes.Buffer
	if code := run([]string{"setup"}, strings.NewReader(""), &out, &stderr); code != 0 {
		t.Fatalf("setup failed: %d %s", code, stderr.String())
	}
	if data, err := os.ReadFile(argsPath); err != nil || string(data) != "setup" {
		t.Fatalf("setup action: %q %v", data, err)
	}
}
