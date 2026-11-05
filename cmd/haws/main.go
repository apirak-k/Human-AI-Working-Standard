package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/app"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

var version = "dev"

func main() {
	if len(os.Args) == 2 && os.Args[1] == "--haws-resolve-active-binary" {
		os.Exit(resolveActiveBinary(os.Stdout, os.Stderr))
	}
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func resolveActiveBinary(stdout, stderr io.Writer) int {
	current, err := os.Executable()
	if err != nil {
		fmt.Fprintln(stderr, "resolve HAWS executable path:", err)
		return 1
	}
	root, err := update.FindInstallRoot(current, runtime.GOOS)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	active, err := update.ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if active == "" {
		active, err = filepath.Abs(current)
		if err != nil {
			fmt.Fprintln(stderr, "resolve base HAWS executable path:", err)
			return 1
		}
	}
	if _, err := fmt.Fprintln(stdout, active); err != nil {
		fmt.Fprintln(stderr, "write resolved HAWS executable path:", err)
		return 1
	}
	return 0
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintf(stdout, "HAWS %s\n", version)
		return 0
	}
	if len(args) > 0 && args[0] == "migrate" {
		packageRoot, err := findPackageRootForRun()
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return actionExitCode(app.RunMigration(packageRoot, args[1:], stdin, stdout, stderr), stderr)
	}
	if len(args) == 1 && (args[0] == "menu" || args[0] == "interactive") {
		args = nil
	}
	root, err := findRootForRun()
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ctx := context.Background()
	if len(args) > 0 {
		action := commandAction(args[0])
		if action == "" {
			return actionExitCode(legacy.RunCommand(ctx, root, args, stdin, stdout, stderr), stderr)
		}
		return actionExitCode(runAction(ctx, root, action, args, stdin, stdout, stderr), stderr)
	}
	if !setupAlreadyExists(root) {
		if _, err := fmt.Fprintln(stdout, "[INFO] First launch detected; starting HAWS Setup."); err != nil {
			fmt.Fprintln(stderr, "write first-run message:", err)
			return 1
		}
		if err := runAction(ctx, root, tui.ActionSetup, nil, stdin, stdout, stderr); err != nil {
			return actionExitCode(err, stderr)
		}
	}
	err = tui.Run(stdin, stdout, func(action tui.Action, actionInput io.Reader) error {
		root, err = findRootForRun()
		if err != nil {
			return err
		}
		return runAction(ctx, root, action, nil, actionInput, stdout, stderr)
	})
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func setupAlreadyExists(root string) bool {
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	} else if !filepath.IsAbs(stateDir) {
		stateDir = filepath.Join(root, stateDir)
	}
	for _, name := range []string{"install.complete", "settings.tsv"} {
		info, err := os.Lstat(filepath.Join(stateDir, name))
		if err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 && (name != "install.complete" || info.Size() > 0) {
			return true
		}
	}
	return false
}

func findRootForRun() (string, error) {
	explicitRoot := os.Getenv("HAWS_ROOT")
	appRoot := ""
	if explicitRoot != "" {
		appRoot = packageRootForPath(explicitRoot)
		if appRoot == "" {
			packageDir := os.Getenv("HAWS_PACKAGE_DIR")
			if packageDir != "" {
				appRoot = packageDir
			}
		}
		if appRoot == "" {
			return legacy.FindRoot()
		}
	} else if configured := os.Getenv("HAWS_APP_DIR"); configured != "" {
		appRoot = configured
	} else {
		executable, err := os.Executable()
		if err != nil {
			return "", fmt.Errorf("resolve HAWS executable path: %w", err)
		}
		if installedRoot, err := update.FindInstallRoot(executable, runtime.GOOS); err == nil {
			appRoot = installedRoot
		}
	}
	if appRoot == "" {
		return legacy.FindRoot()
	}
	runtimeRoot, err := update.ActiveRuntime(appRoot, runtime.GOOS)
	if err != nil {
		return "", err
	}
	return legacy.ConfigurePackageRuntime(appRoot, runtimeRoot)
}

func findPackageRootForRun() (string, error) {
	for _, candidate := range []string{os.Getenv("HAWS_APP_DIR"), os.Getenv("HAWS_PACKAGE_DIR"), os.Getenv("HAWS_ROOT")} {
		if packageRoot := packageRootForPath(candidate); packageRoot != "" {
			resolved, err := filepath.EvalSymlinks(packageRoot)
			if err != nil {
				return "", fmt.Errorf("resolve HAWS package directory: %w", err)
			}
			return resolved, nil
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve HAWS executable path: %w", err)
	}
	packageRoot, err := update.FindInstallRoot(executable, runtime.GOOS)
	if err != nil || packageRoot == "" || !hasPackageManifest(packageRoot) {
		return "", errors.New("migration is available from an installed HAWS package; start the package launcher first")
	}
	resolved, err := filepath.EvalSymlinks(packageRoot)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	return resolved, nil
}

func packageRootForPath(root string) string {
	absolute, err := filepath.Abs(root)
	if err != nil {
		return ""
	}
	if hasPackageManifest(absolute) {
		return absolute
	}
	if filepath.Base(absolute) == "runtime" && hasPackageManifest(filepath.Dir(absolute)) {
		return filepath.Dir(absolute)
	}
	return ""
}

func hasPackageManifest(root string) bool {
	info, err := os.Lstat(filepath.Join(root, "package-manifest.json"))
	return err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0
}

func commandAction(command string) tui.Action {
	switch command {
	case "setup", "bootstrap":
		return tui.ActionSetup
	case "sync", "update", "install":
		return tui.ActionSync
	case "settings", "configure":
		return tui.ActionSettings
	case "doctor", "test":
		return tui.ActionDoctor
	case "repair":
		return tui.ActionRepair
	case "uninstall", "remove":
		return tui.ActionUninstall
	default:
		return ""
	}
}

func runAction(ctx context.Context, root string, action tui.Action, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		args = []string{string(action)}
	}
	if action == tui.ActionSync {
		return app.RunSync(ctx, args, stdin, stdout, stderr)
	}
	if action == tui.ActionRepair {
		return app.RunRepair(ctx, stdin, stdout, stderr)
	}
	if action == tui.ActionSetup || action == tui.ActionSettings {
		return app.RunSettings(ctx, root, args, stdin, stdout, stderr)
	}
	if action == tui.ActionUninstall {
		return app.RunUninstall(ctx, args, stdin, stdout, stderr)
	}
	if action == tui.ActionMigration {
		packageRoot, err := findPackageRootForRun()
		if err != nil {
			return err
		}
		return app.RunMigrationWizard(packageRoot, stdin, stdout, stderr)
	}
	return legacy.RunCommand(ctx, root, args, stdin, stdout, stderr)
}

func actionExitCode(err error, stderr io.Writer) int {
	if err == nil {
		return 0
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	fmt.Fprintln(stderr, err)
	return 1
}
