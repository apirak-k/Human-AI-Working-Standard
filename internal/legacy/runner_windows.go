//go:build windows

package legacy

import (
	"context"
	"os"
	"os/exec"
)

func legacyCommand(ctx context.Context, root, script string, args ...string) (*exec.Cmd, error) {
	cmdArgs := append([]string{"/d", "/c", script}, args...)
	cmd := command(ctx, "cmd.exe", cmdArgs...)
	cmd.Dir = root
	cmd.Env = setEnvironment(os.Environ(), "HAWS_NO_PAUSE", "1")
	return cmd, nil
}
