package settings

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

type ClaudeCommandSyncResult struct {
	Targets   int
	Generated int
	Preserved int
	Adopted   int
	Messages  []string
}

type claudeCommand struct {
	name, source, destination string
	content                   []byte
}

var claudeCommandDescription = regexp.MustCompile(`^[\t ]*description:[\t ]*["']?([^"'#\r\n]+)["']?.*$`)

// SyncClaudeCommands generates owned slash commands for registered custom skills.
func SyncClaudeCommands(ctx context.Context, sourceRoot, home, stateDir, legacyManifest string, adoptLegacy bool) (ClaudeCommandSyncResult, error) {
	var result ClaudeCommandSyncResult
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if sourceRoot == "" || home == "" || stateDir == "" {
		return result, errors.New("Claude command linking needs source, home, and state directories")
	}
	var err error
	sourceRoot, err = filepath.Abs(sourceRoot)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS custom skills: %w", err)
	}
	home, err = filepath.Abs(home)
	if err != nil {
		return result, fmt.Errorf("resolve Claude home: %w", err)
	}
	stateDir, err = filepath.Abs(stateDir)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS state directory: %w", err)
	}
	if err := validateAgentStateDir(stateDir); err != nil {
		return result, err
	}

	customRoot := filepath.Join(sourceRoot, "skills", "custom")
	rootInfo, err := os.Lstat(customRoot)
	if errors.Is(err, os.ErrNotExist) {
		return result, nil
	}
	if err != nil {
		return result, fmt.Errorf("inspect custom skills directory: %w", err)
	}
	if !rootInfo.IsDir() || rootInfo.Mode()&os.ModeSymlink != 0 {
		return result, fmt.Errorf("custom skills path is not an unlinked directory: %s", customRoot)
	}
	entries, err := os.ReadDir(customRoot)
	if err != nil {
		return result, fmt.Errorf("read custom skills directory: %w", err)
	}
	commands := make([]claudeCommand, 0, len(entries))
	for _, entry := range entries {
		customDir := filepath.Join(customRoot, entry.Name())
		info, err := os.Lstat(customDir)
		if err != nil {
			return result, fmt.Errorf("inspect custom skill %s: %w", customDir, err)
		}
		if !info.IsDir() {
			continue
		}
		if info.Mode()&os.ModeSymlink != 0 || !safeSkillTargetName(entry.Name()) || strings.Contains(entry.Name(), "/") {
			return result, fmt.Errorf("unsafe custom skill directory: %s", customDir)
		}
		name := entry.Name()
		description := "Execute the custom " + name + " skill workflow."
		for _, filename := range []string{"SKILL.md", "skill.md"} {
			path := filepath.Join(customDir, filename)
			fileInfo, err := os.Lstat(path)
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			if err != nil {
				return result, fmt.Errorf("inspect custom skill entrypoint %s: %w", path, err)
			}
			if !fileInfo.Mode().IsRegular() || fileInfo.Mode()&os.ModeSymlink != 0 {
				return result, fmt.Errorf("custom skill entrypoint is not a regular file: %s", path)
			}
			contents, err := os.ReadFile(path)
			if err != nil {
				return result, fmt.Errorf("read custom skill entrypoint %s: %w", path, err)
			}
			if extracted := parseClaudeCommandDescription(string(contents)); extracted != "" {
				description = extracted
			}
			break
		}
		commands = append(commands, claudeCommand{
			name: name, source: filepath.Join(customDir, "SKILL.md"),
			destination: filepath.Join(home, ".claude", "commands", name+".md"),
			content:     claudeCommandContent(name, description),
		})
	}

	ledgerPath := filepath.Join(stateDir, "ownership.tsv")
	ledger, ledgerExists, ledgerMode, err := readAgentOwnershipLedger(ledgerPath)
	if err != nil {
		return result, err
	}
	legacyEntries, err := readLegacyAgentManifest(legacyManifest, adoptLegacy)
	if err != nil {
		return result, err
	}
	for _, command := range commands {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		result.Targets++
		if err := safeSkillLinkParent(home, command.destination); err != nil {
			return result, fmt.Errorf("Claude command destination is unsafe: %w", err)
		}
		record, owned, err := findAgentFileOwnership(ledger, command.destination)
		if err != nil {
			return result, err
		}
		info, statErr := os.Lstat(command.destination)
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return result, fmt.Errorf("inspect Claude command %s: %w", command.destination, statErr)
		}
		exists := statErr == nil
		if exists && !owned && adoptLegacy && legacyManifestHasSkillTarget(legacyEntries, command.name) &&
			info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 {
			contents, err := os.ReadFile(command.destination)
			if err != nil {
				return result, fmt.Errorf("read legacy Claude command %s: %w", command.destination, err)
			}
			if bytes.Equal(contents, command.content) {
				record = agentFileOwnership{kind: "generated-file", path: command.destination, source: command.source, fingerprint: agentFileHash(contents)}
				owned = true
				result.Adopted++
				result.Messages = append(result.Messages, fmt.Sprintf("[ADOPTED] Exact legacy Claude Slash Command [/%s]: %s", command.name, command.destination))
			}
		}
		if exists && !owned {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Claude Slash Command [/%s]: existing file is not recorded as HAWS-owned: %s", command.name, command.destination))
			continue
		}
		mode := fs.FileMode(0o644)
		if exists {
			verified, _ := verifyAgentFileOwnership(record, command.destination)
			if !verified {
				result.Preserved++
				result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Claude Slash Command [/%s]: owned file changed; leaving it untouched: %s", command.name, command.destination))
				continue
			}
			if info.Mode().IsRegular() {
				mode = info.Mode().Perm()
			}
		}
		if err := os.MkdirAll(filepath.Dir(command.destination), 0o755); err != nil {
			return result, fmt.Errorf("create Claude commands directory: %w", err)
		}
		if err := writeClaudeCommand(command.destination, command.content, mode); err != nil {
			return result, err
		}
		record = agentFileOwnership{kind: "generated-file", path: command.destination, source: command.source, fingerprint: agentFileHash(command.content)}
		ledger, err = upsertAgentFileOwnership(ledger, record)
		if err != nil {
			return result, err
		}
		if !ledgerExists {
			ledgerMode = 0o600
		}
		if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
			return result, err
		}
		ledgerExists = true
		result.Generated++
		result.Messages = append(result.Messages, fmt.Sprintf("[CONFIG] Claude Slash Command [/%s]: %s", command.name, command.destination))
	}
	return result, nil
}

