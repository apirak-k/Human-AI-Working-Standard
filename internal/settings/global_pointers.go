package settings

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

const (
	globalPointerStart = "<!-- HAWS_GLOBAL_POINTER_START -->"
	globalPointerEnd   = "<!-- HAWS_GLOBAL_POINTER_END -->"
)

type GlobalPointerSyncResult struct {
	Targets   int
	Updated   int
	Preserved int
	Adopted   int
	Skipped   int
	Messages  []string
}

type globalPointerOwnership struct {
	kind, path, source, fingerprint string
}

type globalPointerTarget struct {
	name, path string
}

type globalPointerBlock struct {
	hasStart  bool
	malformed bool
	bytes     []byte
	outside   []byte
}

// SyncGlobalPointers keeps HAWS instruction blocks current while preserving
// the surrounding content and any file that HAWS cannot verify as its own.
func SyncGlobalPointers(ctx context.Context, root, home, stateDir, secondBrainDir string, environments []string, adoptLegacy, recoverLegacy bool) (GlobalPointerSyncResult, error) {
	var result GlobalPointerSyncResult
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if root == "" || home == "" || stateDir == "" {
		return result, errors.New("global pointer sync needs source, home, and state directories")
	}
	var err error
	root, err = filepath.Abs(root)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS source directory: %w", err)
	}
	home, err = filepath.Abs(home)
	if err != nil {
		return result, fmt.Errorf("resolve global pointer home: %w", err)
	}
	stateDir, err = filepath.Abs(stateDir)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS state directory: %w", err)
	}
	if secondBrainDir == "" {
		secondBrainDir = filepath.Join(root, "secondbrain")
	} else if !filepath.IsAbs(secondBrainDir) {
		secondBrainDir = filepath.Join(root, secondBrainDir)
	}
	secondBrainDir, err = filepath.Abs(secondBrainDir)
	if err != nil {
		return result, fmt.Errorf("resolve Second Brain directory: %w", err)
	}
	if err := validateAgentStateDir(stateDir); err != nil {
		return result, err
	}

	targets, err := globalPointerTargets(home, environments)
	if err != nil {
		return result, err
	}
	ledgerPath := filepath.Join(stateDir, "ownership.tsv")
	ledger, ledgerExists, ledgerMode, err := readAgentOwnershipLedger(ledgerPath)
	if err != nil {
		return result, err
	}
	block := globalPointerContent(root, secondBrainDir)
	fingerprint := agentFileHash(block)
	for _, target := range targets {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		result.Targets++
		if err := safeSkillLinkParent(home, target.path); err != nil {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Global pointer parent is unsafe: %s", target.path))
			continue
		}
		record, owned := findGlobalPointerOwnership(ledger, target.path)
		info, statErr := os.Lstat(target.path)
		if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return result, fmt.Errorf("inspect global pointer %s: %w", target.path, statErr)
		}
		exists := statErr == nil
		if exists && info.Mode()&os.ModeSymlink != 0 {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Global pointer target is a user-managed link: %s", target.path))
			continue
		}
		if exists && !info.Mode().IsRegular() {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Global pointer target is not a regular file: %s", target.path))
			continue
		}

		var contents []byte
		pointerSource := "appended"
		if exists {
			if info.Size() > maxGlobalPointerFileBytes {
				return result, fmt.Errorf("global pointer file exceeds size limit: %s", target.path)
			}
			contents, err = os.ReadFile(target.path)
			if err != nil {
				return result, fmt.Errorf("read global pointer %s: %w", target.path, err)
			}
			parsed := parseGlobalPointerBlock(contents)
			if parsed.hasStart {
				if parsed.malformed {
					result.Preserved++
					result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Global pointer markers are malformed: %s", target.path))
					continue
				}
				if !owned {
					outsideState := "appended"
					if !bytesHasNonSpace(parsed.outside) {
						outsideState = "created"
					}
					if (adoptLegacy || recoverLegacy) && len(parsed.bytes) > 0 && agentFileHash(parsed.bytes) == fingerprint &&
						(!recoverLegacy || pointerPredatesLedgerMigration(stateDir, target.path)) {
						record = globalPointerOwnership{kind: "pointer-block", path: target.path, source: outsideState, fingerprint: fingerprint}
						ledger, err = upsertGlobalPointerOwnership(ledger, record)
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
						result.Skipped++
						result.Messages = append(result.Messages, fmt.Sprintf("[ADOPTED] Exact legacy HAWS pointer ownership: %s", target.path))
						continue
					}
					if !isCanonicalGlobalPointer(contents) {
						if len(parsed.bytes) > 0 && agentFileHash(parsed.bytes) == fingerprint {
							result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Exact HAWS pointer is unowned outside the one-time legacy migration: %s", target.path))
						} else {
							result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Existing global pointer block is not an exact HAWS block: %s", target.path))
						}
						result.Preserved++
						continue
					}
					pointerSource = outsideState
				} else {
					if record.kind != "pointer-block" {
						result.Preserved++
						result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Existing global pointer ownership type is unsupported: %s", target.path))
						continue
					}
					if agentFileHash(parsed.bytes) != record.fingerprint || record.fingerprint == "" {
						result.Preserved++
						result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] HAWS pointer block was edited; leaving it untouched: %s", target.path))
						continue
					}
					if record.fingerprint == fingerprint {
						result.Skipped++
						continue
					}
					if record.source == "created" {
						pointerSource = "created"
					}
				}
			}
		} else {
			pointerSource = "created"
		}

		updated := block
		if exists {
			parsed := parseGlobalPointerBlock(contents)
			if parsed.hasStart {
				updated = replaceGlobalPointerBlock(contents, block)
			} else {
				updated = make([]byte, 0, len(contents)+1+len(block))
				updated = append(updated, contents...)
				updated = append(updated, '\n')
				updated = append(updated, block...)
			}
		}
		mode := fs.FileMode(0o644)
		if exists {
			mode = info.Mode().Perm()
		}
		if err := os.MkdirAll(filepath.Dir(target.path), 0o755); err != nil {
			return result, fmt.Errorf("create global pointer directory: %w", err)
		}
		if err := safeSkillLinkParent(home, target.path); err != nil {
			result.Preserved++
			result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Global pointer parent changed during sync: %s", target.path))
			continue
		}
		if err := writeGlobalPointer(target.path, updated, mode); err != nil {
			return result, err
		}
		parsed := parseGlobalPointerBlock(updated)
		if len(parsed.bytes) == 0 || agentFileHash(parsed.bytes) != fingerprint {
			return result, fmt.Errorf("generated global pointer did not verify: %s", target.path)
		}
		record = globalPointerOwnership{kind: "pointer-block", path: target.path, source: pointerSource, fingerprint: fingerprint}
		ledger, err = upsertGlobalPointerOwnership(ledger, record)
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
		result.Updated++
		result.Messages = append(result.Messages, fmt.Sprintf("[UPDATED] HAWS Global Pointer in %s", target.path))
	}
	return result, nil
}

