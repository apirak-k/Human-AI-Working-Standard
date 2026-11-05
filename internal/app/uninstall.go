package app

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/uninstall"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

type legacyUninstall func(context.Context, string, io.Reader, io.Writer, io.Writer) error

type Uninstaller struct {
	CurrentExecutable string
	Legacy            legacyUninstall
}

type uninstallSnapshot struct {
	complete bool
	info     os.FileInfo
	contents []byte
}

// Run presents the Go package cleanup alongside the existing ownership-aware
// uninstall, then removes the package overlay only after the legacy full
// uninstall records completion. The checkout and base package stay intact.
func (u Uninstaller) Run(ctx context.Context, root, appRoot string, stdin io.Reader, stdout, stderr io.Writer) error {
	if u.Legacy == nil {
		return errors.New("HAWS legacy uninstall is not configured")
	}
	plan, previewErr := uninstall.Preview(appRoot, u.CurrentExecutable)
	if previewErr != nil {
		_, _ = fmt.Fprintf(stdout, "[WARN] Go app update cleanup preview failed; preserving package files: %v\n", previewErr)
	} else {
		items := plan.Items()
		if len(items) > 0 {
			fmt.Fprintln(stdout, "Go app package cleanup preview:")
			for _, item := range items {
				fmt.Fprintf(stdout, "  • %s\n", item)
			}
		}
	}
	before := snapshotUninstallCompletion(root)
	if err := u.Legacy(ctx, root, stdin, stdout, stderr); err != nil {
		return err
	}
	if !newUninstallCompletion(before, snapshotUninstallCompletion(root)) {
		return nil
	}
	if previewErr != nil {
		return fmt.Errorf("HAWS integrations were uninstalled, but Go app files were preserved because cleanup could not be verified: %w", previewErr)
	}
	result, err := uninstall.Apply(plan)
	for _, item := range result.Removed {
		fmt.Fprintf(stdout, "[PASS] Removed verified %s.\n", item)
	}
	for _, item := range result.Preserved {
		fmt.Fprintf(stdout, "[KEEP] Preserved %s.\n", item)
	}
	if len(result.Preserved) > 0 {
		fmt.Fprintln(stdout, "[WARN] Package cleanup left the listed items in place; complete package removal did not occur.")
	} else if err == nil && len(result.Removed) > 0 {
		fmt.Fprintln(stdout, "[PASS] All verified HAWS package files were removed.")
	}
	return err
}

func RunUninstall(ctx context.Context, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		args = []string{"uninstall"}
	}
	root, err := legacy.FindRoot()
	if err != nil {
		return err
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
		return legacy.RunCommand(ctx, root, args, stdin, stdout, stderr)
	}
	executable, _ := os.Executable()
	return (Uninstaller{
		CurrentExecutable: executable,
		Legacy: func(ctx context.Context, root string, stdin io.Reader, stdout, stderr io.Writer) error {
			return legacy.RunCommand(ctx, root, args, stdin, stdout, stderr)
		},
	}).Run(ctx, root, appRoot, stdin, stdout, stderr)
}

func snapshotUninstallCompletion(root string) uninstallSnapshot {
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	} else if !filepath.IsAbs(stateDir) {
		stateDir = filepath.Join(root, stateDir)
	}
	marker := filepath.Join(stateDir, "uninstalled")
	info, err := os.Lstat(marker)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() == 0 {
		return uninstallSnapshot{}
	}
	_, err = os.Lstat(filepath.Join(stateDir, "install.complete"))
	if !errors.Is(err, os.ErrNotExist) {
		return uninstallSnapshot{}
	}
	contents, err := os.ReadFile(marker)
	if err != nil {
		return uninstallSnapshot{}
	}
	return uninstallSnapshot{complete: true, info: info, contents: contents}
}

func newUninstallCompletion(before, after uninstallSnapshot) bool {
	if !after.complete {
		return false
	}
	if !before.complete {
		return true
	}
	return !os.SameFile(before.info, after.info) || !bytes.Equal(before.contents, after.contents)
}
