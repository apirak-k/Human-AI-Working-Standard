//go:build windows

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
	t.Setenv("HAWS_TEST_ARGS", argsPath)
	t.Setenv("HAWS_TEST_INPUT", inputPath)
	t.Setenv("HAWS_TEST_HOST", hostPath)
	batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %HAWS_GO_HOST%> \"%HAWS_TEST_HOST%\"\r\nset /p line=\r\necho %line%> \"%HAWS_TEST_INPUT%\"\r\necho child-output\r\necho child-error 1>&2\r\nexit /b 7\r\n"
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
	if host, err := os.ReadFile(hostPath); err != nil || strings.TrimSpace(string(host)) != "1" {
		t.Fatalf("HAWS_GO_HOST = %q, %v; want 1", host, err)
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

func TestRunCommandPassesLegacyArguments(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	t.Setenv("HAWS_TEST_ARGS", argsPath)
	batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %2>> \"%HAWS_TEST_ARGS%\"\r\n"
	if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := RunCommand(context.Background(), root, []string{"doctor", "--json"}, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatalf("RunCommand() error = %v", err)
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(args)) != "doctor\r\n--json" && strings.TrimSpace(string(args)) != "doctor\n--json" {
		t.Fatalf("legacy args = %q", args)
	}
}
