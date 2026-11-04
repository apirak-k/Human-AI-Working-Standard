//go:build windows

package legacy

import (
	"bytes"
	"context"
	"errors"
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
	t.Setenv("HAWS_TEST_ARGS", argsPath)
	t.Setenv("HAWS_TEST_INPUT", inputPath)
	batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\nset /p line=\r\necho %line%> \"%HAWS_TEST_INPUT%\"\r\necho child-output\r\necho child-error 1>&2\r\nexit /b 7\r\n"
	if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	err := Run(context.Background(), root, tui.ActionSync, strings.NewReader("fixture-input\n"), &stdout, &stderr)
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
	if strings.TrimSpace(string(args)) != "sync" {
		t.Fatalf("legacy args = %q, want sync", args)
	}
	input, err := os.ReadFile(inputPath)
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(input)) != "fixture-input" {
		t.Fatalf("legacy stdin = %q, want fixture input", input)
	}
	if !strings.Contains(stdout.String(), "child-output") || !strings.Contains(stderr.String(), "child-error") {
		t.Fatalf("stdout/stderr = %q/%q", stdout.String(), stderr.String())
	}
}
