//go:build windows

package legacy

import (
	"context"
	"os"
	"os/exec"
)

func legacyCommand(ctx context.Context, root, script, action string) (*exec.Cmd, error) {
	cmd := command(ctx, "cmd.exe", "/d", "/c", script, action)
	cmd.Dir = root
	cmd.Env = append(os.Environ(), "HAWS_NO_PAUSE=1")
	return cmd, nil
}
