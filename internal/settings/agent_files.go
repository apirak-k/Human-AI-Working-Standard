package settings

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

type AgentFileSyncResult struct {
	Targets    int
	Linked     int
	Hardlinked int
	Copied     int
	Already    int
	Preserved  int
	Adopted    int
	Messages   []string
}

type agentFileProjection struct {
	name, source, destination, label string
	content                          []byte
	sourceInfo                       fs.FileInfo
}

type agentFileOwnership struct {
	kind, path, source, fingerprint string
}

// SyncAgentFiles projects canonical agent Markdown into Claude and Gemini homes
// while preserving paths that HAWS cannot verify as its own.
func SyncAgentFiles(ctx context.Context, sourceRoot, home, stateDir string, environments []string, legacyManifest string, adoptLegacy bool) (AgentFileSyncResult, error) {
	var result AgentFileSyncResult
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if sourceRoot == "" || home == "" || stateDir == "" {
		return result, errors.New("agent file linking needs source, home, and state directories")
	}
	sourceRoot, err := filepath.Abs(sourceRoot)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS agent source: %w", err)
	}
	home, err = filepath.Abs(home)
	if err != nil {
		return result, fmt.Errorf("resolve agent home: %w", err)
	}
	stateDir, err = filepath.Abs(stateDir)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS state directory: %w", err)
	}

	selected := make([]string, 0, len(environments))
	seenEnvironments := make(map[string]bool, len(environments))
	for _, environment := range environments {
		if environment != "claude" && environment != "gemini" {
			return result, fmt.Errorf("unsupported agent file environment %q", environment)
		}
		if !seenEnvironments[environment] {
			selected = append(selected, environment)
			seenEnvironments[environment] = true
		}
	}
	if len(selected) == 0 {
		return result, errors.New("agent file linking needs at least one environment")
	}
	if err := validateAgentStateDir(stateDir); err != nil {
		return result, err
	}

	agentsDir := filepath.Join(sourceRoot, "agents")
	agentsInfo, err := os.Lstat(agentsDir)
	if errors.Is(err, os.ErrNotExist) {
		return result, nil
	}
	if err != nil {
		return result, fmt.Errorf("inspect HAWS agents directory: %w", err)
	}
	if !agentsInfo.IsDir() || agentsInfo.Mode()&os.ModeSymlink != 0 {
		return result, fmt.Errorf("HAWS agents path is not an unlinked directory: %s", agentsDir)
	}
	entries, err := os.ReadDir(agentsDir)
	if err != nil {
		return result, fmt.Errorf("read HAWS agents directory: %w", err)
	}
	projections := make([]agentFileProjection, 0, len(entries)*len(selected))
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".md") {
			continue
		}
		name := strings.TrimSuffix(entry.Name(), ".md")
		if !safeSkillTargetName(name) || strings.Contains(name, "/") {
			return result, fmt.Errorf("unsafe HAWS agent name %q", name)
		}
		source := filepath.Join(agentsDir, entry.Name())
		info, err := os.Lstat(source)
		if err != nil {
			return result, fmt.Errorf("inspect HAWS agent source %s: %w", source, err)
		}
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return result, fmt.Errorf("HAWS agent source is not a regular file: %s", source)
		}
		content, err := os.ReadFile(source)
		if err != nil {
			return result, fmt.Errorf("read HAWS agent source %s: %w", source, err)
		}
		for _, environment := range selected {
			var destination, label string
			if environment == "claude" {
				destination = filepath.Join(home, ".claude", "agents", name+".md")
				label = "Claude Agent [" + name + "]"
			} else {
				destination = filepath.Join(home, ".gemini", "config", "agents", name, "agent.md")
				label = "Antigravity Agent [" + name + "]"
			}
			projections = append(projections, agentFileProjection{
				name: name, source: source, destination: destination, label: label,
				content: content, sourceInfo: info,
			})
		}
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
	for _, projection := range projections {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		result.Targets++
		if err := safeSkillLinkParent(home, projection.destination); err != nil {
			return result, fmt.Errorf("agent destination is unsafe: %w", err)
		}
		record, owned, err := findAgentFileOwnership(ledger, projection.destination)
		if err != nil {
			return result, err
		}
		destinationInfo, statErr := os.Lstat(projection.destination)
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return result, fmt.Errorf("inspect agent destination %s: %w", projection.destination, statErr)
		}
		exists := statErr == nil
		if exists && !owned && adoptLegacy && legacyEntries["agent:"+projection.name] {
			if adopted, ok, err := exactLegacyAgentOwnership(projection, destinationInfo); err != nil {
				return result, err
			} else if ok {
				record, owned = adopted, true
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
				result.Adopted++
				result.Messages = append(result.Messages, fmt.Sprintf("[ADOPTED] Exact legacy %s: %s", projection.label, projection.destination))
			}
		}
		if exists && !owned {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] %s: existing item is not recorded as HAWS-owned: %s", projection.label, projection.destination))
			continue
		}
		if exists && owned {
			if (record.kind == "symlink" || record.kind == "hardlink") && destinationInfo.Mode().IsRegular() && destinationInfo.Mode()&os.ModeSymlink == 0 &&
				!sameAgentFile(projection.source, projection.destination) {
				current, readErr := os.ReadFile(projection.destination)
				if readErr != nil {
					return result, fmt.Errorf("read owned agent destination %s: %w", projection.destination, readErr)
				}
				if bytes.Equal(projection.content, current) {
					record = agentFileOwnership{kind: "generated-file", path: projection.destination, source: projection.source, fingerprint: agentFileHash(current)}
					ledger, err = upsertAgentFileOwnership(ledger, record)
					if err != nil {
						return result, err
					}
					if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
						return result, err
					}
					result.Messages = append(result.Messages, fmt.Sprintf("[REPAIRED] Corrected stale agent link ownership: %s", projection.destination))
				}
			}
			verified, currentTarget := verifyAgentFileOwnership(record, projection.destination)
			if !verified {
				result.Preserved++
				result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] %s: owned item changed; leaving it untouched: %s", projection.label, projection.destination))
				continue
			}
			if record.kind == "symlink" && currentTarget == projection.source {
				record.fingerprint = currentTarget
				ledger, err = upsertAgentFileOwnership(ledger, record)
				if err != nil {
					return result, err
				}
				if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
					return result, err
				}
				result.Already++
				continue
			}
			if record.kind == "hardlink" && sameAgentFile(projection.source, projection.destination) {
				record.fingerprint = agentFileHash(projection.content)
				ledger, err = upsertAgentFileOwnership(ledger, record)
				if err != nil {
					return result, err
				}
				if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
					return result, err
				}
				result.Already++
				continue
			}
			if err := os.Remove(projection.destination); err != nil {
				return result, fmt.Errorf("replace HAWS-owned agent destination %s: %w", projection.destination, err)
			}
		}

		if err := os.MkdirAll(filepath.Dir(projection.destination), 0o755); err != nil {
			return result, fmt.Errorf("create agent destination directory: %w", err)
		}
		kind, err := createAgentFileProjection(projection)
		if err != nil {
			return result, err
		}
		record = agentFileOwnership{kind: kind, path: projection.destination, source: projection.source, fingerprint: projection.source}
		if kind == "generated-file" || kind == "hardlink" {
			record.fingerprint = agentFileHash(projection.content)
		}
		ledger, err = upsertAgentFileOwnership(ledger, record)
		if err != nil {
			_ = os.Remove(projection.destination)
			return result, err
		}
		if !ledgerExists {
			ledgerMode = 0o600
		}
		if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
			_ = os.Remove(projection.destination)
			return result, err
		}
		ledgerExists = true
		switch kind {
		case "symlink":
			result.Linked++
			result.Messages = append(result.Messages, fmt.Sprintf("[LINKED] %s: %s -> %s", projection.label, projection.destination, projection.source))
		case "hardlink":
			result.Hardlinked++
			result.Messages = append(result.Messages, fmt.Sprintf("[HARDLINK] %s: %s -> %s", projection.label, projection.destination, projection.source))
		default:
			result.Copied++
			result.Messages = append(result.Messages, fmt.Sprintf("[COPIED] %s: %s -> %s", projection.label, projection.destination, projection.source))
		}
	}
	return result, nil
}

