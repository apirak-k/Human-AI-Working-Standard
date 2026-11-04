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
	if len(args) > 1 {
		fmt.Fprintln(stderr, "Usage: haws [sync|settings|doctor|uninstall|--version]")
		return 2
	}
	root, err := legacy.FindRoot()
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ctx := context.Background()
	if len(args) == 1 {
		return actionExitCode(runAction(ctx, root, tui.Action(args[0]), stdin, stdout, stderr), stderr)
	}
	err = tui.Run(stdin, stdout, func(action tui.Action) error {
		return runAction(ctx, root, action, stdin, stdout, stderr)
	})
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func runAction(ctx context.Context, root string, action tui.Action, stdin io.Reader, stdout, stderr io.Writer) error {
	if action == tui.ActionSync {
		return app.RunSync(ctx, stdin, stdout, stderr)
	}
	if action == tui.ActionUninstall {
		return app.RunUninstall(ctx, stdin, stdout, stderr)
	}
	return legacy.Run(ctx, root, action, stdin, stdout, stderr)
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
