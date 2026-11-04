package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

var version = "dev"

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
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
		return actionExitCode(legacy.Run(ctx, root, tui.Action(args[0]), stdin, stdout, stderr), stderr)
	}
	err = tui.Run(stdin, stdout, func(action tui.Action) error {
		return legacy.Run(ctx, root, action, stdin, stdout, stderr)
	})
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
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