func validateAgentStateDir(stateDir string) error {
	if stateInfo, err := os.Lstat(stateDir); err == nil && (!stateInfo.IsDir() || stateInfo.Mode()&os.ModeSymlink != 0) {
		return fmt.Errorf("HAWS state path is not an unlinked directory: %s", stateDir)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect HAWS state directory: %w", err)
	}
	return nil
}

func readAgentOwnershipLedger(path string) ([]string, bool, fs.FileMode, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, 0o600, nil
	}
	if err != nil {
		return nil, false, 0, fmt.Errorf("inspect agent ownership ledger %s: %w", path, err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maxSkillOwnershipBytes {
		return nil, false, 0, fmt.Errorf("agent ownership ledger is not a bounded regular file: %s", path)
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return nil, false, 0, fmt.Errorf("read agent ownership ledger %s: %w", path, err)
	}
	if len(contents) > maxSkillOwnershipBytes {
		return nil, false, 0, fmt.Errorf("agent ownership ledger exceeds size limit: %s", path)
	}
	trimmed := strings.TrimSuffix(string(contents), "\n")
	if trimmed == "" {
		return nil, true, info.Mode().Perm(), nil
	}
	return strings.Split(trimmed, "\n"), true, info.Mode().Perm(), nil
}

func readLegacyAgentManifest(path string, enabled bool) (map[string]bool, error) {
	entries := make(map[string]bool)
	if !enabled || path == "" {
		return entries, nil
	}
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return entries, nil
	}
	if err != nil {
		return nil, fmt.Errorf("inspect legacy HAWS manifest: %w", err)
	}
	if !info.Mode().IsRegular() || info.Size() > maxSkillOwnershipBytes {
		return nil, fmt.Errorf("legacy HAWS manifest is not a bounded regular file: %s", path)
	}
	contents, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read legacy HAWS manifest: %w", err)
	}
	if len(contents) > maxSkillOwnershipBytes {
		return nil, errors.New("legacy HAWS manifest exceeds size limit")
	}
	for _, line := range strings.Split(string(contents), "\n") {
		entries[strings.TrimSuffix(line, "\r")] = true
	}
	return entries, nil
}

