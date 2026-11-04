package update

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

var ErrRunningVersion = errors.New("installed HAWS version is currently running")

type InstalledVersion struct {
	Version       string
	ArchiveSHA256 string
}

// ActiveMarkerContents returns the validated, app-owned marker bytes. A
// missing marker means the base package is active.
func ActiveMarkerContents(root string) ([]byte, bool, error) {
	root, err := resolveInstallRoot(root)
	if err != nil {
		return nil, false, err
	}
	marker := filepath.Join(root, activeMarkerName)
	info, err := os.Lstat(marker)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, fmt.Errorf("inspect active version marker: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > 512 {
		return nil, false, errors.New("active version marker is not a valid HAWS-owned file")
	}
	contents, err := os.ReadFile(marker)
	if err != nil {
		return nil, false, fmt.Errorf("read active version marker: %w", err)
	}
	if _, err := readActiveState(root); err != nil {
		return nil, false, err
	}
	return contents, true, nil
}

// InstalledVersions returns only versions whose manifest, binaries, and
// directory contents all match the format written by Installer.Install.
func InstalledVersions(root string) ([]InstalledVersion, error) {
	root, err := resolveInstallRoot(root)
	if err != nil {
		return nil, err
	}
	versionsDir := filepath.Join(root, "versions")
	info, err := os.Lstat(versionsDir)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("inspect HAWS versions directory: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return nil, errors.New("HAWS versions path is not a regular directory")
	}
	entries, err := os.ReadDir(versionsDir)
	if err != nil {
		return nil, fmt.Errorf("read HAWS versions directory: %w", err)
	}
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		return nil, err
	}
	versions := make([]InstalledVersion, 0, len(entries))
	for _, entry := range entries {
		if !validInstallVersion(entry.Name()) || !entry.IsDir() {
			continue
		}
		versionDir := filepath.Join(versionsDir, entry.Name())
		versionInfo, err := os.Lstat(versionDir)
		if err != nil || versionInfo.Mode()&os.ModeSymlink != 0 || !versionInfo.IsDir() {
			continue
		}
		manifest, err := readInstallManifest(versionDir, entry.Name(), spec)
		if err != nil || !ownedVersionTreeOnly(versionDir, spec) {
			continue
		}
		versions = append(versions, InstalledVersion{Version: entry.Name(), ArchiveSHA256: manifest.ArchiveSHA256})
	}
	return versions, nil
}

