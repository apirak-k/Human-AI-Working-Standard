package settings

import (
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
)

const maxStateBytes = 1 << 20

type Config struct {
	AutoUpdateSkills bool
	AutoUpdateBrain  bool
}

func DefaultConfig() Config { return Config{AutoUpdateSkills: true, AutoUpdateBrain: true} }

type State struct {
	Config               Config
	DisabledEnvironments []string
	DisabledSkills       []string
	loaded               map[string]fileState
}

type Store struct {
	Root string
	Dir  string
}

func NewStore(root string) Store {
	if absolute, err := filepath.Abs(root); err == nil {
		root = absolute
	}
	originalRoot := root
	// Resolve the trusted checkout once, including macOS's /var temp alias.
	if resolved, err := filepath.EvalSymlinks(root); err == nil {
		root = resolved
	}
	dir := os.Getenv("HAWS_STATE_DIR")
	if dir == "" {
		dir = filepath.Join(root, ".haws", "state")
	} else if !filepath.IsAbs(dir) {
		dir = filepath.Join(root, dir)
	} else if relative, err := filepath.Rel(originalRoot, dir); err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative) {
		dir = filepath.Join(root, relative)
	}
	return Store{Root: root, Dir: filepath.Clean(dir)}
}

func (s Store) Path(name string) string { return filepath.Join(s.Dir, name) }

type fileState struct {
	data   string
	exists bool
	mode   os.FileMode
}

func (s Store) Load() (State, error) {
	state := State{Config: DefaultConfig(), loaded: make(map[string]fileState)}
	read := func(path string) (fileState, error) {
		file, err := readStateFile(path)
		if err == nil {
			state.loaded[path] = file
		}
		return file, err
	}
	file, err := read(s.Path("settings.tsv"))
	if err != nil {
		return State{}, err
	}
	if err := parseConfig(file.data, &state.Config); err != nil {
		return State{}, err
	}
	_, file, err = firstFile(s.environmentCandidates(), read)
	if err != nil {
		return State{}, err
	}
	state.DisabledEnvironments = parseList(file.data, true)
	_, file, err = firstFile(s.skillCandidates(), read)
	if err != nil {
		return State{}, err
	}
	state.DisabledSkills = parseList(file.data, false)
	return state, nil
}

func (s Store) environmentCandidates() []string {
	if os.Getenv("HAWS_PACKAGE_DIR") != "" && os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE") != "" {
		path := os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE")
		if !filepath.IsAbs(path) {
			path = filepath.Join(s.Root, path)
		}
		return []string{path}
	}
	return []string{filepath.Join(s.Root, "ai-configs", "environments.disabled"), filepath.Join(s.Root, "config", "environments.disabled"), filepath.Join(s.Root, "environments.disabled")}
}

func (s Store) skillCandidates() []string {
	return []string{s.Path("skills.disabled"), filepath.Join(s.Root, "skills", "skills.disabled"), filepath.Join(s.Root, "skills.disabled"), filepath.Join(s.Root, "config", "skills.disabled")}
}

func firstFile(paths []string, read func(string) (fileState, error)) (string, fileState, error) {
	for _, path := range paths {
		file, err := read(path)
		if err != nil {
			return "", fileState{}, err
		}
		if file.exists {
			return path, file, nil
		}
	}
	return paths[0], fileState{}, nil
}

func parseConfig(data string, config *Config) error {
	skillsExplicit := false
	for index, line := range strings.Split(data, "\n") {
		line = strings.TrimSuffix(line, "\r")
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) != 2 {
			return fmt.Errorf("HAWS settings line %d is invalid", index+1)
		}
		key, value := fields[0], fields[1]
		valid := value == "on" || value == "off"
		switch key {
		case "schema_version":
			valid = value == "1"
		case "second_brain", "second_brain_enabled":
		case "second_brain_remote":
			valid = validRemote(value)
		case "auto_update":
			if !skillsExplicit {
				config.AutoUpdateSkills = value == "on"
			}
		case "auto_update_skills":
			config.AutoUpdateSkills = value == "on"
			skillsExplicit = true
		case "auto_update_brain":
			config.AutoUpdateBrain = value == "on"
		default:
			valid = false
		}
		if !valid {
			return fmt.Errorf("HAWS settings line %d is invalid", index+1)
		}
	}
	return nil
}

func validRemote(value string) bool {
	if value == "" {
		return true
	}
	if strings.HasPrefix(value, "-") {
		return false
	}
	for _, char := range value {
		if unicode.IsControl(char) {
			return false
		}
	}
	if strings.HasPrefix(value, "git@") {
		rest := strings.TrimPrefix(value, "git@")
		colon := strings.IndexByte(rest, ':')
		if colon > 0 && colon < len(rest)-1 {
			return true
		}
	}
	separator := strings.Index(value, "://")
	return separator > 0 && separator+3 < len(value)
}

