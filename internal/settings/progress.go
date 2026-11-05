package settings

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

func (s Store) ReadProgress() (plan, result string, err error) {
	p, err := readStateFile(s.Path("settings.plan"))
	if err != nil {
		return "", "", err
	}
	r, err := readStateFile(s.Path("apply.result"))
	if err != nil {
		return "", "", err
	}
	return p.data, r.data, nil
}

// WriteProgress records the approved plan and its current result together.
// Progress alone never establishes that installation has completed.
func (s Store) WriteProgress(plan, result string) error {
	for _, data := range []string{plan, result} {
		if len(data) > maxStateBytes || strings.ContainsRune(data, 0) {
			return errors.New("HAWS progress exceeds the size limit or contains a NUL byte")
		}
	}
	return s.withProgressLock(func(_ *os.Root) error {
		return replaceStateFiles([]replacement{{path: s.Path("settings.plan"), data: plan}, {path: s.Path("apply.result"), data: result}})
	})
}

// CompleteIntegration records successful Sync without completing other apply
// actions or claiming that installation itself has finished.
func (s Store) CompleteIntegration() (bool, error) {
	changed := false
	err := s.withProgressLock(func(_ *os.Root) error {
		progress, err := readStateFile(s.Path("apply.result"))
		if err != nil {
			return err
		}
		lines := strings.Split(progress.data, "\n")
		for _, line := range lines {
			kind, status, ok := strings.Cut(strings.TrimSuffix(line, "\r"), "\t")
			if ok && kind != "integration" && status == "pending" {
				return errors.New("component Sync completed, but Settings still has unfinished actions; reopen Settings to recover")
			}
		}
		for index, line := range lines {
			if strings.TrimSuffix(line, "\r") == "integration\tpending" {
				lines[index] = strings.Replace(line, "\tpending", "\tcompleted", 1)
				changed = true
			}
		}
		if !changed {
			return nil
		}
		return replaceStateFiles([]replacement{{path: s.Path("apply.result"), data: strings.Join(lines, "\n")}})
	})
	return changed && err == nil, err
}

// CompleteInstall must be called only after successful integration and verified
// apply actions. Pending or missing progress cannot become an installed state.
func (s Store) CompleteInstall() error {
	return s.withProgressLock(func(dir *os.Root) error {
		progress, err := readStateFile(s.Path("apply.result"))
		if err != nil {
			return err
		}
		if !progress.exists || progress.data == "" {
			return errors.New("HAWS installation has no completed apply result")
		}
		for _, line := range strings.Split(strings.TrimSuffix(progress.data, "\n"), "\n") {
			fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
			if len(fields) != 2 || fields[0] == "" || fields[1] != "completed" {
				return errors.New("HAWS installation has an incomplete apply step")
			}
		}
		uninstalled, err := readStateFile(s.Path("uninstalled"))
		if err != nil {
			return err
		}
		installed, err := s.InstallComplete()
		if err != nil {
			return err
		}
		migrationPath := s.Path("integration-ownership-migration-v1")
		migration, err := readStateFile(migrationPath)
		if err != nil {
			return err
		}
		if migration.exists && !validProgressMarker(migration.data, "migrated_at") {
			return errors.New("HAWS integration ownership migration marker is invalid")
		}
		stamp := time.Now().UTC().Format("2006-01-02T15:04:05Z")
		files := []replacement{{path: s.Path("install.complete"), data: "schema=1\tcompleted_at=" + stamp + "\n"}}
		if !installed && !migration.exists {
			files = append(files, replacement{path: migrationPath, data: "schema=1\tmigrated_at=" + stamp + "\n"})
		}
		if err := replaceStateFiles(files); err != nil {
			return err
		}
		if uninstalled.exists {
			latest, err := readStateFile(s.Path("uninstalled"))
			if err != nil {
				return err
			}
			if latest.exists != uninstalled.exists || latest.data != uninstalled.data {
				return errors.New("HAWS uninstall marker changed during completion")
			}
			if err := dir.Remove("uninstalled"); err != nil {
				return fmt.Errorf("clear HAWS uninstall marker: %w", err)
			}
		}
		return nil
	})
}

func (s Store) InstallComplete() (bool, error) {
	uninstalled, err := readStateFile(s.Path("uninstalled"))
	if err != nil {
		return false, err
	}
	if uninstalled.exists && uninstalled.data != "" {
		return false, nil
	}
	installed, err := readStateFile(s.Path("install.complete"))
	if err != nil {
		return false, err
	}
	if !installed.exists || installed.data == "" {
		return false, nil
	}
	if !validProgressMarker(installed.data, "completed_at") {
		return false, errors.New("HAWS installation marker is invalid")
	}
	return true, nil
}

func validProgressMarker(data, key string) bool {
	fields := strings.Split(strings.TrimSuffix(data, "\n"), "\t")
	if len(fields) != 2 || fields[0] != "schema=1" || !strings.HasPrefix(fields[1], key+"=") {
		return false
	}
	stamp := strings.TrimPrefix(fields[1], key+"=")
	parsed, err := time.Parse("2006-01-02T15:04:05Z", stamp)
	return err == nil && parsed.Format("2006-01-02T15:04:05Z") == stamp
}

func (s Store) withProgressLock(operation func(*os.Root) error) error {
	dir, err := openStateDir(s.Dir, true)
	if err != nil {
		return err
	}
	defer dir.Close()
	if err := dir.Mkdir("sync.lock", 0700); err != nil {
		return fmt.Errorf("HAWS progress is locked (sync.lock): %w", err)
	}
	lock, err := openStateDir(s.Path("sync.lock"), false)
	if err != nil {
		_ = dir.Remove("sync.lock")
		return err
	}
	defer func() {
		_ = lock.Remove("pid")
		_ = lock.Remove("timestamp")
		_ = lock.Close()
		_ = dir.Remove("sync.lock")
	}()
	for name, value := range map[string]string{"pid": strconv.Itoa(os.Getpid()), "timestamp": strconv.FormatInt(time.Now().Unix(), 10)} {
		file, err := lock.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		_, writeErr := io.WriteString(file, value+"\n")
		if err := errors.Join(writeErr, file.Close()); err != nil {
			return err
		}
	}
	return operation(dir)
}
