package settings

import (
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"
)

// WithApplyLock serializes native applies without holding the legacy Sync lock.
// Existing locks are retained for inspection, including locks from interrupted runs.
func (s Store) WithApplyLock(operation func() error) (result error) {
	if operation == nil {
		return errors.New("HAWS Settings apply operation is required")
	}
	dir, err := openStateDir(s.Dir, true)
	if err != nil {
		return err
	}
	defer dir.Close()
	const name = "settings-apply.lock"
	if err := dir.Mkdir(name, 0700); err != nil {
		return fmt.Errorf("HAWS Settings apply is locked (%s); inspect any interrupted apply before removing the lock: %w", name, err)
	}
	owned, err := dir.Lstat(name)
	if err != nil {
		return err
	}
	if !owned.IsDir() || owned.Mode()&os.ModeSymlink != 0 {
		return errors.New("HAWS Settings apply lock changed during creation")
	}
	var lock *os.Root
	verified := false
	defer func() {
		if lock != nil {
			if verified {
				for _, entry := range []string{"pid", "timestamp"} {
					if err := lock.Remove(entry); err != nil && !errors.Is(err, os.ErrNotExist) {
						result = errors.Join(result, fmt.Errorf("clean HAWS Settings apply lock: %w", err))
					}
				}
			}
			result = errors.Join(result, lock.Close())
		}
		current, err := dir.Lstat(name)
		if errors.Is(err, os.ErrNotExist) {
			return
		}
		if err != nil {
			result = errors.Join(result, err)
			return
		}
		if !os.SameFile(owned, current) || !current.IsDir() || current.Mode()&os.ModeSymlink != 0 {
			result = errors.Join(result, errors.New("HAWS Settings apply lock was replaced; foreign lock retained"))
			return
		}
		if err := dir.Remove(name); err != nil {
			result = errors.Join(result, fmt.Errorf("release HAWS Settings apply lock: %w", err))
		}
	}()
	lock, err = dir.OpenRoot(name)
	if err != nil {
		return err
	}
	opened, statErr := lock.Stat(".")
	after, afterErr := dir.Lstat(name)
	if statErr != nil || afterErr != nil || !os.SameFile(owned, opened) || !os.SameFile(owned, after) || after.Mode()&os.ModeSymlink != 0 {
		return errors.New("HAWS Settings apply lock changed while opening")
	}
	verified = true
	for entry, value := range map[string]string{"pid": strconv.Itoa(os.Getpid()), "timestamp": strconv.FormatInt(time.Now().Unix(), 10)} {
		file, err := lock.OpenFile(entry, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return err
		}
		_, writeErr := io.WriteString(file, value+"\n")
		if err := errors.Join(writeErr, file.Close()); err != nil {
			return err
		}
	}
	return operation()
}

// ValidateLoaded detects external edits before the coordinator writes its journal.
// It reads through guarded directory handles and never creates state directories.
func (s Store) ValidateLoaded(state State) error {
	for path, before := range state.loaded {
		after, err := readStateFile(path)
		if err != nil {
			return err
		}
		if before.exists != after.exists || before.data != after.data {
			return errors.New("HAWS settings changed since this draft was loaded; reload before applying")
		}
	}
	return nil
}
