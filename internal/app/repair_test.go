package app

import (
	"bytes"
	"context"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

func repairFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	logPath := filepath.Join(root, "calls.log")
	script := "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$HAWS_CALL_LOG\"\ncase \"$1\" in\n  doctor) echo doctor-preview; exit \"${HAWS_TEST_DOCTOR_EXIT:-0}\";;\n  sync) echo sync-applied;;\nesac\n"
	if runtime.GOOS == "windows" {
		batch := "@echo off\r\necho %* >> \"%HAWS_CALL_LOG%\"\r\n" +
			"if /I \"%1\"==\"doctor\" (echo doctor-preview & if not \"%HAWS_TEST_DOCTOR_EXIT%\"==\"\" exit /b %HAWS_TEST_DOCTOR_EXIT%)\r\n" +
			"if /I \"%1\"==\"sync\" echo sync-applied\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
	} else if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HAWS_CALL_LOG", logPath)
	return root, logPath
}

func TestRepairPreviewsThenRunsOneSyncAndPreservesFollowingHomeInput(t *testing.T) {
	_, logPath := repairFixture(t)
	var output bytes.Buffer
	var actions []tui.Action
	err := tui.Run(strings.NewReader("4\ny\n3\nq\n"), &output, func(action tui.Action, input io.Reader) error {
		actions = append(actions, action)
		if action == tui.ActionRepair {
			return RunRepair(context.Background(), input, &output, io.Discard)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(actions) != 2 || actions[0] != tui.ActionRepair || actions[1] != tui.ActionDoctor {
		t.Fatalf("actions = %v, want repair followed by queued doctor selection", actions)
	}
	calls, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(calls) != "doctor --deep\nsync\n" {
		t.Fatalf("legacy calls = %q, want one diagnostic then one Sync", calls)
	}
	if doctor, plan, sync := strings.Index(output.String(), "doctor-preview"), strings.Index(output.String(), "Repair plan"), strings.Index(output.String(), "sync-applied"); doctor < 0 || plan < doctor || sync < plan {
		t.Fatalf("repair order must be diagnostics, preview, then apply: %q", output.String())
	}
}

func TestRepairCancelRunsOnlyReadOnlyDiagnostics(t *testing.T) {
	_, logPath := repairFixture(t)
	var output bytes.Buffer
	if err := RunRepair(context.Background(), strings.NewReader("n\n"), &output, io.Discard); err != nil {
		t.Fatal(err)
	}
	calls, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(calls) != "doctor --deep\n" {
		t.Fatalf("legacy calls = %q, want diagnostics only", calls)
	}
	if !strings.Contains(output.String(), "No changes were made") {
		t.Fatalf("cancel result missing: %q", output.String())
	}
}

func TestRepairCanPreviewBlockedDoctorFindings(t *testing.T) {
	_, logPath := repairFixture(t)
	t.Setenv("HAWS_TEST_DOCTOR_EXIT", "1")
	var output bytes.Buffer
	if err := RunRepair(context.Background(), strings.NewReader("n\n"), &output, io.Discard); err != nil {
		t.Fatalf("RunRepair() error = %v, want to allow explicit handling of blocked findings", err)
	}
	if !strings.Contains(output.String(), "Repair plan") || !strings.Contains(output.String(), "No changes were made") {
		t.Fatalf("blocked Doctor findings were not previewed safely: %q", output.String())
	}
	calls, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(calls) != "doctor --deep\n" {
		t.Fatalf("legacy calls = %q, want diagnostics only", calls)
	}
}

func TestRepairStopsWhenDoctorCannotRun(t *testing.T) {
	_, logPath := repairFixture(t)
	t.Setenv("HAWS_TEST_DOCTOR_EXIT", "2")
	var output bytes.Buffer
	err := RunRepair(context.Background(), strings.NewReader("y\n"), &output, io.Discard)
	if err == nil {
		t.Fatal("RunRepair() error = nil, want diagnostics failure")
	}
	if strings.Contains(output.String(), "Repair plan") || strings.Contains(output.String(), "sync-applied") {
		t.Fatalf("Repair continued after Doctor failed: %q", output.String())
	}
	calls, readErr := os.ReadFile(logPath)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(calls) != "doctor --deep\n" {
		t.Fatalf("legacy calls = %q, want diagnostics only", calls)
	}
}
