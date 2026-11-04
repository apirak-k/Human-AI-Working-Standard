package legacy

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

func Run(ctx context.Context, root string, action tui.Action, stdin io.Reader, stdout, stderr io.Writer) error {
	if !validAction(action) {
		return fmt.Errorf("unsupported HAWS action %q", action)
	}
	runtime := "haws.sh"
	if os.PathSeparator == '\\' {
		runtime = "haws.bat"
	}
	path := filepath.Join(root, runtime)
	if info, err := os.Stat(path); err != nil || info.IsDir() {
		return fmt.Errorf("legacy HAWS runtime not found at %s", path)
	}
	cmd, err := legacyCommand(ctx, root, path, string(action))
	if err != nil {
		return err
	}
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	return cmd.Run()
}

func validAction(action tui.Action) bool {
	switch action {
	case "setup", "sync", "settings", "doctor", "uninstall":
		return true
	default:
		return false
	}
}

func command(ctx context.Context, program string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, program, args...)
}
