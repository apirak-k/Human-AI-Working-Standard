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
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	stateDir := filepath.Join(root, ".haws", "state")
	if err := os.MkdirAll(stateDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "settings.tsv"), []byte("schema_version\t1\nauto_update\toff\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(stateDir, "install.complete"), []byte("schema=1\tcompleted_at=2026-11-05T00:00:00Z\n"), 0o600); err != nil {
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
		"  settings|setup) exit 91;;\n" +
		"  sync) printf '%s\\n' \"$HAWS_GO_HOST\" > \"$HAWS_HOST_LOG\"; printf '%s\\n' \"$HAWS_NATIVE_ROOT_SYNC\" > \"$HAWS_ROOT_SYNC_LOG\"; printf '%s\\n' \"$HAWS_NATIVE_SOURCE_SYNC\" > \"$HAWS_SOURCE_SYNC_LOG\"; printf '%s\\n' \"$HAWS_NATIVE_CLAUDE_SKILLS\" > \"$HAWS_CLAUDE_SKILLS_SYNC_LOG\"; printf '%s\\n' \"$HAWS_NATIVE_CODEX_SKILLS\" > \"$HAWS_CODEX_SKILLS_SYNC_LOG\"; exit \"${HAWS_TEST_SYNC_EXIT:-0}\";;\n" +
		"esac\n"
	if runtime.GOOS == "windows" {
		batch := "@echo off\r\necho(%1>>\"%HAWS_CALL_LOG%\"\r\n" +
			"if /I \"%1\"==\"settings\" exit /b 91\r\n" +
			"if /I \"%1\"==\"setup\" exit /b 91\r\n" +
			"if /I \"%1\"==\"sync\" echo %HAWS_GO_HOST% > \"%HAWS_HOST_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" echo %HAWS_NATIVE_ROOT_SYNC% > \"%HAWS_ROOT_SYNC_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" echo %HAWS_NATIVE_SOURCE_SYNC% > \"%HAWS_SOURCE_SYNC_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" echo %HAWS_NATIVE_CLAUDE_SKILLS% > \"%HAWS_CLAUDE_SKILLS_SYNC_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" echo %HAWS_NATIVE_CODEX_SKILLS% > \"%HAWS_CODEX_SKILLS_SYNC_LOG%\"\r\n" +
			"if /I \"%1\"==\"sync\" exit /b %HAWS_TEST_SYNC_EXIT%\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
	} else if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
	// Keep Bash available after isolating HOME on macOS.
	if home, err := os.UserHomeDir(); err == nil {
		t.Setenv("PATH", filepath.Join(home, ".local", "bin")+string(os.PathListSeparator)+os.Getenv("PATH"))
	}
	t.Setenv("HOME", root)
	t.Setenv("USERPROFILE", root)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	t.Setenv("HAWS_APP_DIR", "")
	t.Setenv("HAWS_PACKAGE_DIR", "")
	t.Setenv("HAWS_ROOT", root)
	t.Setenv("HAWS_STATE_DIR", stateDir)
	t.Setenv("HAWS_CALL_LOG", calls)
	t.Setenv("HAWS_HOST_LOG", filepath.Join(root, "host.log"))
	t.Setenv("HAWS_ROOT_SYNC_LOG", filepath.Join(root, "root-sync.log"))
	t.Setenv("HAWS_SOURCE_SYNC_LOG", filepath.Join(root, "source-sync.log"))
	t.Setenv("HAWS_CLAUDE_SKILLS_SYNC_LOG", filepath.Join(root, "claude-skills-sync.log"))
	t.Setenv("HAWS_CODEX_SKILLS_SYNC_LOG", filepath.Join(root, "codex-skills-sync.log"))
	t.Setenv("HAWS_TEST_SYNC_EXIT", syncExit)
	return root, calls, applyResult
}

func TestRunSettingsUsesOneGoHostedSyncWhenIntegrationIsPending(t *testing.T) {
	root, callsPath, resultPath := settingsHostFixture(t, true, "0")
	var stdout, stderr strings.Builder
	if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("6\napply\n"), &stdout, &stderr); err != nil {
		t.Fatalf("RunSettings() error = %v; stderr %q", err, stderr.String())
	}
	calls, err := os.ReadFile(callsPath)
	if err != nil {
		t.Fatal(err)
	}
	gotCalls := strings.ReplaceAll(string(calls), "\r\n", "\n")
	if gotCalls != "sync\n" {
		t.Fatalf("legacy commands = %q, want exactly one Go-hosted Sync", gotCalls)
	}
	host, err := os.ReadFile(filepath.Join(root, "host.log"))
	if err != nil || strings.TrimSpace(strings.ReplaceAll(string(host), "\r\n", "\n")) != "1" {
		t.Fatalf("Go host marker = %q, %v; want 1", host, err)
	}
	rootSync, err := os.ReadFile(filepath.Join(root, "root-sync.log"))
	if err != nil || strings.TrimSpace(strings.ReplaceAll(string(rootSync), "\r\n", "\n")) != "1" {
		t.Fatalf("native root Sync marker = %q, %v; want 1", rootSync, err)
	}
	sourceSync, err := os.ReadFile(filepath.Join(root, "source-sync.log"))
	if err != nil || strings.TrimSpace(strings.ReplaceAll(string(sourceSync), "\r\n", "\n")) != "1" {
		t.Fatalf("native source Sync marker = %q, %v; want 1", sourceSync, err)
	}
	codexSkillsSync, err := os.ReadFile(filepath.Join(root, "codex-skills-sync.log"))
	if err != nil || strings.TrimSpace(strings.ReplaceAll(string(codexSkillsSync), "\r\n", "\n")) != "1" {
		t.Fatalf("native Codex skill Sync marker = %q, %v; want 1", codexSkillsSync, err)
	}
	claudeSkillsSync, err := os.ReadFile(filepath.Join(root, "claude-skills-sync.log"))
	if err != nil || strings.TrimSpace(strings.ReplaceAll(string(claudeSkillsSync), "\r\n", "\n")) != "1" {
		t.Fatalf("native Claude skill Sync marker = %q, %v; want 1", claudeSkillsSync, err)
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
	if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("q\n"), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	if calls, err := os.ReadFile(callsPath); !os.IsNotExist(err) {
		t.Fatalf("native cancel invoked legacy commands = %q, error %v", calls, err)
	}
}

func TestRunSettingsLeavesPendingStateWhenGoSyncFails(t *testing.T) {
	root, callsPath, resultPath := settingsHostFixture(t, true, "7")
	err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader("6\napply\n"), io.Discard, io.Discard)
	var exitErr *exec.ExitError
	if !errors.As(err, &exitErr) || exitErr.ExitCode() != 7 {
		t.Fatalf("RunSettings() error = %v, want child exit 7", err)
	}
	calls, readErr := os.ReadFile(callsPath)
	if readErr != nil || strings.ReplaceAll(string(calls), "\r\n", "\n") != "sync\n" {
		t.Fatalf("legacy commands = %q, %v", calls, readErr)
	}
	result, readErr := os.ReadFile(resultPath)
	if readErr != nil || !strings.Contains(string(result), "integration\tpending") {
		t.Fatalf("failed Sync lost pending integration state: %q, %v", result, readErr)
	}
}
