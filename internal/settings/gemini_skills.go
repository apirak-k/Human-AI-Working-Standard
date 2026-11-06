package settings

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// GeminiSkillConfigResult describes the changes made while reconciling
// Antigravity's skills.json file with HAWS's candidate catalog.
type GeminiSkillConfigResult struct {
	Added     int
	Preserved int
	Pruned    int
	Removed   int
}

type GeminiSkillAdoptionResult struct {
	Adopted       int
	LegacyRecords int
}

type geminiJSONField struct {
	name  string
	value json.RawMessage
}

type geminiSkillsRoot struct {
	fields  []geminiJSONField
	entries []json.RawMessage
}

type geminiFileState struct {
	data   []byte
	mode   os.FileMode
	exists bool
}

type geminiSkillsManifest struct {
	Version       float64  `json:"version"`
	Paths         []string `json:"paths"`
	CreatedTarget *bool    `json:"createdTarget,omitempty"`
}

// ApplyGeminiSkillConfig merges desired skill paths into Antigravity's
// skills.json while preserving entries not recorded as HAWS-owned.
func ApplyGeminiSkillConfig(file, manifestFile, candidateFile string, replaceOwned bool) (GeminiSkillConfigResult, error) {
	var result GeminiSkillConfigResult
	root, rootState, err := readGeminiSkillsRoot(file)
	if err != nil {
		return result, err
	}
	manifest, manifestState, err := readGeminiSkillsManifest(manifestFile)
	if err != nil {
		return result, err
	}
	candidate, _, err := readGeminiSkillsRoot(candidateFile)
	if err != nil {
		return result, err
	}
	desiredPaths, err := geminiCandidatePaths(candidate.entries, candidateFile)
	if err != nil {
		return result, err
	}

	preserved := root.entries
	if replaceOwned {
		preserved = nil
	} else {
		preserved = splitGeminiManagedEntries(root.entries, manifest.Paths)
	}
	desiredSet := make(map[string]bool, len(desiredPaths))
	for _, path := range desiredPaths {
		desiredSet[path] = true
	}
	sourceRoot, err := filepath.Abs(filepath.Join(filepath.Dir(manifestFile), "skill-sources"))
	if err != nil {
		return result, err
	}
	kept := make([]json.RawMessage, 0, len(preserved))
	for _, entry := range preserved {
		missing, err := missingGeminiManagedSourceEntry(entry, sourceRoot, desiredSet)
		if err != nil {
			return result, err
		}
		if missing {
			result.Pruned++
			continue
		}
		kept = append(kept, entry)
	}

	existingPathCounts := make(map[string]int)
	for _, entry := range root.entries {
		if path, plain := geminiPlainPathEntry(entry); plain {
			existingPathCounts[path]++
		}
	}
	preservedPaths := make(map[string]bool)
	for _, entry := range kept {
		if path, hasPath := geminiEntryPath(entry); hasPath {
			preservedPaths[path] = true
		}
	}
	nextPaths := make([]string, 0, len(desiredPaths))
	managedEntries := make([]json.RawMessage, 0, len(desiredPaths))
	for _, path := range desiredPaths {
		if preservedPaths[path] {
			continue
		}
		nextPaths = append(nextPaths, path)
		managedEntries = append(managedEntries, geminiManagedPathEntry(path))
		if existingPathCounts[path] == 0 {
			result.Added++
		}
	}
	createdTarget := replaceOwned || manifest.CreatedTarget != nil && *manifest.CreatedTarget ||
		!rootState.exists && len(managedEntries) > 0
	removeCreatedRoot := len(nextPaths) == 0 && createdTarget && len(kept) == 0 && len(root.fields) == 1
	if err := commitGeminiSkills(file, rootState, manifestFile, manifestState,
		root.withEntries(append(kept, managedEntries...)), nextPaths, createdTarget, removeCreatedRoot); err != nil {
		return GeminiSkillConfigResult{}, err
	}
	result.Preserved = len(kept)
	return result, nil
}

