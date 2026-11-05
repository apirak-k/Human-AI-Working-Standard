//go:build !windows

package legacy

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
)

func legacyCommand(ctx context.Context, root, script string, args ...string) (*exec.Cmd, error) {
	bash, err := findSupportedBash()
	if err != nil {
		return nil, err
	}
	cmdArgs := append([]string{script}, args...)
	cmd := command(ctx, bash, cmdArgs...)
	cmd.Dir = root
	return cmd, nil
}

func findSupportedBash() (string, error) {
	home, _ := os.UserHomeDir()
	candidates := []string{}
	if home != "" {
		candidates = append(candidates, filepath.Join(home, ".local", "bin", "bash"))
	}
	candidates = append(candidates, "/opt/homebrew/bin/bash", "/usr/local/bin/bash")
	if path, err := exec.LookPath("bash"); err == nil {
		candidates = append(candidates, path)
	}
	seen := make(map[string]bool)
	for _, candidate := range candidates {
		if candidate == "" || seen[candidate] {
			continue
		}
		seen[candidate] = true
		info, err := os.Stat(candidate)
		if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
			continue
		}
		check := exec.Command(candidate, "-c", "(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) ))")
		if err := check.Run(); err == nil {
			return candidate, nil
		}
	}
	return "", errors.New("legacy HAWS actions need Bash 4.2 or newer; install a supported Bash or use the existing HAWS launcher")
}
