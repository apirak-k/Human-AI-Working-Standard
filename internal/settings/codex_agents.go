package settings

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var codexAgentRoles = []string{"backend-engineer", "frontend-engineer", "organizer", "researcher", "tester"}

var codexAgentHashPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

type CodexAgentProfile struct {
	Name    string
	Path    string
	Source  string
	Hash    string
	Managed bool
}

type CodexAgentOperationResult struct {
	Message      string
	AgentsDir    string
	ManifestPath string
	ManifestHash string
	Profiles     []CodexAgentProfile
}

type codexAgentManifest struct {
	Version float64           `json:"version"`
	Owner   string            `json:"owner,omitempty"`
	Hashes  map[string]string `json:"hashes"`
}

type codexAgentPlan struct {
	CodexAgentProfile
	Content  []byte
	Previous []byte
	Existing bool
	Same     bool
	Owned    bool
}

// CodexAgentPaths returns the existing Codex profile directory and HAWS
// ownership manifest paths for the selected Codex home.
func CodexAgentPaths(codexHome string) (string, string, error) {
	if codexHome == "" {
		codexHome = os.Getenv("CODEX_HOME")
	}
	if codexHome == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", "", err
		}
		codexHome = filepath.Join(home, ".codex")
	}
	absolute, err := filepath.Abs(codexHome)
	if err != nil {
		return "", "", err
	}
	agentsDir := filepath.Join(absolute, "agents")
	return agentsDir, filepath.Join(absolute, "haws-agents.json"), nil
}

// RunCodexAgents creates, checks, or removes the five HAWS Codex agent
// profiles while preserving unrelated and user-edited files.
func RunCodexAgents(command, sourceRoot, codexHome string, dryRun bool) (CodexAgentOperationResult, error) {
	var result CodexAgentOperationResult
	if command == "" {
		command = "check"
	}
	if command != "install" && command != "check" && command != "uninstall" {
		return result, fmt.Errorf("unsupported Codex agent operation %q", command)
	}
	if sourceRoot == "" {
		return result, errors.New("Codex agent profiles need their HAWS source root")
	}
	source, err := filepath.Abs(sourceRoot)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS agent source: %w", err)
	}
	result.AgentsDir, result.ManifestPath, err = CodexAgentPaths(codexHome)
	if err != nil {
		return result, fmt.Errorf("resolve Codex agent paths: %w", err)
	}
	manifest, manifestBytes, manifestExists, err := readCodexAgentManifest(result.ManifestPath)
	if err != nil {
		return result, err
	}
	if manifestExists {
		result.ManifestHash = codexAgentHash(manifestBytes)
	}
	if info, err := os.Lstat(result.AgentsDir); err == nil {
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return result, fmt.Errorf("preserving non-directory or linked agent directory: %s", result.AgentsDir)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return result, err
	}

	plans := make([]codexAgentPlan, 0, len(codexAgentRoles))
	for _, name := range codexAgentRoles {
		rolePath := filepath.Join(source, "agents", name+".md")
		markdown, err := os.ReadFile(rolePath)
		if err != nil {
			return result, err
		}
		description, err := codexAgentDescription(name, string(markdown), rolePath)
		if err != nil {
			return result, err
		}
		content := codexAgentProfileContent(name, description, source, rolePath)
		profilePath := filepath.Join(result.AgentsDir, name+".toml")
		plan := codexAgentPlan{CodexAgentProfile: CodexAgentProfile{
			Name: name, Path: profilePath, Source: rolePath, Hash: codexAgentHash(content),
		}, Content: content}
		info, err := os.Lstat(profilePath)
		if err == nil {
			plan.Existing = true
			if info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 {
				plan.Previous, err = os.ReadFile(profilePath)
				if err != nil {
					return result, err
				}
				plan.Same = bytes.Equal(plan.Previous, content)
				plan.Owned = manifest.Hashes[name] != "" && manifest.Hashes[name] == codexAgentHash(plan.Previous)
			}
		} else if !errors.Is(err, os.ErrNotExist) {
			return result, err
		}
		plans = append(plans, plan)
	}
	result.Profiles = make([]CodexAgentProfile, 0, len(plans))
	for _, plan := range plans {
		profile := plan.CodexAgentProfile
		profile.Managed = plan.Owned
		if command == "install" && (plan.Owned || !plan.Existing) {
			profile.Managed = true
		}
		result.Profiles = append(result.Profiles, profile)
	}

	conflicts := make([]string, 0)
	for _, plan := range plans {
		if plan.Existing && !plan.Same && !plan.Owned {
			conflicts = append(conflicts, plan.Path)
		}
	}
	if len(conflicts) > 0 {
		return result, fmt.Errorf("preserving conflicting or edited profiles: %s", strings.Join(conflicts, ", "))
	}

	switch command {
	case "check":
		missing := make([]string, 0)
		for _, plan := range plans {
			if !plan.Same {
				missing = append(missing, plan.Name)
			}
		}
		if len(missing) > 0 {
			return result, fmt.Errorf("missing Codex profiles: %s", strings.Join(missing, ", "))
		}
		result.Message = "PASS: 5/5 native Codex HAWS profiles match canonical sources."
	case "install":
		pending := make([]codexAgentPlan, 0, len(plans))
		for _, plan := range plans {
			if !plan.Same {
				pending = append(pending, plan)
			}
		}
		if !dryRun && (len(pending) > 0 || !manifestExists) {
			if err := os.MkdirAll(result.AgentsDir, 0o755); err != nil {
				return result, err
			}
			changed := make([]codexAgentPlan, 0, len(pending))
			for _, plan := range pending {
				changed = append(changed, plan)
				if err := writeCodexAgentProfile(plan); err != nil {
					return result, rollbackCodexAgentFiles(changed, err)
				}
			}
			hashes := make(map[string]string)
			for _, plan := range plans {
				if plan.Owned || !plan.Existing {
					hashes[plan.Name] = codexAgentHash(plan.Content)
				}
			}
			manifestContent, err := json.MarshalIndent(codexAgentManifest{Version: 1, Owner: "HAWS", Hashes: hashes}, "", "  ")
			if err == nil {
				manifestContent = append(manifestContent, '\n')
				err = atomicCodexAgentWrite(result.ManifestPath, manifestContent)
			}
			if err != nil {
				return result, rollbackCodexAgentFiles(changed, err)
			}
		}
		if !dryRun {
			data, err := os.ReadFile(result.ManifestPath)
			if err != nil {
				return result, fmt.Errorf("read Codex agent ownership record: %w", err)
			}
			result.ManifestHash = codexAgentHash(data)
		}
		mode := "OK"
		if dryRun {
			mode = "DRY-RUN"
		}
		result.Message = fmt.Sprintf("%s: install %d Codex profiles (%s).", mode, len(pending), result.AgentsDir)
	case "uninstall":
		pending := make([]codexAgentPlan, 0, len(plans))
		for _, plan := range plans {
			if plan.Owned {
				pending = append(pending, plan)
			}
		}
		if !dryRun && (len(pending) > 0 || manifestExists) {
			changed := make([]codexAgentPlan, 0, len(pending))
			for _, plan := range pending {
				latest, err := os.ReadFile(plan.Path)
				if err != nil {
					return result, rollbackCodexAgentFiles(changed, err)
				}
				if !bytes.Equal(latest, plan.Previous) {
					return result, rollbackCodexAgentFiles(changed, fmt.Errorf("Codex profile changed after preview: %s", plan.Path))
				}
				changed = append(changed, plan)
				if err := os.Remove(plan.Path); err != nil {
					return result, rollbackCodexAgentFiles(changed, err)
				}
			}
			if manifestExists {
				if err := os.Remove(result.ManifestPath); err != nil {
					return result, rollbackCodexAgentFiles(changed, err)
				}
			}
		}
		mode := "OK"
		if dryRun {
			mode = "DRY-RUN"
		}
		result.Message = fmt.Sprintf("%s: uninstall %d Codex profiles (%s).", mode, len(pending), result.AgentsDir)
	}
	return result, nil
}