// AdoptGeminiSkillOwnership records only exact legacy HAWS entries that are
// still present in the generated catalog, without changing skills.json.
func AdoptGeminiSkillOwnership(file, manifestFile, candidateFile, legacyManifestFile, legacySkillMapFile string) (GeminiSkillAdoptionResult, error) {
	var result GeminiSkillAdoptionResult
	root, _, err := readGeminiSkillsRoot(file)
	if err != nil {
		return result, err
	}
	_, manifestState, err := readGeminiSkillsManifest(manifestFile)
	if err != nil {
		return result, err
	}
	if manifestState.exists {
		return result, errors.New("legacy adoption requires a matching skill map and no current ownership record")
	}
	legacyManifest, err := os.ReadFile(legacyManifestFile)
	if err != nil {
		return result, err
	}
	legacyTargets := parseGeminiLegacyTargets(string(legacyManifest))
	if len(legacyTargets) == 0 {
		return result, nil
	}
	result.LegacyRecords = len(legacyTargets)
	candidate, _, err := readGeminiSkillsRoot(candidateFile)
	if err != nil {
		return result, err
	}
	candidatePaths, err := geminiCandidatePathSet(candidate.entries, candidateFile)
	if err != nil {
		return result, err
	}
	legacySkillMap, err := os.ReadFile(legacySkillMapFile)
	if err != nil {
		return result, err
	}
	eligible := make(map[string]bool)
	for _, line := range strings.Split(strings.ReplaceAll(string(legacySkillMap), "\r\n", "\n"), "\n") {
		if line == "" {
			continue
		}
		tab := strings.IndexByte(line, '\t')
		if tab <= 0 || tab == len(line)-1 {
			return result, fmt.Errorf("invalid legacy skill map in %s", legacySkillMapFile)
		}
		path, target := line[:tab], line[tab+1:]
		if candidatePaths[path] && legacyTargets[target] {
			eligible[path] = true
		}
	}
	counts := make(map[string]int)
	order := make([]string, 0)
	for _, entry := range root.entries {
		path, plain := geminiPlainPathEntry(entry)
		if plain && eligible[path] {
			if counts[path] == 0 {
				order = append(order, path)
			}
			counts[path]++
		}
	}
	adopted := make([]string, 0, len(counts))
	for _, path := range order {
		if counts[path] == 1 {
			adopted = append(adopted, path)
		}
	}
	if len(adopted) == 0 {
		return result, nil
	}
	manifestBytes, err := json.MarshalIndent(geminiSkillsManifest{Version: 1, Paths: adopted, CreatedTarget: boolPointer(false)}, "", "  ")
	if err != nil {
		return result, err
	}
	manifestBytes = append(manifestBytes, '\n')
	if err := atomicGeminiWrite(manifestFile, manifestBytes, 0o600); err != nil {
		return result, err
	}
	result.Adopted = len(adopted)
	return result, nil
}

// VerifyGeminiSkillConfig checks that the skills config and ownership
// manifest remain regular, parseable files in recognized formats.
func VerifyGeminiSkillConfig(file, manifestFile string) error {
	if _, _, err := readGeminiSkillsRoot(file); err != nil {
		return err
	}
	_, _, err := readGeminiSkillsManifest(manifestFile)
	return err
}

// UninstallGeminiSkillConfig removes verified managed entries and leaves
// unrelated Antigravity config entries and properties in place.
func UninstallGeminiSkillConfig(file, manifestFile string) (GeminiSkillConfigResult, error) {
	var result GeminiSkillConfigResult
	root, rootState, err := readGeminiSkillsRoot(file)
	if err != nil {
		return result, err
	}
	manifest, manifestState, err := readGeminiSkillsManifest(manifestFile)
	if err != nil {
		return result, err
	}
	kept := splitGeminiManagedEntries(root.entries, manifest.Paths)
	result.Removed = len(root.entries) - len(kept)
	result.Preserved = len(kept)
	createdTarget := manifest.CreatedTarget != nil && *manifest.CreatedTarget
	removeCreatedRoot := createdTarget && len(kept) == 0 && len(root.fields) == 1
	if err := commitGeminiSkills(file, rootState, manifestFile, manifestState,
		root.withEntries(kept), nil, false, removeCreatedRoot); err != nil {
		return GeminiSkillConfigResult{}, err
	}
	return result, nil
}

