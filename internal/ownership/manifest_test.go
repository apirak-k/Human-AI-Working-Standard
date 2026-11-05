package ownership

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func makePackage(t *testing.T, root string) Manifest {
	t.Helper()
	platform, launcher, extension, err := packagePlatform(runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	files := map[string][]byte{
		"README.txt": []byte("package help"),
		launcher:     []byte("launcher"),
		"bin/" + platform + "-amd64/haws" + extension: []byte("amd64 binary"),
		"bin/" + platform + "-arm64/haws" + extension: []byte("arm64 binary"),
	}
	manifest := Manifest{SchemaVersion: manifestSchema, Version: "v1.2.3", Platform: platform, Files: make(map[string]string, len(files))}
	for relative, contents := range files {
		filename := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, contents, 0o755); err != nil {
			t.Fatal(err)
		}
		hash := sha256.Sum256(contents)
		manifest.Files[relative] = hex.EncodeToString(hash[:])
	}
	writeManifest(t, root, manifest)
	return readFixtureManifest(t, root)
}

func writeManifest(t *testing.T, root string, manifest Manifest) {
	t.Helper()
	contents, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ManifestName), contents, 0o600); err != nil {
		t.Fatal(err)
	}
}

func readFixtureManifest(t *testing.T, root string) Manifest {
	t.Helper()
	manifest, err := ReadManifest(root, runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	return manifest
}

func TestInspectPackageVerifiesManifestAndFileFingerprints(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	got, statuses, err := InspectPackage(root, runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	if !sameManifest(got, manifest) || len(statuses) != 4 {
		t.Fatalf("manifest/status count = %#v / %d", got, len(statuses))
	}
	for _, status := range statuses {
		if status.State != "owned" {
			t.Fatalf("file %s state = %s", status.Path, status.State)
		}
	}

	if err := os.WriteFile(filepath.Join(root, "README.txt"), []byte("user edit"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, statuses, err = InspectPackage(root, runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	for _, status := range statuses {
		if status.Path == "README.txt" && status.State != "changed" {
			t.Fatalf("modified README state = %s", status.State)
		}
	}
}

func TestRemovePackageFilesDeletesOnlyUnchangedOwnedFiles(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	_, launcher, _, _ := packagePlatform(runtime.GOOS)
	if err := os.WriteFile(filepath.Join(root, launcher), []byte("user-modified launcher"), 0o600); err != nil {
		t.Fatal(err)
	}
	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err != nil {
		t.Fatal(err)
	}
	if !contains(preserved, launcher) || !contains(preserved, ManifestName+" (kept for remaining package files)") {
		t.Fatalf("preserved = %v", preserved)
	}
	for _, path := range removed {
		if path == launcher || path == ManifestName {
			t.Fatalf("modified launcher or its manifest was removed: %v", removed)
		}
	}
	if _, err := os.Stat(filepath.Join(root, launcher)); err != nil {
		t.Fatalf("modified launcher was deleted: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, ManifestName)); err != nil {
		t.Fatalf("manifest was deleted while modified files remain: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "README.txt")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("unchanged README remains: %v", err)
	}
}

func TestRemovePackageFilesPreservesCurrentlyRunningBaseBinary(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	platform, _, extension, _ := packagePlatform(runtime.GOOS)
	current := filepath.Join(root, "bin", platform+"-"+runtime.GOARCH, "haws"+extension)
	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, current)
	if !errors.Is(err, ErrRunningPackage) {
		t.Fatalf("RemovePackageFiles() error = %v, want ErrRunningPackage", err)
	}
	if len(removed) != 0 || len(preserved) == 0 {
		t.Fatalf("running package removal = removed %v, preserved %v", removed, preserved)
	}
	if _, err := os.Stat(current); err != nil {
		t.Fatalf("running binary was removed: %v", err)
	}
}

func TestRemovePackageFilesReportsPermissionFailures(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows does not enforce Unix directory write bits")
	}
	root := t.TempDir()
	manifest := makePackage(t, root)
	platform, _, _, _ := packagePlatform(runtime.GOOS)
	archDirectory := filepath.Join(root, "bin", platform+"-amd64")
	if err := os.Chmod(archDirectory, 0o500); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Chmod(archDirectory, 0o700) }()

	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err == nil {
		t.Fatalf("RemovePackageFiles() returned nil error; removed=%v preserved=%v", removed, preserved)
	}
	if len(preserved) == 0 {
		t.Fatalf("permission failure was not reported: removed=%v", removed)
	}
}

func TestRemovePackageFilesRemovesEmptyOwnedRuntimeDirectories(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	runtimeFile := "runtime/core/HAWS.md"
	runtimeContents := []byte("HAWS runtime fixture")
	runtimePath := filepath.Join(root, filepath.FromSlash(runtimeFile))
	if err := os.MkdirAll(filepath.Dir(runtimePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(runtimePath, runtimeContents, 0o600); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(runtimeContents)
	manifest.Files[runtimeFile] = hex.EncodeToString(hash[:])
	writeManifest(t, root, manifest)
	manifest = readFixtureManifest(t, root)

	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err != nil {
		t.Fatal(err)
	}
	if !contains(removed, runtimeFile) {
		t.Fatalf("runtime file not listed as removed: %v", removed)
	}
	if len(preserved) != 0 {
		t.Fatalf("unexpected preserved paths: %v", preserved)
	}
	for _, directory := range []string{"runtime/core", "runtime"} {
		if _, err := os.Lstat(filepath.Join(root, filepath.FromSlash(directory))); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("empty owned directory %s remains: %v", directory, err)
		}
	}
}

func TestRemovePackageFilesPreservesUnownedRuntimeAndDataContent(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	runtimeFile := "runtime/core/HAWS.md"
	runtimeContents := []byte("HAWS runtime fixture")
	runtimePath := filepath.Join(root, filepath.FromSlash(runtimeFile))
	if err := os.MkdirAll(filepath.Dir(runtimePath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(runtimePath, runtimeContents, 0o600); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(runtimeContents)
	manifest.Files[runtimeFile] = hex.EncodeToString(hash[:])
	writeManifest(t, root, manifest)
	manifest = readFixtureManifest(t, root)
	if err := os.WriteFile(filepath.Join(root, "runtime", "core", "personal-note.md"), []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	personal := filepath.Join(root, "data", "secondbrain", "WORKFLOW.md")
	if err := os.MkdirAll(filepath.Dir(personal), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(personal, []byte("personal brain"), 0o600); err != nil {
		t.Fatal(err)
	}

	_, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err != nil {
		t.Fatal(err)
	}
	if !contains(preserved, "runtime/core (contains unowned files)") {
		t.Fatalf("unowned runtime content was not reported: %v", preserved)
	}
	if got, err := os.ReadFile(filepath.Join(root, "runtime", "core", "personal-note.md")); err != nil || string(got) != "keep" {
		t.Fatalf("unowned runtime file = %q, %v", got, err)
	}
	if got, err := os.ReadFile(personal); err != nil || string(got) != "personal brain" {
		t.Fatalf("personal data = %q, %v", got, err)
	}
}

func TestRemovePackageFilesDoesNotTraverseSymlinkedRuntimeAncestor(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	external := t.TempDir()
	if err := os.Mkdir(filepath.Join(external, "core"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, filepath.Join(root, "runtime")); err != nil {
		t.Skipf("creating directory symlink is unavailable: %v", err)
	}
	runtimeFile := "runtime/core/HAWS.md"
	hash := sha256.Sum256([]byte("fixture runtime"))
	manifest.Files[runtimeFile] = hex.EncodeToString(hash[:])
	writeManifest(t, root, manifest)
	manifest = readFixtureManifest(t, root)

	_, _, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err != nil {
		t.Fatal(err)
	}
	if info, err := os.Lstat(filepath.Join(external, "core")); err != nil || !info.IsDir() {
		t.Fatalf("external directory beneath symlink was removed: info=%v err=%v", info, err)
	}
	if info, err := os.Lstat(filepath.Join(root, "runtime")); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("package symlink was changed: info=%v err=%v", info, err)
	}
}

func TestRemoveEmptyPackageDirectoryRechecksSwappedAncestorBeforeRemoval(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "runtime", "core"), 0o755); err != nil {
		t.Fatal(err)
	}
	external := t.TempDir()
	if err := os.Mkdir(filepath.Join(external, "core"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, filepath.Join(root, "runtime-link")); err != nil {
		t.Skipf("creating directory symlink is unavailable: %v", err)
	}
	if err := os.Remove(filepath.Join(root, "runtime-link")); err != nil {
		t.Fatal(err)
	}

	removed, reason, err := removeEmptyPackageDirectoryWithHook(root, "runtime/core", func() {
		if err := os.Rename(filepath.Join(root, "runtime"), filepath.Join(root, "runtime-original")); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(external, filepath.Join(root, "runtime")); err != nil {
			t.Fatal(err)
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	if removed || reason != "symlinked or unowned parent" {
		t.Fatalf("remove result = %t, %q; want preserved symlinked parent", removed, reason)
	}
	for _, directory := range []string{
		filepath.Join(root, "runtime-original", "core"),
		filepath.Join(external, "core"),
	} {
		if info, err := os.Lstat(directory); err != nil || !info.IsDir() {
			t.Fatalf("directory %s was removed or changed: info=%v err=%v", directory, info, err)
		}
	}
	if info, err := os.Lstat(filepath.Join(root, "runtime")); err != nil || info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("swapped runtime entry = %v, %v; want symlink", info, err)
	}
}

func TestRemoveOwnedPackageFileDoesNotFollowSwappedSymlinkAncestor(t *testing.T) {
	root := t.TempDir()
	ownedPath := filepath.Join(root, "runtime", "core", "HAWS.md")
	ownedContents := []byte("owned runtime fixture")
	if err := os.MkdirAll(filepath.Dir(ownedPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(ownedPath, ownedContents, 0o600); err != nil {
		t.Fatal(err)
	}
	external := t.TempDir()
	externalPath := filepath.Join(external, "core", "HAWS.md")
	if err := os.MkdirAll(filepath.Dir(externalPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(externalPath, []byte("user file"), 0o600); err != nil {
		t.Fatal(err)
	}
	probe := filepath.Join(root, "symlink-probe")
	if err := os.Symlink(external, probe); err != nil {
		t.Skipf("creating directory symlink is unavailable: %v", err)
	}
	if err := os.Remove(probe); err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(ownedContents)

	removed, state, err := removeOwnedPackageFileWithHook(root, "runtime/core/HAWS.md", hex.EncodeToString(hash[:]), func() {
		if err := os.Rename(filepath.Join(root, "runtime"), filepath.Join(root, "runtime-original")); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink(external, filepath.Join(root, "runtime")); err != nil {
			t.Fatal(err)
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	if removed || state != "unowned" {
		t.Fatalf("remove result = %t, %q; want preserved swapped ancestor", removed, state)
	}
	if got, err := os.ReadFile(externalPath); err != nil || string(got) != "user file" {
		t.Fatalf("external user file = %q, %v", got, err)
	}
	if got, err := os.ReadFile(filepath.Join(root, "runtime-original", "core", "HAWS.md")); err != nil || string(got) != string(ownedContents) {
		t.Fatalf("original package file = %q, %v", got, err)
	}
}

func TestRemovePackageFilesRejectsChangedOwnershipManifestAfterPreview(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	manifestPath := filepath.Join(root, ManifestName)
	contents, err := os.ReadFile(manifestPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(manifestPath, append(contents, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}

	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err == nil {
		t.Fatalf("RemovePackageFiles() accepted changed preview manifest: removed=%v preserved=%v", removed, preserved)
	}
	if len(removed) != 0 || len(preserved) != 0 {
		t.Fatalf("cleanup began before rejecting changed manifest: removed=%v preserved=%v", removed, preserved)
	}
	if _, err := os.Lstat(manifestPath); err != nil {
		t.Fatalf("changed ownership manifest was removed: %v", err)
	}
	if _, err := os.Lstat(filepath.Join(root, "README.txt")); err != nil {
		t.Fatalf("package cleanup began before rejecting changed manifest: %v", err)
	}
}

func TestReadManifestRejectsTraversalUnknownAndUntrustedManifest(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	manifest.Files["../outside"] = strings.Repeat("a", 64)
	writeManifest(t, root, manifest)
	if _, err := ReadManifest(root, runtime.GOOS); err == nil {
		t.Fatal("ReadManifest() accepted a traversal path")
	}
	manifest = makePackage(t, root)
	manifest.Files["unexpected.txt"] = strings.Repeat("a", 64)
	writeManifest(t, root, manifest)
	if _, err := ReadManifest(root, runtime.GOOS); err == nil {
		t.Fatal("ReadManifest() accepted an unexpected file")
	}
	manifest = makePackage(t, root)
	if err := os.Remove(filepath.Join(root, ManifestName)); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(root, "outside-manifest")
	encoded, _ := json.Marshal(manifest)
	if err := os.WriteFile(target, encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, filepath.Join(root, ManifestName)); err != nil {
		t.Skipf("symlink creation unavailable: %v", err)
	}
	if _, err := ReadManifest(root, runtime.GOOS); err == nil {
		t.Fatal("ReadManifest() followed a symlink manifest")
	}
}

func TestRemovePackageFilesPreservesUnownedDirectoryContent(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	custom := filepath.Join(root, "bin", "custom-note.txt")
	if err := os.WriteFile(custom, []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	removed, preserved, err := RemovePackageFiles(root, runtime.GOOS, manifest, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(removed) == 0 || len(preserved) < 2 {
		t.Fatalf("removed=%v preserved=%v", removed, preserved)
	}
	if _, err := os.Stat(custom); err != nil {
		t.Fatalf("unowned directory file was removed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, ManifestName)); err != nil {
		t.Fatalf("manifest was removed with unowned files remaining: %v", err)
	}
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func TestManifestAllowsPackagedRuntimeButRejectsPersonalState(t *testing.T) {
	root := t.TempDir()
	manifest := makePackage(t, root)
	manifest.Files["runtime/haws.sh"] = strings.Repeat("a", 64)
	writeManifest(t, root, manifest)
	if _, err := ReadManifest(root, runtime.GOOS); err != nil {
		t.Fatalf("runtime manifest rejected: %v", err)
	}
	manifest.Files["runtime/.haws/state/settings"] = strings.Repeat("a", 64)
	writeManifest(t, root, manifest)
	if _, err := ReadManifest(root, runtime.GOOS); err == nil {
		t.Fatal("personal state accepted as owned")
	}
}