func parseList(data string, environments bool) []string {
	seen := make(map[string]bool)
	for _, line := range strings.Split(data, "\n") {
		line, _, _ = strings.Cut(line, "#")
		line = strings.TrimSpace(line)
		if line == "" || environments && !validEnvironment(line) {
			continue
		}
		seen[line] = true
	}
	var result []string
	for value := range seen {
		result = append(result, value)
	}
	sort.Strings(result)
	return result
}

func validEnvironment(value string) bool {
	return value == "claude" || value == "codex" || value == "gemini"
}

func listData(values []string, environments bool) (string, error) {
	seen := make(map[string]bool)
	for _, value := range values {
		if value == "" || strings.TrimSpace(value) != value || strings.Contains(value, "#") || environments && !validEnvironment(value) {
			return "", fmt.Errorf("invalid disabled entry %q", value)
		}
		for _, char := range value {
			if unicode.IsControl(char) {
				return "", errors.New("disabled entry contains a control character")
			}
		}
		seen[value] = true
	}
	var sorted []string
	for value := range seen {
		sorted = append(sorted, value)
	}
	sort.Strings(sorted)
	header := "# HAWS Disabled Skills (source-aware)\n"
	if environments {
		header = "# HAWS Disabled AI Environments\n"
	}
	if len(sorted) > 0 {
		header += strings.Join(sorted, "\n") + "\n"
	}
	if len(header) > maxStateBytes {
		return "", errors.New("disabled list exceeds size limit")
	}
	return header, nil
}

// Save commits the three compatible files under the legacy Sync lock. A state
// returned by Load also guards against edits made since the draft was opened.
func (s Store) Save(state State) error {
	environments, err := listData(state.DisabledEnvironments, true)
	if err != nil {
		return err
	}
	skills, err := listData(state.DisabledSkills, false)
	if err != nil {
		return err
	}
	dir, err := openStateDir(s.Dir, true)
	if err != nil {
		return err
	}
	defer dir.Close()
	if err := dir.Mkdir("sync.lock", 0700); err != nil {
		return fmt.Errorf("HAWS settings are locked (sync.lock): %w", err)
	}
	defer func() {
		_ = dir.Remove("sync.lock/pid")
		_ = dir.Remove("sync.lock/timestamp")
		_ = dir.Remove("sync.lock")
	}()
	for name, value := range map[string]string{"pid": strconv.Itoa(os.Getpid()), "timestamp": strconv.FormatInt(time.Now().Unix(), 10)} {
		file, err := dir.OpenFile("sync.lock/"+name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		_, writeErr := io.WriteString(file, value+"\n")
		closeErr := file.Close()
		if err := errors.Join(writeErr, closeErr); err != nil {
			return err
		}
	}
	current, err := s.Load()
	if err != nil {
		return err
	}
	for path, before := range state.loaded {
		after, err := readStateFile(path)
		if err != nil {
			return err
		}
		if before.exists != after.exists || before.data != after.data {
			return errors.New("HAWS settings changed since this draft was loaded; reload before saving")
		}
	}
	environmentPath, environmentFile, err := firstFile(s.environmentCandidates(), func(path string) (fileState, error) { return current.loaded[path], nil })
	if err != nil {
		return err
	}
	toggle := func(enabled bool) string {
		if enabled {
			return "on"
		}
		return "off"
	}
	config := "schema_version\t1\nauto_update_skills\t" + toggle(state.Config.AutoUpdateSkills) + "\nauto_update_brain\t" + toggle(state.Config.AutoUpdateBrain) + "\nauto_update\t" + toggle(state.Config.AutoUpdateSkills) + "\n"
	files := []replacement{{path: s.Path("settings.tsv"), data: config}}
	if !current.loaded[s.Path("skills.disabled")].exists || strings.Join(parseList(skills, false), "\n") != strings.Join(current.DisabledSkills, "\n") {
		files = append(files, replacement{path: s.Path("skills.disabled"), data: skills})
	}
	if !environmentFile.exists || strings.Join(parseList(environments, true), "\n") != strings.Join(current.DisabledEnvironments, "\n") {
		files = append(files, replacement{path: environmentPath, data: environments})
	}
	return replaceStateFiles(files)
}

type replacement struct {
	path, data          string
	parent              *os.Root
	name, stage, backup string
	before              fileState
}

func replaceStateFiles(files []replacement) error {
	defer func() {
		for _, file := range files {
			if file.parent != nil {
				if file.stage != "" {
					_ = file.parent.Remove(file.stage)
				}
				if file.backup != "" {
					_ = file.parent.Remove(file.backup)
				}
				_ = file.parent.Close()
			}
		}
	}()
	seen := make(map[string]bool)
	for i := range files {
		file := &files[i]
		if seen[file.path] {
			return errors.New("HAWS settings destinations overlap")
		}
		seen[file.path] = true
		var err error
		file.before, err = readStateFile(file.path)
		if err != nil {
			return err
		}
		file.parent, err = openStateDir(filepath.Dir(file.path), true)
		if err != nil {
			return err
		}
		file.name = filepath.Base(file.path)
		mode := os.FileMode(0600)
		if file.before.exists {
			mode = file.before.mode.Perm()
		}
		file.stage, err = stageStateFile(file.parent, file.data, mode)
		if err != nil {
			return err
		}
		if file.before.exists {
			file.backup, err = stageStateFile(file.parent, file.before.data, mode)
			if err != nil {
				return err
			}
		}
	}
	return commitStateFiles(files)
}

func commitStateFiles(files []replacement) error {
	for i := range files {
		file := &files[i]
		latest, err := readStateFile(file.path)
		if err == nil && (latest.exists != file.before.exists || latest.data != file.before.data) {
			err = errors.New("HAWS settings destination changed during save")
		}
		if err == nil {
			err = file.parent.Rename(file.stage, file.name)
		}
		if err != nil {
			var rollback []error
			for j := i - 1; j >= 0; j-- {
				previous := &files[j]
				var restoreErr error
				if previous.before.exists {
					restoreErr = previous.parent.Rename(previous.backup, previous.name)
				} else {
					restoreErr = previous.parent.Remove(previous.name)
				}
				if restoreErr != nil {
					recovery := filepath.Join(filepath.Dir(previous.path), previous.backup)
					rollback = append(rollback, fmt.Errorf("restore %s (backup retained at %s): %w", previous.path, recovery, restoreErr))
					previous.backup = ""
				}
			}
			return errors.Join(append([]error{fmt.Errorf("save %s: %w", file.path, err)}, rollback...)...)
		}
	}
	return nil
}

func stageStateFile(parent *os.Root, data string, mode os.FileMode) (string, error) {
	name := fmt.Sprintf(".haws-settings-%x", randomStateName())
	file, err := parent.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return "", err
	}
	_, writeErr := io.WriteString(file, data)
	syncErr := file.Sync()
	closeErr := file.Close()
	if err := errors.Join(writeErr, syncErr, closeErr); err != nil {
		_ = parent.Remove(name)
		return "", err
	}
	return name, nil
}