func readCodexAgentManifest(path string) (codexAgentManifest, []byte, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return codexAgentManifest{Version: 1, Hashes: map[string]string{}}, nil, false, nil
	}
	if err != nil {
		return codexAgentManifest{}, nil, false, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return codexAgentManifest{}, nil, false, fmt.Errorf("preserving linked or non-file ownership record: %s", path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return codexAgentManifest{}, nil, false, err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil || fields == nil {
		return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
	}
	for key := range fields {
		if key != "version" && key != "owner" && key != "hashes" {
			return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
		}
	}
	var manifest codexAgentManifest
	if err := json.Unmarshal(data, &manifest); err != nil || manifest.Version != 1 {
		return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
	}
	if raw, ok := fields["owner"]; ok {
		trimmed := bytes.TrimSpace(raw)
		if len(trimmed) == 0 || trimmed[0] != '"' || json.Unmarshal(raw, &manifest.Owner) != nil || manifest.Owner != "HAWS" {
			return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
		}
	}
	rawHashes, ok := fields["hashes"]
	trimmedHashes := bytes.TrimSpace(rawHashes)
	if !ok || len(trimmedHashes) == 0 || trimmedHashes[0] != '{' || manifest.Hashes == nil {
		return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
	}
	for name, hash := range manifest.Hashes {
		if !contains(codexAgentRoles, name) || !codexAgentHashPattern.MatchString(hash) {
			return codexAgentManifest{}, nil, false, fmt.Errorf("unrecognized ownership record: %s", path)
		}
	}
	return manifest, data, true, nil
}

func codexAgentDescription(name, markdown, rolePath string) (string, error) {
	lines := strings.Split(strings.ReplaceAll(markdown, "\r\n", "\n"), "\n")
	if len(lines) < 3 || lines[0] != "---" {
		return "", fmt.Errorf("invalid canonical HAWS role: %s", rolePath)
	}
	closing := -1
	for index := 1; index < len(lines); index++ {
		if lines[index] == "---" {
			closing = index
			break
		}
	}
	if closing < 0 {
		return "", fmt.Errorf("invalid canonical HAWS role: %s", rolePath)
	}
	nameFound := false
	description := ""
	for _, line := range lines[1:closing] {
		if line == "name: "+name {
			nameFound = true
		}
		if description == "" && strings.HasPrefix(line, "description: ") && len(line) > len("description: ") {
			description = strings.TrimSpace(strings.TrimPrefix(line, "description: "))
		}
	}
	if !nameFound {
		return "", fmt.Errorf("invalid canonical HAWS role: %s", rolePath)
	}
	if description == "" {
		return "", fmt.Errorf("missing role description: %s", rolePath)
	}
	return description, nil
}

func codexAgentProfileContent(name, description, source, rolePath string) []byte {
	pathText := func(path string) string { return strings.ReplaceAll(path, `\`, "/") }
	instructions := strings.Join([]string{
		"You are the HAWS " + name + " specialist.",
		"Before acting, read your canonical role: " + pathText(rolePath) + ".",
		"Read applicable standards: " + pathText(filepath.Join(source, "core", "HAWS.md")) + " and " + pathText(filepath.Join(source, "core", "WORK_INSTRUCTIONS.md")) + ".",
		"Read the neutral starter documents under " + pathText(filepath.Join(source, "secondbrain")) + "; keep personal content in a private repository or local copy.",
		"Accept a bounded <task_assignment> from the main agent. Use only the tools actually available in this Codex session; the role YAML is not Codex configuration.",
		"Choose relevant installed skills, open their SKILL.md before using them, and execute their methodology. Use the skill catalog and ~/.agents/skills for discovery.",
		"Return <task_report> with results, command evidence, skills actually used, and [Unverified] limitations. Report questions to the main agent, who communicates with the user.",
		"Follow the canonical role scope. Never push without explicit user authorization. Inherit the parent model, effort, permissions, and available tools.",
	}, "\n")
	content := "# Generated by HAWS codex-agents. Edit canonical agents/*.md instead.\n"
	content += "name = " + codexAgentTOMLString(name) + "\n"
	content += "description = " + codexAgentTOMLString(description) + "\n"
	if name == "researcher" {
		content += "sandbox_mode = \"read-only\"\n"
	}
	content += "developer_instructions = " + codexAgentTOMLString(instructions) + "\n"
	return []byte(content)
}

func codexAgentTOMLString(value string) string {
	var buffer bytes.Buffer
	encoder := json.NewEncoder(&buffer)
	encoder.SetEscapeHTML(false)
	_ = encoder.Encode(value)
	return strings.TrimSuffix(buffer.String(), "\n")
}

func codexAgentHash(content []byte) string {
	hash := sha256.Sum256(content)
	return hex.EncodeToString(hash[:])
}

func writeCodexAgentProfile(plan codexAgentPlan) error {
	flags := os.O_WRONLY
	mode := os.FileMode(0o666)
	if plan.Existing {
		latest, err := os.ReadFile(plan.Path)
		if err != nil {
			return err
		}
		if !bytes.Equal(latest, plan.Previous) {
			return fmt.Errorf("Codex profile changed before install: %s", plan.Path)
		}
		flags |= os.O_TRUNC
	} else {
		flags |= os.O_CREATE | os.O_EXCL
	}
	file, err := os.OpenFile(plan.Path, flags, mode)
	if err != nil {
		return err
	}
	if _, err := file.Write(plan.Content); err != nil {
		_ = file.Close()
		return err
	}
	return file.Close()
}

func rollbackCodexAgentFiles(changed []codexAgentPlan, cause error) error {
	var rollbackErrors []error
	for index := len(changed) - 1; index >= 0; index-- {
		plan := changed[index]
		var err error
		if plan.Existing {
			err = os.WriteFile(plan.Path, plan.Previous, 0o666)
		} else {
			err = os.Remove(plan.Path)
			if errors.Is(err, os.ErrNotExist) {
				err = nil
			}
		}
		if err != nil {
			rollbackErrors = append(rollbackErrors, fmt.Errorf("restore %s: %w", plan.Path, err))
		}
	}
	return errors.Join(append([]error{cause}, rollbackErrors...)...)
}

func atomicCodexAgentWrite(path string, contents []byte) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".haws-agents-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
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
		return err
	}
	return nil
}
