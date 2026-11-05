package app

import (
	"context"
	"errors"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

func nativeSettingsSnapshot(t *testing.T, root string) map[string]string {
	t.Helper()
	files := make(map[string]string)
	if err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		if entry.IsDir() {
			files[relative] = "directory"
			return nil
		}
		data, err := os.ReadFile(path)
		if err == nil {
			files[relative] = string(data)
		}
		return err
	}); err != nil {
		t.Fatal(err)
	}
	return files
}

func assertNativeSettingsNoLegacyCalls(t *testing.T, callsPath string) {
	t.Helper()
	if calls, err := os.ReadFile(callsPath); !os.IsNotExist(err) {
		t.Fatalf("native Settings invoked legacy commands %q, error %v", calls, err)
	}
}

func TestNativeSettingsConfigOnlyApplyNeverRunsLegacy(t *testing.T) {
	for _, relative := range []bool{false, true} {
		name := "absolute-state"
		if relative {
			name = "relative-state"
		}
		t.Run(name, func(t *testing.T) {
			root, callsPath, _ := settingsHostFixture(t, false, "0")
			if relative {
				t.Setenv("HAWS_STATE_DIR", filepath.Join(".haws", "state"))
			}
			before, err := settings.NewStore(root).Load()
			if err != nil {
				t.Fatal(err)
			}
			var output strings.Builder
			err = RunSettings(context.Background(), root, nil, strings.NewReader("5\n1\nq\n6\napply\n"), &output, io.Discard)
			if err != nil {
				t.Fatalf("config-only apply: %v\n%s", err, output.String())
			}
			assertNativeSettingsNoLegacyCalls(t, callsPath)
			state, err := settings.NewStore(root).Load()
			if err != nil || state.Config.AutoUpdateSkills == before.Config.AutoUpdateSkills || state.Config.AutoUpdateBrain != before.Config.AutoUpdateBrain {
				t.Fatalf("saved config = %+v, error %v", state.Config, err)
			}
			if !strings.Contains(output.String(), "Preview") {
				t.Fatalf("apply omitted preview: %s", output.String())
			}
		})
	}
}