func findAgentFileOwnership(lines []string, destination string) (agentFileOwnership, bool, error) {
	var found agentFileOwnership
	for _, line := range lines {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) != 6 || fields[0] != "agents" || fields[5] != "schema=2" || !sameSkillPath(fields[2], destination) {
			continue
		}
		record := agentFileOwnership{kind: fields[1], path: fields[2], source: fields[3], fingerprint: fields[4]}
		if found.path != "" && found != record {
			return agentFileOwnership{}, false, fmt.Errorf("conflicting agent ownership records for %s", destination)
		}
		found = record
	}
	return found, found.path != "", nil
}

func exactLegacyAgentOwnership(projection agentFileProjection, info fs.FileInfo) (agentFileOwnership, bool, error) {
	if info.Mode()&os.ModeSymlink != 0 {
		linkTarget, err := os.Readlink(projection.destination)
		if err != nil {
			return agentFileOwnership{}, false, err
		}
		if linkTarget == projection.source || sameAgentFile(projection.source, projection.destination) {
			return agentFileOwnership{kind: "symlink", path: projection.destination, source: projection.source, fingerprint: linkTarget}, true, nil
		}
		return agentFileOwnership{}, false, nil
	}
	if !info.Mode().IsRegular() {
		return agentFileOwnership{}, false, nil
	}
	if sameAgentFile(projection.source, projection.destination) {
		return agentFileOwnership{kind: "hardlink", path: projection.destination, source: projection.source, fingerprint: agentFileHash(projection.content)}, true, nil
	}
	contents, err := os.ReadFile(projection.destination)
	if err != nil {
		return agentFileOwnership{}, false, err
	}
	if bytes.Equal(contents, projection.content) {
		return agentFileOwnership{kind: "generated-file", path: projection.destination, source: projection.source, fingerprint: agentFileHash(contents)}, true, nil
	}
	return agentFileOwnership{}, false, nil
}

