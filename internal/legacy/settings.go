package legacy

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

const maxSettingsBytes = 1 << 20

// AutoUpdateEnabled reads the setting that gates the legacy Sync's HAWS and
// skill updates. A missing settings file uses HAWS's default, which is on.
func AutoUpdateEnabled(root string) (bool, error) {
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	} else if !filepath.IsAbs(stateDir) {
		stateDir = filepath.Join(root, stateDir)
	}
	filename := filepath.Join(stateDir, "settings.tsv")
	info, err := os.Lstat(filename)
	if errors.Is(err, os.ErrNotExist) {
		return true, nil
	}
	if err != nil {
		return false, fmt.Errorf("inspect HAWS settings: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > maxSettingsBytes {
		return false, errors.New("HAWS settings are not a bounded regular file")
	}
	file, err := os.Open(filename)
	if err != nil {
		return false, fmt.Errorf("open HAWS settings: %w", err)
	}
	defer file.Close()

	updateSkills := "on"
	skillsExplicit := false
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 4096), maxSettingsBytes)
	for lineNumber := 1; scanner.Scan(); lineNumber++ {
		line := strings.TrimSuffix(scanner.Text(), "\r")
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		key := fields[0]
		value := ""
		if len(fields) > 1 {
			value = fields[1]
		}
		invalid := func() (bool, error) {
			return false, fmt.Errorf("HAWS settings line %d is invalid", lineNumber)
		}
		switch key {
		case "schema_version":
			if len(fields) != 2 || value != "1" {
				return invalid()
			}
		case "second_brain", "second_brain_enabled", "auto_update_brain":
			if len(fields) != 2 || !validToggle(value) {
				return invalid()
			}
		case "second_brain_remote":
			if len(fields) != 2 || !validRemote(value) {
				return invalid()
			}
		case "auto_update":
			if len(fields) != 2 || !validToggle(value) {
				return invalid()
			}
			if !skillsExplicit {
				updateSkills = value
			}
		case "auto_update_skills":
			if len(fields) != 2 || !validToggle(value) {
				return invalid()
			}
			updateSkills = value
			skillsExplicit = true
		default:
			return invalid()
		}
	}
	if err := scanner.Err(); err != nil {
		return false, fmt.Errorf("read HAWS settings: %w", err)
	}
	return updateSkills == "on", nil
}

func validToggle(value string) bool {
	return value == "on" || value == "off"
}

func validRemote(value string) bool {
	if value == "" {
		return true
	}
	for _, character := range value {
		if unicode.IsControl(character) {
			return false
		}
	}
	if strings.HasPrefix(value, "-") {
		return false
	}
	if strings.HasPrefix(value, "git@") {
		repository := strings.TrimPrefix(value, "git@")
		separator := strings.IndexByte(repository, ':')
		return separator > 0 && separator < len(repository)-1
	}
	separator := strings.Index(value, "://")
	return separator > 0 && separator+3 < len(value)
}