func readGeminiSkillsRoot(path string) (geminiSkillsRoot, geminiFileState, error) {
	state, exists, err := readGeminiFile(path)
	if err != nil {
		return geminiSkillsRoot{}, geminiFileState{}, fmt.Errorf("read Gemini skills config %s: %w", path, err)
	}
	if !exists {
		return geminiSkillsRoot{fields: []geminiJSONField{{name: "entries", value: json.RawMessage("[]")}}}, state, nil
	}
	fields, err := decodeGeminiObject(state.data)
	if err != nil {
		return geminiSkillsRoot{}, geminiFileState{}, fmt.Errorf("preserving invalid JSON skills config: %s", path)
	}
	var entriesRaw json.RawMessage
	for _, field := range fields {
		if field.name == "entries" {
			entriesRaw = field.value
			break
		}
	}
	var entries []json.RawMessage
	if len(entriesRaw) == 0 || json.Unmarshal(entriesRaw, &entries) != nil || entries == nil {
		return geminiSkillsRoot{}, geminiFileState{}, fmt.Errorf("preserving unsupported skills config structure: %s", path)
	}
	return geminiSkillsRoot{fields: fields, entries: entries}, state, nil
}

func readGeminiSkillsManifest(path string) (geminiSkillsManifest, geminiFileState, error) {
	state, exists, err := readGeminiFile(path)
	if err != nil {
		return geminiSkillsManifest{}, geminiFileState{}, fmt.Errorf("read Gemini skill ownership record %s: %w", path, err)
	}
	if !exists {
		return geminiSkillsManifest{Version: 1, Paths: []string{}}, state, nil
	}
	var value map[string]json.RawMessage
	if err := json.Unmarshal(state.data, &value); err != nil || value == nil {
		return geminiSkillsManifest{}, geminiFileState{}, fmt.Errorf("preserving invalid JSON ownership record: %s", path)
	}
	var manifest geminiSkillsManifest
	if err := json.Unmarshal(state.data, &manifest); err != nil || manifest.Version != 1 || manifest.Paths == nil {
		return geminiSkillsManifest{}, geminiFileState{}, fmt.Errorf("preserving unrecognized ownership record: %s", path)
	}
	if raw, ok := value["createdTarget"]; ok {
		if string(bytes.TrimSpace(raw)) != "true" && string(bytes.TrimSpace(raw)) != "false" {
			return geminiSkillsManifest{}, geminiFileState{}, fmt.Errorf("preserving unrecognized ownership record: %s", path)
		}
		created := string(bytes.TrimSpace(raw)) == "true"
		manifest.CreatedTarget = &created
	}
	return manifest, state, nil
}

func readGeminiFile(path string) (geminiFileState, bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return geminiFileState{}, false, nil
	}
	if err != nil {
		return geminiFileState{}, false, err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return geminiFileState{}, false, fmt.Errorf("preserving linked or non-file: %s", path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return geminiFileState{}, false, err
	}
	return geminiFileState{data: data, mode: info.Mode().Perm(), exists: true}, true, nil
}

func decodeGeminiObject(data []byte) ([]geminiJSONField, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return nil, errors.New("expected JSON object")
	}
	fields := make([]geminiJSONField, 0)
	indices := make(map[string]int)
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, err
		}
		name, ok := token.(string)
		if !ok {
			return nil, errors.New("expected object key")
		}
		var raw json.RawMessage
		if err := decoder.Decode(&raw); err != nil {
			return nil, err
		}
		if index, exists := indices[name]; exists {
			fields[index].value = raw
		} else {
			indices[name] = len(fields)
			fields = append(fields, geminiJSONField{name: name, value: raw})
		}
	}
	if _, err := decoder.Token(); err != nil {
		return nil, err
	}
	var extra json.RawMessage
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return nil, errors.New("multiple JSON values")
		}
		return nil, err
	}
	return fields, nil
}

