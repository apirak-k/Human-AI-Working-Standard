package uninstall

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/ownership"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

type Plan struct {
	root       string
	currentExe string
	marker     []byte
	hasMarker  bool
	versions   []update.InstalledVersion
	preserved  []string
	base       ownership.Manifest
	baseFiles  []ownership.FileStatus
	hasBase    bool
}

type Summary struct {
	Removed   []string
	Preserved []string
}

func Preview(root, currentExecutable string) (Plan, error) {
	root, err := update.ResolveInstallRoot(root)
	if err != nil {
		return Plan{}, err
	}
	marker, hasMarker, err := update.ActiveMarkerContents(root)
	if err != nil {
		return Plan{}, err
	}
	versions, err := update.InstalledVersions(root)
	if err != nil {
		return Plan{}, err
	}
	plan := Plan{
		root:       root,
		currentExe: currentExecutable,
		marker:     marker,
		hasMarker:  hasMarker,
		versions:   versions,
		preserved:  []string{"HAWS checkout and personal state"},
	}
	manifest, baseFiles, manifestErr := ownership.InspectPackage(root, runtime.GOOS)
	if manifestErr == nil {
		plan.base = manifest
		plan.baseFiles = baseFiles
		plan.hasBase = true
		for _, file := range baseFiles {
			if file.State != "owned" && file.State != "missing" {
				plan.preserved = append(plan.preserved, "base package file "+file.Path+" (modified or unowned)")
			}
		}
	} else {
		plan.preserved = append(plan.preserved, "base package files (ownership manifest unavailable)")
	}

	versionsDir := filepath.Join(root, "versions")
	entries, err := os.ReadDir(versionsDir)
	if errors.Is(err, os.ErrNotExist) {
		return plan, nil
	}
	if err != nil {
		return Plan{}, fmt.Errorf("inspect HAWS versions for uninstall preview: %w", err)
	}
	owned := make(map[string]bool, len(versions))
	for _, version := range versions {
		owned[version.Version] = true
	}
	for _, entry := range entries {
		if entry.IsDir() && owned[entry.Name()] {
			continue
		}
		plan.preserved = append(plan.preserved, filepath.Join("versions", entry.Name())+" (ownership not verified)")
	}
	sort.Strings(plan.preserved)
	return plan, nil
}

func (p Plan) Items() []string {
	items := make([]string, 0, len(p.versions)+len(p.baseFiles)+2)
	if p.hasMarker {
		items = append(items, "active-version marker (return launcher to base package)")
	}
	allBaseFilesOwned := p.hasBase
	for _, file := range p.baseFiles {
		if file.State == "owned" {
			items = append(items, "base package file "+file.Path)
		}
		if file.State != "owned" && file.State != "missing" {
			allBaseFilesOwned = false
		}
	}
	if allBaseFilesOwned {
		items = append(items, "base package ownership manifest")
	}
	for _, version := range p.versions {
		items = append(items, "Go app version "+version.Version)
	}
	return items
}

func (p Plan) Preserved() []string {
	return append([]string(nil), p.preserved...)
}

// Apply revalidates each item after preview. It never recursively removes a
// directory and keeps a version that is currently executing or has changed.
func Apply(p Plan) (Summary, error) {
	result := Summary{Preserved: p.Preserved()}
	if p.root == "" {
		return result, errors.New("HAWS uninstall plan is empty")
	}
	if p.hasMarker {
		if err := update.RemoveActiveMarker(p.root, p.marker); err != nil {
			return result, err
		}
		result.Removed = append(result.Removed, "active-version marker")
	} else {
		current, exists, err := update.ActiveMarkerContents(p.root)
		if err != nil {
			return result, err
		}
		if exists || len(current) != 0 {
			return result, errors.New("active version marker appeared after uninstall preview")
		}
	}

	var failures []error
	for _, version := range p.versions {
		if err := update.RemoveInstalledVersion(p.root, version, p.currentExe); err != nil {
			label := "Go app version " + version.Version
			if errors.Is(err, update.ErrRunningVersion) {
				label += " (kept while the app is running)"
			}
			result.Preserved = append(result.Preserved, label)
			if !errors.Is(err, update.ErrRunningVersion) {
				failures = append(failures, fmt.Errorf("preserve %s: %w", label, err))
			}
			continue
		}
		result.Removed = append(result.Removed, "Go app version "+version.Version)
	}
	if p.hasBase {
		removed, preserved, err := ownership.RemovePackageFiles(p.root, runtime.GOOS, p.base, p.currentExe)
		for _, path := range removed {
			result.Removed = append(result.Removed, "base package file "+path)
		}
		for _, path := range preserved {
			result.Preserved = append(result.Preserved, "base package file "+path)
		}
		if err != nil {
			failures = append(failures, fmt.Errorf("clean owned base package files: %w", err))
		}
	}

	versionsDir := filepath.Join(p.root, "versions")
	if info, statErr := os.Lstat(versionsDir); errors.Is(statErr, os.ErrNotExist) {
		// The versions directory was already absent.
	} else if statErr != nil {
		failures = append(failures, fmt.Errorf("inspect HAWS versions directory after cleanup: %w", statErr))
	} else if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		result.Preserved = append(result.Preserved, "versions path (unowned or reparse point)")
	} else if err := os.Remove(versionsDir); err == nil {
		result.Removed = append(result.Removed, "empty versions directory")
	} else if !errors.Is(err, os.ErrNotExist) {
		result.Preserved = append(result.Preserved, "versions directory contains unowned or active files")
	}
	return result, errors.Join(failures...)
}
