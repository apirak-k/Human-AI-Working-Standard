package update

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

// FindInstallRoot finds the package directory that owns the OS launcher used
// to start the current Go binary.
func FindInstallRoot(executable, goos string) (string, error) {
	spec, err := platformForOS(goos)
	if err != nil {
		return "", err
	}
	if executable == "" {
		return "", errors.New("HAWS executable path is required")
	}
	absolute, err := filepath.Abs(executable)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS executable path: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS executable path: %w", err)
	}
	for directory := filepath.Dir(resolved); ; directory = filepath.Dir(directory) {
		launcher := filepath.Join(directory, spec.launcher)
		info, statErr := os.Lstat(launcher)
		if statErr == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 {
			return directory, nil
		}
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return "", fmt.Errorf("inspect HAWS package launcher: %w", statErr)
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			break
		}
	}
	return "", errors.New("could not find an HAWS package launcher beside the executable")
}

func ResolveInstallRoot(root string) (string, error) {
	return resolveInstallRoot(root)
}
