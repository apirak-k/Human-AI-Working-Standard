package legacy

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

func Run(ctx context.Context, root string, action tui.Action, stdin io.Reader, stdout, stderr io.Writer) error {
	if !validAction(action) {
		return fmt.Errorf("unsupported HAWS action %q", action)
	}
	return RunCommand(ctx, root, []string{string(action)}, stdin, stdout, stderr)
}

// RunCommand passes a supported legacy command and its arguments through the
// Go host without returning to the legacy shell's Home menu.
func RunCommand(ctx context.Context, root string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		return errors.New("legacy HAWS command is required")
	}
	runtime := "haws.sh"
	if os.PathSeparator == '\\' {
		runtime = "haws.bat"
	}
	path := filepath.Join(root, runtime)
	if info, err := os.Stat(path); err != nil || info.IsDir() {
		return fmt.Errorf("legacy HAWS runtime not found at %s", path)
	}
	cmd, err := legacyCommand(ctx, root, path, args...)
	if err != nil {
		return err
	}
	environment := cmd.Env
	if environment == nil {
		environment = os.Environ()
	}
	cmd.Env = setEnvironment(environment, "HAWS_GO_HOST", "1")
	cmd.Stdin = stdin
	cmd.Stdout = stdout
	cmd.Stderr = stderr
	return cmd.Run()
}

func setEnvironment(environment []string, name, value string) []string {
	result := make([]string, 0, len(environment)+1)
	for _, entry := range environment {
		key, _, _ := strings.Cut(entry, "=")
		if !strings.EqualFold(key, name) {
			result = append(result, entry)
		}
	}
	return append(result, name+"="+value)
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
