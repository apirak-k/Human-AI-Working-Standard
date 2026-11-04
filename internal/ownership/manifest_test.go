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
	return manifest
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
	if err != nil {
		t.Fatal(err)
	}
	if len(removed) != 0 || len(preserved) == 0 {
		t.Fatalf("running package removal = removed %v, preserved %v", removed, preserved)
	}
	if _, err := os.Stat(current); err != nil {
		t.Fatalf("running binary was removed: %v", err)
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
