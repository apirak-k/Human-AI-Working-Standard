package main

import (
	"bytes"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRunPreservesSupportedLegacyArgumentsAndExitStatus(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	writeArgsRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"doctor", "--json"}, strings.NewReader(""), &stdout, &stderr); code != 7 {
		t.Fatalf("run() exit = %d, want legacy exit 7 (stderr %q)", code, stderr.String())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != "doctor\n--json\n" {
		t.Fatalf("legacy args = %q", args)
	}
}

func TestRunPreservesSyncAndUninstallOptionsAcrossGoHost(t *testing.T) {
	for _, tc := range []struct {
		name string
		args []string
		want string
	}{
		{name: "sync clean", args: []string{"sync", "--clean"}, want: "sync\n--clean\n"},
		{name: "uninstall dry run", args: []string{"uninstall", "--dry-run"}, want: "uninstall\n--dry-run\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			argsPath := filepath.Join(root, "args.txt")
			writeArgsRuntime(t, root, argsPath)
			t.Setenv("HAWS_ROOT", root)
			var stdout, stderr bytes.Buffer
			if code := run(tc.args, strings.NewReader(""), &stdout, &stderr); code != 7 {
				t.Fatalf("run() exit = %d, want legacy exit 7 (stderr %q)", code, stderr.String())
			}
			args, err := os.ReadFile(argsPath)
			if err != nil {
				t.Fatal(err)
			}
			if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != tc.want {
				t.Fatalf("legacy args = %q, want %q", normalized, tc.want)
			}
		})
	}
}

func TestRunDirectRepairPreviewsBeforeAnySync(t *testing.T) {
	root := t.TempDir()
	argsPath := filepath.Join(root, "args.txt")
	writeDoctorRuntime(t, root, argsPath)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"repair"}, strings.NewReader("n\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("repair exit = %d, stderr = %q", code, stderr.String())
	}
	args, err := os.ReadFile(argsPath)
	if err != nil {
		t.Fatal(err)
	}
	if normalized := strings.ReplaceAll(string(args), "\r\n", "\n"); normalized != "doctor\n--deep\n" {
		t.Fatalf("repair legacy args = %q, want diagnostics only", args)
	}
	if !strings.Contains(stdout.String(), "Repair plan") || !strings.Contains(stdout.String(), "No changes were made") {
		t.Fatalf("repair did not preview and cancel safely: %q", stdout.String())
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
	writeUnknownRuntime(t, root)
	t.Setenv("HAWS_ROOT", root)
	var stdout, stderr bytes.Buffer
	if code := run([]string{"unknown"}, strings.NewReader(""), &stdout, &stderr); code != 1 {
		t.Fatalf("run() exit = %d, want 1", code)
	}
	if !strings.Contains(stderr.String(), "Usage:") {
		t.Fatalf("legacy usage missing: %q", stderr.String())
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

func writeArgsRuntime(t *testing.T, root, argsPath string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Setenv("HAWS_TEST_ARGS", argsPath)
		batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %2>> \"%HAWS_TEST_ARGS%\"\r\nexit /b 7\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"" + argsPath + "\"\nexit 7\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}

func writeUnknownRuntime(t *testing.T, root string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		batch := "@echo off\r\necho Usage: unknown 1>&2\r\nexit /b 1\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte("#!/bin/sh\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\necho 'Usage: unknown' >&2\nexit 1\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}

func writeDoctorRuntime(t *testing.T, root, argsPath string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Setenv("HAWS_TEST_ARGS", argsPath)
		batch := "@echo off\r\necho %1> \"%HAWS_TEST_ARGS%\"\r\necho %2>> \"%HAWS_TEST_ARGS%\"\r\necho doctor-preview\r\n"
		if err := os.WriteFile(filepath.Join(root, "haws.bat"), []byte(batch), 0o600); err != nil {
			t.Fatal(err)
		}
		return
	}
	script := "#!/bin/sh\nprintf '%s\\n' \"$@\" >> '" + argsPath + "'\necho doctor-preview\n"
	if err := os.WriteFile(filepath.Join(root, "haws.sh"), []byte(script), 0o700); err != nil {
		t.Fatal(err)
	}
}