func (root geminiSkillsRoot) withEntries(entries []json.RawMessage) geminiSkillsRoot {
	encoded, _ := json.Marshal(entries)
	for index := range root.fields {
		if root.fields[index].name == "entries" {
			root.fields[index].value = encoded
			root.entries = entries
			return root
		}
	}
	root.fields = append(root.fields, geminiJSONField{name: "entries", value: encoded})
	root.entries = entries
	return root
}

func marshalGeminiRoot(root geminiSkillsRoot) []byte {
	var output bytes.Buffer
	output.WriteString("{\n")
	for index, field := range root.fields {
		key, _ := json.Marshal(field.name)
		value := bytes.TrimSpace(field.value)
		var pretty bytes.Buffer
		if json.Indent(&pretty, value, "", "  ") != nil {
			pretty.Write(value)
		}
		lines := bytes.Split(pretty.Bytes(), []byte{'\n'})
		output.WriteString("  ")
		output.Write(key)
		output.WriteString(": ")
		output.Write(lines[0])
		for _, line := range lines[1:] {
			output.WriteByte('\n')
			output.WriteString("  ")
			output.Write(line)
		}
		if index < len(root.fields)-1 {
			output.WriteByte(',')
		}
		output.WriteByte('\n')
	}
	output.WriteString("}\n")
	return output.Bytes()
}

func geminiCandidatePaths(entries []json.RawMessage, file string) ([]string, error) {
	paths, err := geminiCandidatePathSet(entries, file)
	if err != nil {
		return nil, err
	}
	result := make([]string, 0, len(paths))
	seen := make(map[string]bool, len(paths))
	for _, entry := range entries {
		path, ok := geminiEntryPath(entry)
		if ok && !seen[path] {
			seen[path] = true
			result = append(result, path)
		}
	}
	return result, nil
}

func geminiCandidatePathSet(entries []json.RawMessage, file string) (map[string]bool, error) {
	paths := make(map[string]bool, len(entries))
	for _, entry := range entries {
		path, ok := geminiEntryPath(entry)
		if !ok || path == "" {
			return nil, fmt.Errorf("invalid generated skill entry in %s", file)
		}
		paths[path] = true
	}
	return paths, nil
}

func geminiEntryPath(entry json.RawMessage) (string, bool) {
	if len(bytes.TrimSpace(entry)) == 0 || bytes.TrimSpace(entry)[0] != '{' {
		return "", false
	}
	var object map[string]json.RawMessage
	if json.Unmarshal(entry, &object) != nil || object == nil {
		return "", false
	}
	raw, ok := object["path"]
	if !ok || len(bytes.TrimSpace(raw)) == 0 || bytes.TrimSpace(raw)[0] != '"' {
		return "", false
	}
	var path string
	if json.Unmarshal(raw, &path) != nil {
		return "", false
	}
	return path, true
}

func geminiPlainPathEntry(entry json.RawMessage) (string, bool) {
	path, ok := geminiEntryPath(entry)
	if !ok {
		return "", false
	}
	var object map[string]json.RawMessage
	if json.Unmarshal(entry, &object) != nil || len(object) != 1 {
		return "", false
	}
	return path, true
}

func geminiManagedPathEntry(path string) json.RawMessage {
	encoded, _ := json.Marshal(struct {
		Path string `json:"path"`
	}{Path: path})
	return encoded
}

func splitGeminiManagedEntries(entries []json.RawMessage, ownedPaths []string) []json.RawMessage {
	remaining := make(map[string]bool, len(ownedPaths))
	for _, path := range ownedPaths {
		remaining[path] = true
	}
	preserved := make([]json.RawMessage, 0, len(entries))
	for _, entry := range entries {
		path, plain := geminiPlainPathEntry(entry)
		if plain && remaining[path] {
			delete(remaining, path)
			continue
		}
		preserved = append(preserved, entry)
	}
	return preserved
}

