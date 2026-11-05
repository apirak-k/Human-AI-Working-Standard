package app

import (
	"bytes"
	"context"
	"errors"
	"io"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

type fakeReleaseSource struct {
	packageData update.ReleasePackage
	changed     bool
	err         error
	calls       int
	active      string
	goos        string
	order       *[]string
}

func (f *fakeReleaseSource) DownloadLatestIfChanged(_ context.Context, goos, active string) (update.ReleasePackage, bool, error) {
	f.calls++
	f.active = active
	f.goos = goos
	if f.order != nil {
		*f.order = append(*f.order, "release")
	}
	return f.packageData, f.changed, f.err
}

type fakeInstaller struct {
	active      string
	previous    string
	installErr  error
	rollbackErr error
	installs    []string
	rollbacks   int
	order       *[]string
}

func (f *fakeInstaller) ActiveVersion(string) (string, error) { return f.active, nil }

func (f *fakeInstaller) Install(_ string, version string, _ []byte) error {
	f.installs = append(f.installs, version)
	if f.order != nil {
		*f.order = append(*f.order, "install")
	}
	if f.installErr == nil {
		f.previous = f.active
		f.active = version
	}
	return f.installErr
}

func (f *fakeInstaller) Rollback(string) error {
	f.rollbacks++
	if f.order != nil {
		*f.order = append(*f.order, "rollback")
	}
	if f.rollbackErr == nil && f.previous != "" {
		f.active = f.previous
	}
	return f.rollbackErr
}

func TestSyncerInstallsReleaseBeforeRunningLegacySyncOnce(t *testing.T) {
	order := []string{}
	releases := &fakeReleaseSource{
		packageData: update.ReleasePackage{Version: "v1.2.3", Data: []byte("verified")},
		changed:     true,
		order:       &order,
	}
	installer := &fakeInstaller{active: "base", order: &order}
	stdin := strings.NewReader("input")
	var stdout, stderr bytes.Buffer
	legacyCalls := 0
	syncer := Syncer{
		GOOS:      "darwin",
		Releases:  releases,
		Installer: installer,
		RuntimeRoot: func(appRoot string) (string, error) {
			if appRoot != "/app" {
				t.Fatalf("runtime resolver got app root %q", appRoot)
			}
			return "/app/versions/v1.2.3/runtime", nil
		},
		Legacy: func(_ context.Context, root string, gotIn io.Reader, gotOut, gotErr io.Writer) error {
			legacyCalls++
			if root != "/app/versions/v1.2.3/runtime" || gotIn != stdin || gotOut != &stdout || gotErr != &stderr {
				t.Fatal("legacy Sync did not receive its root and terminal streams")
			}
			order = append(order, "legacy")
			return nil
		},
	}
	if err := syncer.Run(context.Background(), "/app/runtime", "/app", true, stdin, &stdout, &stderr); err != nil {
		t.Fatalf("Syncer.Run() error = %v", err)
	}
	if legacyCalls != 1 || releases.calls != 1 || releases.active != "base" || releases.goos != "darwin" {
		t.Fatalf("calls = legacy:%d releases:%#v", legacyCalls, releases)
	}
	if got := strings.Join(order, ","); got != "release,install,legacy" {
		t.Fatalf("operation order = %q", got)
	}
	if installer.active != "v1.2.3" || !strings.Contains(stdout.String(), "updated to v1.2.3") {
		t.Fatalf("active version/output = %q / %q", installer.active, stdout.String())
	}
}

func TestSyncerSkipsReleaseUpdateWhenAutoUpdateIsDisabled(t *testing.T) {
	releases := &fakeReleaseSource{}
	installer := &fakeInstaller{active: "base"}
	legacyCalls := 0
	syncer := Syncer{
		GOOS:      "linux",
		Releases:  releases,
		Installer: installer,
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error {
			legacyCalls++
			return nil
		},
	}
	if err := syncer.Run(context.Background(), "/checkout", "/app", false, strings.NewReader(""), io.Discard, io.Discard); err != nil {
		t.Fatal(err)
	}
	if releases.calls != 0 || legacyCalls != 1 || len(installer.installs) != 0 {
		t.Fatalf("release calls=%d, legacy calls=%d, installs=%v", releases.calls, legacyCalls, installer.installs)
	}
}

func TestSyncerContinuesLegacySyncWhenReleaseCheckFails(t *testing.T) {
	checkErr := errors.New("offline")
	releases := &fakeReleaseSource{err: checkErr}
	legacyCalls := 0
	syncer := Syncer{
		GOOS:      "linux",
		Releases:  releases,
		Installer: &fakeInstaller{active: "base"},
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error {
			legacyCalls++
			return nil
		},
	}
	err := syncer.Run(context.Background(), "/checkout", "/app", true, strings.NewReader(""), io.Discard, io.Discard)
	if !errors.Is(err, checkErr) || legacyCalls != 1 {
		t.Fatalf("Syncer.Run() = %v; legacy calls=%d", err, legacyCalls)
	}
}

func TestSyncerRollsBackInstalledAppWhenLegacySyncFails(t *testing.T) {
	legacyErr := errors.New("component sync failed")
	order := []string{}
	releases := &fakeReleaseSource{packageData: update.ReleasePackage{Version: "v1.2.3"}, changed: true, order: &order}
	installer := &fakeInstaller{active: "base", order: &order}
	selectedRuntime := ""
	syncer := Syncer{
		GOOS:      "linux",
		Releases:  releases,
		Installer: installer,
		RuntimeRoot: func(appRoot string) (string, error) {
			if appRoot != "/app" {
				t.Fatalf("runtime resolver got app root %q", appRoot)
			}
			if installer.active == "base" {
				selectedRuntime = "/app/runtime"
				return selectedRuntime, nil
			}
			selectedRuntime = "/app/versions/" + installer.active + "/runtime"
			return selectedRuntime, nil
		},
		Legacy: func(_ context.Context, root string, _ io.Reader, _, _ io.Writer) error {
			if root != "/app/versions/v1.2.3/runtime" {
				t.Fatalf("legacy Sync used runtime %q before rollback", root)
			}
			order = append(order, "legacy")
			return legacyErr
		},
	}
	err := syncer.Run(context.Background(), "/checkout", "/app", true, strings.NewReader(""), io.Discard, io.Discard)
	if !errors.Is(err, legacyErr) || installer.rollbacks != 1 {
		t.Fatalf("Syncer.Run() = %v; rollback calls=%d", err, installer.rollbacks)
	}
	if got := strings.Join(order, ","); got != "release,install,legacy,rollback" {
		t.Fatalf("operation order = %q", got)
	}
	if installer.active != "base" {
		t.Fatalf("active app version after rollback = %q; want base", installer.active)
	}
	if selectedRuntime != "/app/runtime" {
		t.Fatalf("runtime after rollback = %q; want /app/runtime", selectedRuntime)
	}
}

func TestSyncerDoesNotRollbackWhenNoReleaseWasInstalled(t *testing.T) {
	legacyErr := errors.New("component sync failed")
	installer := &fakeInstaller{active: "v1.2.3"}
	syncer := Syncer{
		GOOS:      "linux",
		Releases:  &fakeReleaseSource{packageData: update.ReleasePackage{Version: "v1.2.3"}},
		Installer: installer,
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error {
			return legacyErr
		},
	}
	if err := syncer.Run(context.Background(), "/checkout", "/app", true, strings.NewReader(""), io.Discard, io.Discard); !errors.Is(err, legacyErr) {
		t.Fatalf("Syncer.Run() error = %v", err)
	}
	if installer.rollbacks != 0 {
		t.Fatalf("rollback calls = %d; want 0", installer.rollbacks)
	}
}

func TestSyncerReportsInstallFailureAndStillRunsLegacySync(t *testing.T) {
	installErr := errors.New("activation rejected")
	installer := &fakeInstaller{active: "base", installErr: installErr}
	legacyCalls := 0
	syncer := Syncer{
		GOOS:      "linux",
		Releases:  &fakeReleaseSource{packageData: update.ReleasePackage{Version: "v1.2.3"}, changed: true},
		Installer: installer,
		Legacy: func(context.Context, string, io.Reader, io.Writer, io.Writer) error {
			legacyCalls++
			return nil
		},
	}
	if err := syncer.Run(context.Background(), "/checkout", "/app", true, strings.NewReader(""), io.Discard, io.Discard); !errors.Is(err, installErr) {
		t.Fatalf("Syncer.Run() error = %v", err)
	}
	if legacyCalls != 1 || installer.rollbacks != 0 {
		t.Fatalf("legacy calls=%d, rollback calls=%d", legacyCalls, installer.rollbacks)
	}
}