func parseClaudeCommandDescription(contents string) string {
	for _, line := range strings.Split(contents, "\n") {
		match := claudeCommandDescription.FindStringSubmatch(strings.TrimSuffix(line, "\r"))
		if len(match) == 2 {
			return strings.TrimSpace(match[1])
		}
	}
	return ""
}

func claudeCommandContent(name, description string) []byte {
	return []byte(fmt.Sprintf("---\ndescription: %s\n---\nExecute the %s skill workflow defined in ~/.claude/skills/%s/SKILL.md.\n", description, name, name))
}

func writeClaudeCommand(path string, contents []byte, mode fs.FileMode) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".claude-command-*.tmp")
	if err != nil {
		return fmt.Errorf("stage Claude command %s: %w", path, err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode.Perm()); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(contents); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, path); err != nil {
		return fmt.Errorf("replace Claude command %s: %w", path, err)
	}
	return nil
}

func legacyManifestHasSkillTarget(entries map[string]bool, wanted string) bool {
	for entry := range entries {
		if !strings.HasPrefix(entry, "skill:") {
			continue
		}
		payload := strings.TrimPrefix(entry, "skill:")
		target := payload
		if index := strings.IndexByte(payload, '\t'); index >= 0 {
			target = payload[index+1:]
		} else if index := strings.LastIndex(payload, "::"); index >= 0 {
			target = payload[index+2:]
		}
		if target == wanted {
			return true
		}
	}
	return false
}