func TestNativeSettingsConfigApplyNeedsNoBashOrGitExecutable(t *testing.T) {
	root, calls, _ := settingsHostFixture(t, false, "0")
	t.Setenv("PATH", t.TempDir())
	if err := RunSettings(context.Background(), root, nil, strings.NewReader("5\n1\nq\n6\napply\n"), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	assertNativeSettingsNoLegacyCalls(t, calls)
	state, err := settings.NewStore(root).Load()
	if err != nil || !state.Config.AutoUpdateSkills {
		t.Fatal(state.Config, err)
	}
}

func TestNativeSetupInitialInstallRunsExactlyOneGoHostedSync(t *testing.T) {
	for _, tc := range []struct{ name, status string }{{"success", "0"}, {"sync-failure", "7"}} {
		t.Run(tc.name, func(t *testing.T) {
			root, callsPath, resultPath := settingsHostFixture(t, false, tc.status)
			stateDir := filepath.Dir(resultPath)
			for _, name := range []string{"settings.tsv", "install.complete"} {
				if err := os.Remove(filepath.Join(stateDir, name)); err != nil {
					t.Fatal(err)
				}
			}
			var output strings.Builder
			err := RunSettings(context.Background(), root, []string{"setup"}, strings.NewReader("2\n5\n1\nq\n6\napply\n"), &output, io.Discard)
			if tc.status == "0" {
				if err != nil {
					t.Fatalf("initial install: %v\n%s", err, output.String())
				}
			} else {
				var exitErr *exec.ExitError
				if !errors.As(err, &exitErr) || exitErr.ExitCode() != 7 {
					t.Fatalf("initial install error %v, want Sync exit 7", err)
				}
				var status interface{ ExitCode() int }
				if !errors.As(err, &status) || status.ExitCode() != 7 {
					t.Fatalf("initial install lost exit status 7: %v", err)
				}
			}
			calls, readErr := os.ReadFile(callsPath)
			if readErr != nil || strings.ReplaceAll(string(calls), "\r\n", "\n") != "sync\n" {
				t.Fatalf("legacy commands = %q, %v; want exactly one sync", calls, readErr)
			}
			host, readErr := os.ReadFile(filepath.Join(root, "host.log"))
			if readErr != nil || strings.TrimSpace(string(host)) != "1" {
				t.Fatalf("Sync Go host marker = %q, %v", host, readErr)
			}
			result, readErr := os.ReadFile(resultPath)
			if readErr != nil {
				t.Fatal(readErr)
			}
			if !strings.Contains(string(result), "settings\tcompleted") {
				t.Fatalf("initial install did not retain saved settings progress: %q", result)
			}
			_, markerErr := os.Stat(filepath.Join(stateDir, "install.complete"))
			if tc.status == "0" {
				if markerErr != nil || !strings.Contains(string(result), "integration\tcompleted") {
					t.Fatalf("successful install result %q, marker error %v", result, markerErr)
				}
			} else if !os.IsNotExist(markerErr) || !strings.Contains(string(result), "integration\tpending") {
				t.Fatalf("failed install result %q, marker error %v", result, markerErr)
			}
		})
	}
}

func TestNativeSettingsCancelInvalidInputAndEOFNeverWrite(t *testing.T) {
	for _, input := range []string{"q\n", "invalid\nq\n", "5\n1\nq\nq\n2\n", "5\n1\nq\n6\nq\n", "5\n1\nq\n6\n"} {
		t.Run(strings.ReplaceAll(input, "\n", "/"), func(t *testing.T) {
			root, callsPath, _ := settingsHostFixture(t, true, "0")
			before := nativeSettingsSnapshot(t, root)
			if err := RunSettings(context.Background(), root, []string{"settings"}, strings.NewReader(input), io.Discard, io.Discard); err != nil {
				t.Fatal(err)
			}
			assertNativeSettingsNoLegacyCalls(t, callsPath)
			if after := nativeSettingsSnapshot(t, root); !reflect.DeepEqual(before, after) {
				t.Fatalf("canceled Settings changed files\nbefore: %#v\nafter: %#v", before, after)
			}
		})
	}
}

func TestNativeSetupCancelPreservesFirstRun(t *testing.T) {
	root, callsPath, resultPath := settingsHostFixture(t, false, "0")
	stateDir := filepath.Dir(resultPath)
	if err := os.RemoveAll(stateDir); err != nil {
		t.Fatal(err)
	}
	before := nativeSettingsSnapshot(t, root)
	input := strings.NewReader("q\n3\n")
	if err := RunSettings(context.Background(), root, []string{"setup"}, input, io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	assertNativeSettingsNoLegacyCalls(t, callsPath)
	if after := nativeSettingsSnapshot(t, root); !reflect.DeepEqual(before, after) {
		t.Fatal("canceled Setup changed first-run files")
	}
	remaining, err := io.ReadAll(input)
	if err != nil || string(remaining) != "3\n" {
		t.Fatalf("Setup consumed following Home input %q, error %v", remaining, err)
	}
}

type nativeSettingsFailWriter struct{ err error }

func (w nativeSettingsFailWriter) Write([]byte) (int, error) { return 0, w.err }

func TestNativeSettingsPropagatesContextAndOutputErrors(t *testing.T) {
	for _, canceled := range []bool{false, true} {
		name := "output-failure"
		if canceled {
			name = "canceled-context"
		}
		t.Run(name, func(t *testing.T) {
			root, callsPath, _ := settingsHostFixture(t, false, "0")
			before := nativeSettingsSnapshot(t, root)
			ctx := context.Background()
			want := errors.New("terminal unavailable")
			var out io.Writer = nativeSettingsFailWriter{want}
			if canceled {
				var cancel context.CancelFunc
				ctx, cancel = context.WithCancel(ctx)
				cancel()
				want = context.Canceled
				out = io.Discard
			}
			err := RunSettings(ctx, root, []string{"settings"}, strings.NewReader("6\napply\n"), out, io.Discard)
			if !errors.Is(err, want) {
				t.Fatalf("Settings error %v, want %v", err, want)
			}
			assertNativeSettingsNoLegacyCalls(t, callsPath)
			if !reflect.DeepEqual(before, nativeSettingsSnapshot(t, root)) {
				t.Fatal("failed Settings changed files")
			}
		})
	}
}