const maxGlobalPointerFileBytes = 16 << 20

func globalPointerTargets(home string, environments []string) ([]globalPointerTarget, error) {
	seen := make(map[string]bool)
	targets := make([]globalPointerTarget, 0, len(environments))
	for _, environment := range environments {
		if seen[environment] {
			continue
		}
		seen[environment] = true
		var target string
		switch environment {
		case "claude":
			target = filepath.Join(home, ".claude", "CLAUDE.md")
		case "gemini":
			target = filepath.Join(home, ".gemini", "GEMINI.md")
		case "codex":
			override := filepath.Join(home, ".codex", "AGENTS.override.md")
			if info, err := os.Stat(override); err == nil && info.Size() > 0 {
				target = override
			} else {
				agents := filepath.Join(home, ".codex", "AGENTS.md")
				if info, err := os.Stat(agents); err == nil && info.Mode().IsRegular() {
					target = agents
				} else if info, err := os.Stat(filepath.Join(home, ".codex")); err == nil && info.IsDir() {
					target = override
				}
			}
		default:
			return nil, fmt.Errorf("unsupported global pointer environment %q", environment)
		}
		if target != "" {
			targets = append(targets, globalPointerTarget{name: environment, path: target})
		}
	}
	if len(environments) == 0 {
		return nil, errors.New("global pointer sync needs at least one environment")
	}
	return targets, nil
}

func globalPointerContent(root, secondBrainDir string) []byte {
	return []byte(fmt.Sprintf("%s\n# HAWS — Human-AI Working Standard\nThis environment operates under HAWS. Read and adhere to:\n- Core Standard: %s\n- Work Instructions: %s\n- Second Brain documents: %s/ (neutral defaults in public main; personal DEV content stays in the private DEV checkout)\n- Subagent roles: %s/agents/ (organizer, researcher, frontend-engineer, backend-engineer, tester). Read the relevant role before delegating with available native subagent tools.\n%s\n",
		globalPointerStart, filepath.Join(root, "core", "HAWS.md"), filepath.Join(root, "core", "WORK_INSTRUCTIONS.md"), secondBrainDir, root, globalPointerEnd))
}

