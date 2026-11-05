package app

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func settingsHostFixture(t *testing.T, pending bool, syncExit string) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	applyResult := filepath.Join(stateDir, "apply.result")
	if pending {
		if err := os.WriteFile(applyResult, []byte("settings\tcompleted\nintegration\tpending\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	calls := filepath.Join(root, "calls.log")
	script := "#!/bin/sh\nprintf '%s\\n' \"$1\" >> \"$HAWS_CALL_LOG\"\n" +
		"case \"$1\" in\n" +
		"  settings|setup) printf '%s\\n' \"$HAWS_GO_HOST\" > \"$HAWS_HOST_LOG\";;\n" +
		"  sync) exit \"${HAWS_TEST_SYNC_EXIT:-0}\";;\n" +
		"esac\n"
	if runtime.GOOS == "windows" {
		batch := "@echo off\r\necho %1 >> \"%HAWS_CALL_LOG%\"\r\n" +
			"if /I \"%1\"==\"settings\" echo %HAWS_GO_HOST% > \"%HAWS_HOST_LOG%\"\r\n" +
			"if /I \"%1\"==\"setup\" echo %HAWS_GO_HOST% > \"%HAWS_HOST_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" exit /b %HAWS_TEST_SYNC_EXIT%\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
	} else if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HAWS_CALL_LOG", calls)
	t.Setenv("HAWS_HOST_LOG", filepath.Join(root, "host.log"))
	t.Setenv("HAWS_TEST_SYNC_EXIT", syncExit)
	return root, calls, applyResult
}

func TestRunSettingsUsesOneGoHostedSyncWhenIntegrationIsPending(t *testing.T) {
	root, callsPath, resultPath := settingsHostFixture(t, true, "0")
	var stdout, stderr strings.Builder
	if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("queued-home-input"), &stdout, &stderr); err != nil {
		t.Fatalf("RunSettings() error = %v; stderr %q", err, stderr.String())
	}
	calls, err := os.ReadFile(callsPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(calls) != "settings\nsync\n" {
		t.Fatalf("legacy commands = %q, want one Settings command and one Go-hosted Sync", calls)
	}
	host, err := os.ReadFile(filepath.Join(root, "host.log"))
	if err != nil || string(host) != "1\n" {
		t.Fatalf("Go host marker = %q, %v; want 1", host, err)
	}
	if !strings.Contains(stdout.String(), "authoritative Sync") {
		t.Fatalf("Go-hosted Sync was not explained: %q", stdout.String())
	}
	result, err := os.ReadFile(resultPath)
	if err != nil || strings.Contains(string(result), "integration\tpending") || !strings.Contains(string(result), "integration\tcompleted") {
		t.Fatalf("settings apply result after Sync = %q, %v", result, err)
	}
}

func TestRunSettingsDoesNotSyncWhenNoIntegrationIsPending(t *testing.T) {
	root, callsPath, _ := settingsHostFixture(t, false, "0")
	if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	calls, err := os.ReadFile(callsPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(calls) != "settings\n" {
		t.Fatalf("legacy commands = %q, want Settings only", calls)
	}
}

func TestRunSettingsLeavesPendingStateWhenGoSyncFails(t *testing.T) {
	root, callsPath, resultPath := settingsHostFixture(t, true, "7")
	err := RunSettings(context.Background(), root, []string{"setup"}, strings.NewReader(""), io.Discard, io.Discard)
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.ExitCode() != 7 {
		t.Fatalf("RunSettings() error = %v, want child exit 7", err)
	}
	calls, readErr := os.ReadFile(callsPath)
	if readErr != nil || string(calls) != "setup\nsync\n" {
		t.Fatalf("legacy commands = %q, %v", calls, readErr)
	}
	result, readErr := os.ReadFile(resultPath)
	if readErr != nil || !strings.Contains(string(result), "integration\tpending") {
		t.Fatalf("failed Sync lost pending integration state: %q, %v", result, readErr)
	}
}
