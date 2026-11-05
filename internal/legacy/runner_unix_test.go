//go:build !windows

package legacy

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

func TestRunPassesInputOutputAndExitStatusToLegacyRuntime(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	inputPath := filepath.Join(root, "input.txt")
	hostPath := filepath.Join(root, "host.txt")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + argsPath + "\"\nprintf '%s\\n' \"$HAWS_GO_HOST\" > \"" + hostPath + "\"\ncat > \"" + inputPath + "\"\nprintf 'child-output'\nprintf 'child-error' >&2\nexit 7\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	err := Run(context.Background(), root, tui.ActionSync, strings.NewReader("fixture-input"), &stdout, &stderr)
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) {
		t.Fatalf("Run() error = %v, want child exit error", err)
	}
	if exitErr.ExitCode() != 7 {
		t.Fatalf("child exit code = %d, want 7", exitErr.ExitCode())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(args) != "sync\n" {
		t.Fatalf("legacy args = %q, want %q", args, "sync\n")
	}
	if host, err := os.ReadFile(hostPath); err != nil || string(host) != "1\n" {
		t.Fatalf("HAWS_GO_HOST = %q, %v; want 1", host, err)
	}
	input, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(input) != "fixture-input" {
		t.Fatalf("legacy stdin = %q, want fixture input", input)
	}
	if stdout.String() != "child-output" || stderr.String() != "child-error" {
		t.Fatalf("stdout/stderr = %q/%q", stdout.String(), stderr.String())
	}
}

func TestRunCommandPassesLegacyArguments(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + argsPath + "\"\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := RunCommand(context.Background(), root, []string{"doctor", "--json"}, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatalf("RunCommand() error = %v", err)
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(args) != "doctor\n--json\n" {
		t.Fatalf("legacy args = %q", args)
	}
}