func parseGlobalPointerBlock(contents []byte) globalPointerBlock {
	lines := splitPointerLines(contents)
	var result globalPointerBlock
	startCount, endCount := 0, 0
	startIndex, endIndex := -1, -1
	for index, line := range lines {
		if strings.Contains(line, globalPointerStart) {
			result.hasStart = true
			startCount++
			if line == globalPointerStart {
				startIndex = index
			}
		}
		if strings.Contains(line, globalPointerEnd) {
			endCount++
			if line == globalPointerEnd {
				endIndex = index
			}
		}
	}
	if !result.hasStart {
		result.outside = contents
		return result
	}
	if startCount != 1 || endCount != 1 {
		result.malformed = true
		result.outside = contents
		return result
	}
	if startIndex < 0 || endIndex <= startIndex {
		result.outside = contents
		return result
	}
	for index, line := range lines {
		if index >= startIndex && index <= endIndex {
			result.bytes = append(result.bytes, line...)
			result.bytes = append(result.bytes, '\n')
			continue
		}
		result.outside = append(result.outside, line...)
		result.outside = append(result.outside, '\n')
	}
	return result
}

func splitPointerLines(contents []byte) []string {
	lines := strings.Split(string(contents), "\n")
	if len(lines) > 0 && lines[len(lines)-1] == "" && strings.HasSuffix(string(contents), "\n") {
		lines = lines[:len(lines)-1]
	}
	return lines
}

func replaceGlobalPointerBlock(contents, replacement []byte) []byte {
	lines := splitPointerLines(contents)
	var outside strings.Builder
	inside := false
	for _, rawLine := range lines {
		line := strings.TrimSuffix(rawLine, "\r")
		switch line {
		case globalPointerStart:
			inside = true
			continue
		case globalPointerEnd:
			inside = false
			continue
		}
		if !inside {
			outside.WriteString(line)
			outside.WriteByte('\n')
		}
	}
	var updated strings.Builder
	updated.WriteString(outside.String())
	updated.WriteByte('\n')
	updated.Write(replacement)
	return []byte(updated.String())
}

func bytesHasNonSpace(contents []byte) bool {
	return strings.TrimSpace(string(contents)) != ""
}

func isCanonicalGlobalPointer(contents []byte) bool {
	text := string(contents)
	return strings.Contains(text, "# HAWS — Human-AI Working Standard") &&
		strings.Contains(text, "- Core Standard: ") && strings.Contains(text, "- Work Instructions: ")
}

func pointerPredatesLedgerMigration(stateDir, target string) bool {
	marker := filepath.Join(stateDir, "integration-ownership-migration-v1")
	if _, err := os.Lstat(marker); errors.Is(err, os.ErrNotExist) {
		marker = filepath.Join(stateDir, "ownership-ledger-v2")
	}
	pointerInfo, pointerErr := os.Stat(target)
	markerInfo, markerErr := os.Stat(marker)
	return pointerErr == nil && markerErr == nil && pointerInfo.ModTime().Unix() <= markerInfo.ModTime().Unix()
}

func findGlobalPointerOwnership(lines []string, target string) (globalPointerOwnership, bool) {
	for _, line := range lines {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) == 6 && fields[0] == "pointers" && fields[2] == target && fields[5] == "schema=2" {
			return globalPointerOwnership{kind: fields[1], path: fields[2], source: fields[3], fingerprint: fields[4]}, true
		}
	}
	return globalPointerOwnership{}, false
}

func upsertGlobalPointerOwnership(lines []string, record globalPointerOwnership) ([]string, error) {
	fields := []string{"pointers", record.kind, record.path, record.source, record.fingerprint, "schema=2"}
	for _, field := range fields {
		if strings.ContainsAny(field, "\t\r\n") {
			return nil, errors.New("global pointer ownership fields cannot contain tabs or newlines")
		}
	}
	updated := make([]string, 0, len(lines)+1)
	inserted := false
	for _, line := range lines {
		row := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(row) == 6 && row[0] == "pointers" && row[2] == record.path && row[5] == "schema=2" {
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

func writeGlobalPointer(path string, contents []byte, mode fs.FileMode) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".haws-pointer-*.tmp")
	if err != nil {
		return fmt.Errorf("stage global pointer %s: %w", path, err)
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
		return fmt.Errorf("replace global pointer %s: %w", path, err)
	}
	return nil
}
