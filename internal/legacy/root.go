package legacy

import (
	"fmt"
	"os"
	"path/filepath"
)

func FindRoot() (string, error) {
	if root := os.Getenv("HAWS_ROOT"); root != "" {
		return validateRoot(root)
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("find HAWS checkout from current directory: %w", err)
	}
	executable, _ := os.Executable()
	starts := []string{cwd}
	if executable != "" {
		starts = append(starts, filepath.Dir(executable))
	}
	seen := make(map[string]bool)
	for _, start := range starts {
		for dir := start; ; dir = filepath.Dir(dir) {
			if seen[dir] {
				break
			}
			seen[dir] = true
			if fileInfo, err := os.Stat(filepath.Join(dir, "haws.sh")); err == nil && !fileInfo.IsDir() {
				return dir, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
		}
	}
	return "", fmt.Errorf("could not find a HAWS checkout containing haws.sh; set HAWS_ROOT")
}

func validateRoot(root string) (string, error) {
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS root %q: %w", root, err)
	}
	info, err := os.Stat(filepath.Join(absolute, "haws.sh"))
	if err != nil || info.IsDir() {
		return "", fmt.Errorf("HAWS root %q does not contain haws.sh", absolute)
	}
	return absolute, nil
}