func verifyAgentFileOwnership(record agentFileOwnership, destination string) (bool, string) {
	info, err := os.Lstat(destination)
	if err != nil {
		return false, ""
	}
	switch record.kind {
	case "symlink":
		if info.Mode()&os.ModeSymlink == 0 {
			return false, ""
		}
		current, err := os.Readlink(destination)
		if err != nil || record.fingerprint == "" {
			return false, current
		}
		currentPath := resolveLinkTarget(destination, current)
		sourcePath := resolveLinkTarget(destination, record.source)
		matches := sameSkillPath(current, record.source) || sameSkillPath(currentPath, sourcePath)
		if !matches {
			currentResolved, currentErr := filepath.EvalSymlinks(currentPath)
			sourceResolved, sourceErr := filepath.EvalSymlinks(sourcePath)
			matches = currentErr == nil && sourceErr == nil && sameSkillPath(currentResolved, sourceResolved)
		}
		if !matches {
			return false, current
		}
		fingerprintMatches := record.fingerprint == current || record.fingerprint == currentPath
		if !fingerprintMatches {
			if canonical, err := filepath.EvalSymlinks(currentPath); err == nil && record.fingerprint == canonical {
				fingerprintMatches = true
			}
			if canonical, err := filepath.EvalSymlinks(sourcePath); err == nil && record.fingerprint == canonical {
				fingerprintMatches = true
			}
		}
		return fingerprintMatches, current
	case "generated-file", "file", "hardlink":
		if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || record.fingerprint == "" {
			return false, ""
		}
		contents, err := os.ReadFile(destination)
		if err != nil {
			return false, ""
		}
		return agentFileHash(contents) == record.fingerprint, ""
	default:
		return false, ""
	}
}

func createAgentFileProjection(projection agentFileProjection) (string, error) {
	if runtime.GOOS == "windows" {
		if err := os.Link(projection.source, projection.destination); err == nil {
			if sameAgentFile(projection.source, projection.destination) {
				return "hardlink", nil
			}
			_ = os.Remove(projection.destination)
		}
	}
	if err := os.Symlink(projection.source, projection.destination); err == nil {
		if info, statErr := os.Lstat(projection.destination); statErr == nil && info.Mode()&os.ModeSymlink != 0 {
			if target, readErr := os.Readlink(projection.destination); readErr == nil && target == projection.source {
				return "symlink", nil
			}
		}
		_ = os.Remove(projection.destination)
	}
	file, err := os.OpenFile(projection.destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, projection.sourceInfo.Mode().Perm())
	if err != nil {
		return "", fmt.Errorf("create agent file projection %s: %w", projection.destination, err)
	}
	if _, err := file.Write(projection.content); err != nil {
		_ = file.Close()
		_ = os.Remove(projection.destination)
		return "", fmt.Errorf("write agent file projection %s: %w", projection.destination, err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		_ = os.Remove(projection.destination)
		return "", fmt.Errorf("sync agent file projection %s: %w", projection.destination, err)
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(projection.destination)
		return "", fmt.Errorf("close agent file projection %s: %w", projection.destination, err)
	}
	return "generated-file", nil
}

func upsertAgentFileOwnership(lines []string, record agentFileOwnership) ([]string, error) {
	fields := []string{"agents", record.kind, record.path, record.source, record.fingerprint, "schema=2"}
	for _, field := range fields {
		if strings.ContainsAny(field, "\t\r\n") {
			return nil, errors.New("agent ownership fields cannot contain tabs or newlines")
		}
	}
	updated := make([]string, 0, len(lines)+1)
	inserted := false
	for _, line := range lines {
		row := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(row) == 6 && row[0] == "agents" && row[5] == "schema=2" && sameSkillPath(row[2], record.path) {
			if !inserted {
				updated = append(updated, strings.Join(fields, "\t"))
				inserted = true
			}
			continue
		}
		updated = append(updated, line)
	}
	if !inserted {
		updated = append(updated, strings.Join(fields, "\t"))
	}
	return updated, nil
}

func writeAgentOwnershipLedger(path string, lines []string, mode fs.FileMode) error {
	data := []byte(strings.Join(lines, "\n") + "\n")
	if len(data) > maxSkillOwnershipBytes {
		return errors.New("agent ownership ledger exceeds size limit")
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return fmt.Errorf("create agent ownership directory: %w", err)
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".agents-ownership-*.tmp")
	if err != nil {
		return fmt.Errorf("stage agent ownership ledger: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode.Perm()); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
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
		return fmt.Errorf("replace agent ownership ledger: %w", err)
	}
	return nil
}

func sameAgentFile(source, destination string) bool {
	sourceInfo, sourceErr := os.Stat(source)
	destinationInfo, destinationErr := os.Stat(destination)
	return sourceErr == nil && destinationErr == nil && os.SameFile(sourceInfo, destinationInfo)
}

func agentFileHash(contents []byte) string {
	hash := sha256.Sum256(contents)
	return hex.EncodeToString(hash[:])
}