func randomStateName() []byte { bytes := make([]byte, 16); _, _ = rand.Read(bytes); return bytes }

func readStateFile(path string) (fileState, error) {
	parent, err := openStateDir(filepath.Dir(path), false)
	if errors.Is(err, os.ErrNotExist) {
		return fileState{}, nil
	}
	if err != nil {
		return fileState{}, err
	}
	defer parent.Close()
	name := filepath.Base(path)
	info, err := parent.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		return fileState{}, nil
	}
	if err != nil {
		return fileState{}, err
	}
	if !info.Mode().IsRegular() || info.Size() > maxStateBytes {
		return fileState{}, fmt.Errorf("HAWS state %s is not a bounded regular file", path)
	}
	file, err := parent.Open(name)
	if err != nil {
		return fileState{}, err
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil {
		return fileState{}, err
	}
	if !os.SameFile(info, opened) {
		return fileState{}, errors.New("HAWS state file changed while opening")
	}
	data, err := io.ReadAll(io.LimitReader(file, maxStateBytes+1))
	if err != nil {
		return fileState{}, err
	}
	if len(data) > maxStateBytes {
		return fileState{}, errors.New("HAWS state file exceeds size limit")
	}
	return fileState{data: string(data), exists: true, mode: info.Mode()}, nil
}

// Directory handles keep subsequent reads and renames inside the inspected
// directories even if another process replaces a parent pathname.
func openStateDir(path string, create bool) (*os.Root, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	volume := filepath.VolumeName(absolute)
	parent, err := os.OpenRoot(volume + string(filepath.Separator))
	if err != nil {
		return nil, err
	}
	relative := strings.TrimPrefix(strings.TrimPrefix(absolute, volume), string(filepath.Separator))
	for _, part := range strings.Split(relative, string(filepath.Separator)) {
		if part == "" {
			continue
		}
		info, err := parent.Lstat(part)
		if errors.Is(err, os.ErrNotExist) && create {
			err = parent.Mkdir(part, 0700)
			if err == nil || errors.Is(err, os.ErrExist) {
				info, err = parent.Lstat(part)
			}
		}
		if err != nil {
			parent.Close()
			return nil, err
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			parent.Close()
			return nil, fmt.Errorf("unsafe HAWS state directory %s", path)
		}
		child, err := parent.OpenRoot(part)
		if err != nil {
			parent.Close()
			return nil, err
		}
		opened, statErr := child.Stat(".")
		after, afterErr := parent.Lstat(part)
		parent.Close()
		if statErr != nil || afterErr != nil || !os.SameFile(info, opened) || !os.SameFile(info, after) || after.Mode()&os.ModeSymlink != 0 {
			child.Close()
			return nil, errors.New("HAWS state directory changed while opening")
		}
		parent = child
	}
	return parent, nil
}
