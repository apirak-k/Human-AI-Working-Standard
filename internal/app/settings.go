package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
)

const maxApplyResultBytes = 1 << 20

// RunSettings delegates the existing Setup or Settings flow, then completes
// any integration work through the Go-owned Sync path exactly once.
func RunSettings(ctx context.Context, root string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		args = []string{"settings"}
	}
	if err := legacy.RunCommand(ctx, root, args, stdin, stdout, stderr); err != nil {
		return err
	}
	pending, err := settingsIntegrationPending(root)
	if err != nil || !pending {
		return err
	}
	if _, err := fmt.Fprintln(stdout, "[INFO] Applying Settings through one Go-hosted authoritative Sync."); err != nil {
		return err
	}
	return RunSync(ctx, nil, strings.NewReader(""), stdout, stderr)
}

func settingsApplyResultPath(root string) string {
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	} else if !filepath.IsAbs(stateDir) {
		stateDir = filepath.Join(root, stateDir)
	}
	return filepath.Join(stateDir, "apply.result")
}

func readSettingsApplyResult(root string) (string, os.FileInfo, string, error) {
	path := settingsApplyResultPath(root)
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return path, nil, "", nil
	}
	if err != nil {
		return path, nil, "", fmt.Errorf("inspect HAWS Settings result: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > maxApplyResultBytes {
		return path, nil, "", errors.New("HAWS Settings result is not a bounded regular file")
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return path, nil, "", fmt.Errorf("read HAWS Settings result: %w", err)
	}
	if int64(len(contents)) > maxApplyResultBytes {
		return path, nil, "", errors.New("HAWS Settings result exceeds the size limit")
	}
	return path, info, string(contents), nil
}

func settingsIntegrationPending(root string) (bool, error) {
	_, _, contents, err := readSettingsApplyResult(root)
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(contents, "\n") {
		if line == "integration\tpending" {
			return true, nil
		}
	}
	return false, nil
}

func completePendingSettingsIntegration(root string) error {
	path, before, contents, err := readSettingsApplyResult(root)
	if err != nil || before == nil {
		return err
	}
	lines := strings.Split(contents, "\n")
	pending := false
	for index, line := range lines {
		if line == "integration\tpending" {
			lines[index] = "integration\tcompleted"
			pending = true
		}
	}
	if !pending {
		return nil
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".apply-result-*.tmp")
	if err != nil {
		return fmt.Errorf("stage HAWS Settings result: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if _, err := io.WriteString(temporary, strings.Join(lines, "\n")); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write HAWS Settings result: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("sync HAWS Settings result: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close HAWS Settings result: %w", err)
	}
	after, err := os.Lstat(path)
	if err != nil || !os.SameFile(before, after) || before.Size() != after.Size() || !before.ModTime().Equal(after.ModTime()) {
		return errors.New("HAWS Settings result changed while Sync was completing")
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("complete HAWS Settings result: %w", err)
	}
	return nil
}
