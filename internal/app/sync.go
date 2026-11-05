package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

type releaseSource interface {
	DownloadLatestIfChanged(context.Context, string, string) (update.ReleasePackage, bool, error)
}

type packageInstaller interface {
	ActiveVersion(string) (string, error)
	Install(string, string, []byte) error
	Rollback(string) error
}

type legacySync func(context.Context, string, io.Reader, io.Writer, io.Writer) error

type Syncer struct {
	GOOS      string
	Releases  releaseSource
	Installer packageInstaller
	Legacy    legacySync
}

// Run performs the release-managed app update and then delegates the existing
// HAWS Sync, which still owns repository sources, settings, and integrations.
func (s Syncer) Run(ctx context.Context, root, appRoot string, updateEnabled bool, stdin io.Reader, stdout, stderr io.Writer) error {
	if s.Legacy == nil {
		return errors.New("HAWS legacy Sync is not configured")
	}
	var failures []error
	installedVersion := ""
	if updateEnabled {
		if s.Releases == nil || s.Installer == nil {
			failures = append(failures, errors.New("HAWS release update is not configured"))
		} else {
			active, err := s.Installer.ActiveVersion(appRoot)
			if err != nil {
				failures = append(failures, fmt.Errorf("read active HAWS app version: %w", err))
			} else {
				latest, changed, checkErr := s.Releases.DownloadLatestIfChanged(ctx, s.GOOS, active)
				if checkErr != nil {
					failures = append(failures, fmt.Errorf("check for a HAWS app update: %w", checkErr))
				} else if changed {
					if installErr := s.Installer.Install(appRoot, latest.Version, latest.Data); installErr != nil {
						failures = append(failures, fmt.Errorf("install HAWS app %s: %w", latest.Version, installErr))
					} else {
						installedVersion = latest.Version
						if _, outputErr := fmt.Fprintf(stdout, "[PASS] HAWS app updated to %s.\n", latest.Version); outputErr != nil {
							failures = append(failures, fmt.Errorf("report HAWS app update: %w", outputErr))
						}
					}
				} else if _, outputErr := fmt.Fprintf(stdout, "[PASS] HAWS app is up to date (%s).\n", active); outputErr != nil {
					failures = append(failures, fmt.Errorf("report HAWS app version: %w", outputErr))
				}
			}
		}
	}

	legacyErr := s.Legacy(ctx, root, stdin, stdout, stderr)
	if legacyErr != nil {
		failures = append(failures, fmt.Errorf("synchronize HAWS components: %w", legacyErr))
		if installedVersion != "" {
			if rollbackErr := s.Installer.Rollback(appRoot); rollbackErr != nil {
				failures = append(failures, fmt.Errorf("roll back HAWS app after Sync failure: %w", rollbackErr))
			} else if _, outputErr := fmt.Fprintf(stdout, "[WARN] HAWS app update was rolled back after Sync failed.\n"); outputErr != nil {
				failures = append(failures, fmt.Errorf("report HAWS app rollback: %w", outputErr))
			}
		}
	}
	return errors.Join(failures...)
}

// RunSync discovers the checkout and installed package, then runs one Sync
// operation. A source-built Go binary without an OS package keeps the legacy
// Sync available but has no release-managed package directory to update.
func RunSync(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		args = []string{"sync"}
	}
	root, err := legacy.FindRoot()
	if err != nil {
		return err
	}
	updateEnabled, settingsErr := legacy.AutoUpdateEnabled(root)
	if settingsErr != nil {
		return errors.Join(settingsErr, runLegacySync(ctx, root, args, stdin, stdout, stderr))
	}
	appRoot := os.Getenv("HAWS_APP_DIR")
	if appRoot != "" && !filepath.IsAbs(appRoot) {
		appRoot = filepath.Join(root, appRoot)
	}
	if appRoot == "" {
		executable, executableErr := os.Executable()
		if executableErr == nil {
			appRoot, err = update.FindInstallRoot(executable, runtime.GOOS)
		}
	}
	if err != nil || appRoot == "" {
		if updateEnabled {
			if _, outputErr := fmt.Fprintln(stdout, "[INFO] This Go executable is not installed in a HAWS package; using the existing Sync."); outputErr != nil {
				return outputErr
			}
		}
		return runLegacySync(ctx, root, args, stdin, stdout, stderr)
	}

	return Syncer{
		GOOS:      runtime.GOOS,
		Releases:  update.NewReleaseClient(),
		Installer: update.NewInstaller(),
		Legacy: func(ctx context.Context, root string, stdin io.Reader, stdout, stderr io.Writer) error {
			return runLegacySync(ctx, root, args, stdin, stdout, stderr)
		},
	}.Run(ctx, root, appRoot, updateEnabled, stdin, stdout, stderr)
}

func runLegacySync(ctx context.Context, root string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if err := legacy.RunCommand(ctx, root, args, stdin, stdout, stderr); err != nil {
		return err
	}
	return completePendingSettingsIntegration(root)
}