func missingGeminiManagedSourceEntry(entry json.RawMessage, sourceRoot string, desired map[string]bool) (bool, error) {
	path, plain := geminiPlainPathEntry(entry)
	if !plain || desired[path] {
		return false, nil
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return false, err
	}
	relative, err := filepath.Rel(sourceRoot, absolute)
	if err != nil || relative == "." || relative == ".." || filepath.IsAbs(relative) || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return false, nil
	}
	info, err := os.Stat(absolute)
	if err == nil && info.IsDir() {
		for _, name := range []string{"SKILL.md", "skill.md"} {
			if _, statErr := os.Stat(filepath.Join(absolute, name)); statErr == nil {
				return false, nil
			} else if !errors.Is(statErr, os.ErrNotExist) && !errors.Is(statErr, syscall.ENOTDIR) {
				return false, statErr
			}
		}
		return true, nil
	}
	if errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOTDIR) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

func parseGeminiLegacyTargets(manifest string) map[string]bool {
	targets := make(map[string]bool)
	for _, line := range strings.Split(strings.ReplaceAll(manifest, "\r\n", "\n"), "\n") {
		if !strings.HasPrefix(line, "skill:") {
			continue
		}
		remainder := line[len("skill:"):]
		if tab := strings.IndexByte(remainder, '\t'); tab >= 0 {
			targets[remainder[tab+1:]] = true
		} else if separator := strings.LastIndex(remainder, "::"); separator >= 0 {
			targets[remainder[separator+2:]] = true
		} else {
			targets[remainder] = true
		}
	}
	return targets
}

func commitGeminiSkills(file string, oldRoot geminiFileState, manifestFile string, oldManifest geminiFileState, nextRoot geminiSkillsRoot, nextPaths []string, createdTarget, removeCreatedRoot bool) error {
	var manifestBytes []byte
	if len(nextPaths) > 0 {
		manifestBytes, _ = json.MarshalIndent(geminiSkillsManifest{Version: 1, Paths: nextPaths, CreatedTarget: boolPointer(createdTarget)}, "", "  ")
		manifestBytes = append(manifestBytes, '\n')
	}
	rootBytes := marshalGeminiRoot(nextRoot)
	tryErr := error(nil)
	if removeCreatedRoot && oldRoot.exists {
		tryErr = os.Remove(file)
	} else if !bytes.Equal(rootBytes, oldRoot.data) && !(!oldRoot.exists && len(nextRoot.entries) == 0) {
		mode := oldRoot.mode.Perm()
		if mode == 0 {
			mode = 0o644
		}
		tryErr = atomicGeminiWrite(file, rootBytes, mode)
	}
	if tryErr == nil {
		if manifestBytes == nil {
			if oldManifest.exists {
				tryErr = os.Remove(manifestFile)
			}
		} else if !bytes.Equal(manifestBytes, oldManifest.data) {
			mode := oldManifest.mode.Perm()
			if mode == 0 {
				mode = 0o600
			}
			tryErr = atomicGeminiWrite(manifestFile, manifestBytes, mode)
		}
	}
	if tryErr == nil {
		return nil
	}
	var rollbackErrs []error
	if err := restoreGeminiFile(file, oldRoot, 0o644); err != nil {
		rollbackErrs = append(rollbackErrs, fmt.Errorf("restore %s: %w", file, err))
	}
	if err := restoreGeminiFile(manifestFile, oldManifest, 0o600); err != nil {
		rollbackErrs = append(rollbackErrs, fmt.Errorf("restore %s: %w", manifestFile, err))
	}
	return errors.Join(append([]error{tryErr}, rollbackErrs...)...)
}

func restoreGeminiFile(path string, previous geminiFileState, defaultMode os.FileMode) error {
	if !previous.exists {
		if _, err := os.Lstat(path); errors.Is(err, os.ErrNotExist) {
			return nil
		} else if err != nil {
			return err
		}
		return os.Remove(path)
	}
	mode := previous.mode.Perm()
	if mode == 0 {
		mode = defaultMode
	}
	return atomicGeminiWrite(path, previous.data, mode)
}

func atomicGeminiWrite(path string, data []byte, mode os.FileMode) error {
	temporary, err := os.CreateTemp(filepath.Dir(path), ".haws-gemini-skills-*.tmp")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(mode); err != nil {
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
		return err
	}
	return nil
}

func boolPointer(value bool) *bool { return &value }