// RemoveActiveMarker removes a marker only if it still matches the validated
// bytes shown during preview.
func RemoveActiveMarker(root string, expected []byte) error {
	root, err := resolveInstallRoot(root)
	if err != nil {
		return err
	}
	marker := filepath.Join(root, activeMarkerName)
	info, err := os.Lstat(marker)
	if err != nil {
		return fmt.Errorf("inspect active version marker before removal: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > 512 {
		return errors.New("refusing to remove an unowned active version marker")
	}
	contents, err := os.ReadFile(marker)
	if err != nil {
		return fmt.Errorf("read active version marker before removal: %w", err)
	}
	if !bytes.Equal(contents, expected) {
		return errors.New("active version marker changed after uninstall preview")
	}
	if _, err := readActiveState(root); err != nil {
		return err
	}
	if err := os.Remove(marker); err != nil {
		return fmt.Errorf("remove HAWS active version marker: %w", err)
	}
	return nil
}

// RemoveInstalledVersion verifies its recorded fingerprints again and removes
// only the two expected binaries and manifest, followed by empty directories.
func RemoveInstalledVersion(root string, version InstalledVersion, currentExecutable string) error {
	if !validInstallVersion(version.Version) || !isSHA256Hex(version.ArchiveSHA256) {
		return errors.New("refusing to remove an invalid HAWS version record")
	}
	root, err := resolveInstallRoot(root)
	if err != nil {
		return err
	}
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		return err
	}
	versionsDir := filepath.Join(root, "versions")
	versionsInfo, err := os.Lstat(versionsDir)
	if err != nil {
		return fmt.Errorf("inspect HAWS versions directory before removal: %w", err)
	}
	if versionsInfo.Mode()&os.ModeSymlink != 0 || !versionsInfo.IsDir() {
		return errors.New("refusing to remove a version through an unowned HAWS versions path")
	}
	versionDir := filepath.Join(versionsDir, version.Version)
	info, err := os.Lstat(versionDir)
	if err != nil {
		return fmt.Errorf("inspect HAWS version before removal: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return errors.New("refusing to remove an unowned HAWS version path")
	}
	manifest, err := readInstallManifest(versionDir, version.Version, spec)
	if err != nil {
		return fmt.Errorf("verify HAWS version before removal: %w", err)
	}
	if manifest.ArchiveSHA256 != version.ArchiveSHA256 || !ownedVersionTreeOnly(versionDir, spec) {
		return errors.New("HAWS version changed after uninstall preview")
	}
	currentPath := canonicalFilePath(currentExecutable)
	for _, arch := range []string{"amd64", "arm64"} {
		binary := binaryPath(versionDir, spec, arch)
		if currentPath != "" && sameFilePath(binary, currentPath) {
			return ErrRunningVersion
		}
	}

	for _, arch := range []string{"amd64", "arm64"} {
		binary := binaryPath(versionDir, spec, arch)
		if err := removeVerifiedRegularFile(binary); err != nil {
			return err
		}
		if err := os.Remove(filepath.Dir(binary)); err != nil {
			return fmt.Errorf("remove empty HAWS architecture directory: %w", err)
		}
	}
	if err := os.Remove(filepath.Join(versionDir, "bin")); err != nil {
		return fmt.Errorf("remove empty HAWS binary directory: %w", err)
	}
	if err := removeVerifiedRegularFile(filepath.Join(versionDir, "install.json")); err != nil {
		return err
	}
	if err := os.Remove(versionDir); err != nil {
		return fmt.Errorf("remove empty HAWS version directory: %w", err)
	}
	return nil
}

func ownedVersionTreeOnly(versionDir string, spec platformSpec) bool {
	entries, err := os.ReadDir(versionDir)
	if err != nil || len(entries) != 2 {
		return false
	}
	seen := make(map[string]bool, len(entries))
	for _, entry := range entries {
		seen[entry.Name()] = true
		info, err := os.Lstat(filepath.Join(versionDir, entry.Name()))
		if err != nil || info.Mode()&os.ModeSymlink != 0 {
			return false
		}
	}
	if !seen["bin"] || !seen["install.json"] {
		return false
	}
	binDir := filepath.Join(versionDir, "bin")
	info, err := os.Lstat(binDir)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return false
	}
	archDirs, err := os.ReadDir(binDir)
	if err != nil || len(archDirs) != 2 {
		return false
	}
	expectedBinary := "haws" + spec.extension
	for _, arch := range []string{"amd64", "arm64"} {
		archName := spec.packageOS + "-" + arch
		var found bool
		for _, archDir := range archDirs {
			if archDir.Name() == archName {
				found = true
				break
			}
		}
		if !found {
			return false
		}
		archPath := filepath.Join(binDir, archName)
		archInfo, err := os.Lstat(archPath)
		if err != nil || archInfo.Mode()&os.ModeSymlink != 0 || !archInfo.IsDir() {
			return false
		}
		files, err := os.ReadDir(archPath)
		if err != nil || len(files) != 1 || files[0].Name() != expectedBinary {
			return false
		}
		binaryInfo, err := os.Lstat(filepath.Join(archPath, expectedBinary))
		if err != nil || binaryInfo.Mode()&os.ModeSymlink != 0 || !binaryInfo.Mode().IsRegular() {
			return false
		}
	}
	return true
}

func removeVerifiedRegularFile(filename string) error {
	info, err := os.Lstat(filename)
	if err != nil {
		return fmt.Errorf("inspect owned HAWS file before removal: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return errors.New("refusing to remove a non-regular or unowned HAWS file")
	}
	if err := os.Remove(filename); err != nil {
		return fmt.Errorf("remove owned HAWS file: %w", err)
	}
	return nil
}

func canonicalFilePath(filename string) string {
	if filename == "" {
		return ""
	}
	abs, err := filepath.Abs(filename)
	if err != nil {
		return ""
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err == nil {
		abs = resolved
	}
	return filepath.Clean(abs)
}

func sameFilePath(left, right string) bool {
	leftPath := canonicalFilePath(left)
	rightPath := canonicalFilePath(right)
	if leftPath == "" || rightPath == "" {
		return false
	}
	if runtime.GOOS == "windows" {
		return strings.EqualFold(leftPath, rightPath)
	}
	return leftPath == rightPath
}
