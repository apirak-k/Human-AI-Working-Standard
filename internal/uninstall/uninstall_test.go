package uninstall

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
)

type fixtureManifest struct {
	Version       string            `json:"version"`
	Platform      string            `json:"platform"`
	ArchiveSHA256 string            `json:"archive_sha256"`
	Binaries      map[string]string `json:"binaries"`
}

var (
	fixtureOnce     sync.Once
	fixtureBinaries map[string][]byte
	fixtureErr      error
)

func ownedBinaries(t *testing.T) map[string][]byte {
	t.Helper()
	fixtureOnce.Do(func() {
		fixtureBinaries = make(map[string][]byte, 2)
		for _, arch := range []string{"amd64", "arm64"} {
			dir, err := os.MkdirTemp("", "haws-uninstall-build-")
			if err != nil {
				fixtureErr = err
				return
			}
			binary := filepath.Join(dir, "haws")
			cmd := exec.Command("go", "build", "-trimpath", "-buildvcs=false", "-ldflags", "-X main.version=v1.2.3", "-o", binary, "./cmd/haws")
			cmd.Dir = moduleRoot(t)
			cmd.Env = append(os.Environ(), "GOOS="+runtime.GOOS, "GOARCH="+arch, "CGO_ENABLED=0")
			if output, err := cmd.CombinedOutput(); err != nil {
				fixtureErr = errors.New(string(output))
				_ = os.RemoveAll(dir)
				return
			}
			contents, err := os.ReadFile(binary)
			_ = os.RemoveAll(dir)
			if err != nil {
				fixtureErr = err
				return
			}
			fixtureBinaries[runtime.GOOS+"-"+arch] = contents
		}
	})
	if fixtureErr != nil {
		t.Fatal(fixtureErr)
	}
	return fixtureBinaries
}

func moduleRoot(t *testing.T) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func makeOwnedVersion(t *testing.T, root, version string) []string {
	t.Helper()
	specOS := runtime.GOOS
	if specOS == "darwin" {
		specOS = "macos"
	}
	extension := ""
	if runtime.GOOS == "windows" {
		extension = ".exe"
	}
	versionDir := filepath.Join(root, "versions", version)
	manifest := fixtureManifest{
		Version:       version,
		Platform:      specOS,
		ArchiveSHA256: digest([]byte("fixture package " + version)),
		Binaries:      make(map[string]string, 2),
	}
	binaries := ownedBinaries(t)
	paths := make([]string, 0, 2)
	for _, arch := range []string{"amd64", "arm64"} {
		binary := filepath.Join(versionDir, "bin", specOS+"-"+arch, "haws"+extension)
		if err := os.MkdirAll(filepath.Dir(binary), 0o755); err != nil {
			t.Fatal(err)
		}
		contents := binaries[runtime.GOOS+"-"+arch]
		if err := os.WriteFile(binary, contents, 0o755); err != nil {
			t.Fatal(err)
		}
		manifest.Binaries[arch] = digest(contents)
		paths = append(paths, binary)
	}
	encoded, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(versionDir, "install.json"), encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	return paths
}

func digest(contents []byte) string {
	hash := sha256.Sum256(contents)
	return hex.EncodeToString(hash[:])
}

func writeActiveMarker(t *testing.T, root, active string) {
	t.Helper()
	contents := "HAWS_GO_ACTIVE_V1\nactive=" + active + "\nprevious=base\n"
	if err := os.WriteFile(filepath.Join(root, "active-version"), []byte(contents), 0o600); err != nil {
		t.Fatal(err)
	}
}

func makeOwnedBasePackage(t *testing.T, root string) []string {
	t.Helper()
	platform := runtime.GOOS
	launcher := "haws.sh"
	extension := ""
	if platform == "darwin" {
		platform = "macos"
		launcher = "haws.command"
	}
	if platform == "windows" {
		launcher = "haws.bat"
		extension = ".exe"
	}
	files := map[string][]byte{
		"README.txt": []byte("package notes"),
		launcher:     []byte("launcher"),
		"bin/" + platform + "-amd64/haws" + extension: []byte("amd64 base"),
		"bin/" + platform + "-arm64/haws" + extension: []byte("arm64 base"),
	}
	manifestFiles := make(map[string]string, len(files))
	paths := make([]string, 0, len(files))
	for relative, contents := range files {
		filename := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, contents, 0o755); err != nil {
			t.Fatal(err)
		}
		manifestFiles[relative] = digest(contents)
		paths = append(paths, filename)
	}
	manifest := struct {
		SchemaVersion int               `json:"schema_version"`
		Version       string            `json:"version"`
		Platform      string            `json:"platform"`
		Files         map[string]string `json:"files"`
	}{SchemaVersion: 1, Version: "v1.2.3", Platform: platform, Files: manifestFiles}
	encoded, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "package-manifest.json"), encoded, 0o600); err != nil {
		t.Fatal(err)
	}
	return paths
}

func TestPreviewAndApplyRemoveOnlyVerifiedUpdaterFiles(t *testing.T) {
	root := t.TempDir()
	paths := makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	launcherName := map[string]string{"windows": "haws.bat", "darwin": "haws.command", "linux": "haws.sh"}[runtime.GOOS]
	specOS := runtime.GOOS
	if specOS == "darwin" {
		specOS = "macos"
	}
	extension := ""
	if runtime.GOOS == "windows" {
		extension = ".exe"
	}
	baseLauncher := filepath.Join(root, launcherName)
	baseBinary := filepath.Join(root, "bin", specOS+"-"+runtime.GOARCH, "haws"+extension)
	personalFile := filepath.Join(filepath.Dir(root), "keep-personal-data.txt")
	for filename, contents := range map[string]string{baseLauncher: "base launcher", baseBinary: "base binary", personalFile: "personal"} {
		if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, []byte(contents), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	plan, err := Preview(root, "/not-the-running-binary")
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Items()) != 2 {
		t.Fatalf("preview items = %v", plan.Items())
	}
	result, err := Apply(plan)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Removed) != 3 {
		t.Fatalf("removed items = %v", result.Removed)
	}
	for _, filename := range append(paths, filepath.Join(root, "active-version"), filepath.Join(root, "versions")) {
		if _, err := os.Lstat(filename); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("owned updater path remains at %s: %v", filename, err)
		}
	}
	for filename, want := range map[string]string{baseLauncher: "base launcher", baseBinary: "base binary", personalFile: "personal"} {
		got, err := os.ReadFile(filename)
		if err != nil || string(got) != want {
			t.Fatalf("preserved file %s = %q, %v", filename, got, err)
		}
	}
}

func TestApplyPreservesModifiedVersionAndUnownedFiles(t *testing.T) {
	root := t.TempDir()
	paths := makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	if err := os.WriteFile(paths[0], []byte("locally modified"), 0o755); err != nil {
		t.Fatal(err)
	}
	plan, err := Preview(root, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Items()) != 1 {
		t.Fatalf("modified version entered removal plan: %v", plan.Items())
	}
	result, err := Apply(plan)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Preserved) < 2 {
		t.Fatalf("preserved paths = %v", result.Preserved)
	}
	contents, err := os.ReadFile(paths[0])
	if err != nil || string(contents) != "locally modified" {
		t.Fatalf("modified binary = %q, %v", contents, err)
	}
	if _, err := os.Stat(filepath.Join(root, "versions", "v1.2.3", "install.json")); err != nil {
		t.Fatalf("modified version manifest was removed: %v", err)
	}
}

func TestApplyPreservesRunningVersionUntilProcessExits(t *testing.T) {
	root := t.TempDir()
	paths := makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	plan, err := Preview(root, paths[0])
	if err != nil {
		t.Fatal(err)
	}
	result, err := Apply(plan)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Preserved) < 2 {
		t.Fatalf("running version was not preserved: %v", result.Preserved)
	}
	if _, err := os.Stat(paths[0]); err != nil {
		t.Fatalf("running executable was removed: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "active-version")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("active marker remains after fallback activation: %v", err)
	}
}

func TestPreviewRejectsModifiedMarkerAndApplyDetectsChanges(t *testing.T) {
	root := t.TempDir()
	makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	plan, err := Preview(root, "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "active-version"), []byte("unowned marker\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Apply(plan); err == nil {
		t.Fatal("Apply() removed a marker changed after preview")
	}
	if _, err := os.Stat(filepath.Join(root, "versions", "v1.2.3")); err != nil {
		t.Fatalf("version was removed after marker verification failed: %v", err)
	}
	if _, err := Preview(root, ""); err == nil {
		t.Fatal("Preview() accepted an unowned marker")
	}
}

func TestPreviewKeepsVersionTreesWithUnexpectedFiles(t *testing.T) {
	root := t.TempDir()
	makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	if err := os.WriteFile(filepath.Join(root, "versions", "v1.2.3", "user-note.txt"), []byte("keep"), 0o600); err != nil {
		t.Fatal(err)
	}
	plan, err := Preview(root, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Items()) != 1 {
		t.Fatalf("unowned version tree entered removal plan: %v", plan.Items())
	}
	if _, err := Apply(plan); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "versions", "v1.2.3", "user-note.txt")); err != nil {
		t.Fatalf("unowned file was removed: %v", err)
	}
}

func TestApplyPreservesVersionWhenOwnershipChangesAfterPreview(t *testing.T) {
	root := t.TempDir()
	paths := makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	plan, err := Preview(root, "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths[1], []byte("changed after preview"), 0o755); err != nil {
		t.Fatal(err)
	}
	result, err := Apply(plan)
	if err == nil || len(result.Preserved) == 0 {
		t.Fatalf("Apply() = %#v, %v; expected preservation error", result, err)
	}
	if _, err := os.Stat(paths[1]); err != nil {
		t.Fatalf("changed file was removed: %v", err)
	}
}

func TestApplyPreservesReplacedVersionsParentAndExternalFiles(t *testing.T) {
	root := t.TempDir()
	makeOwnedVersion(t, root, "v1.2.3")
	writeActiveMarker(t, root, "v1.2.3")
	plan, err := Preview(root, "")
	if err != nil {
		t.Fatal(err)
	}

	outsideRoot := t.TempDir()
	outsideVersions := filepath.Join(outsideRoot, "versions")
	if err := os.Rename(filepath.Join(root, "versions"), outsideVersions); err != nil {
		t.Fatal(err)
	}
	versionsPath := filepath.Join(root, "versions")
	if runtime.GOOS == "windows" {
		cmd := exec.Command("powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference = 'Stop'; New-Item -ItemType Junction -Path $env:HAWS_TEST_LINK -Target $env:HAWS_TEST_TARGET | Out-Null")
		cmd.Env = append(os.Environ(), "HAWS_TEST_LINK="+versionsPath, "HAWS_TEST_TARGET="+outsideVersions)
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("create test junction: %v\n%s", err, output)
		}
	} else if err := os.Symlink(outsideVersions, versionsPath); err != nil {
		t.Skipf("creating a directory symlink is unavailable on %s: %v", runtime.GOOS, err)
	}

	result, err := Apply(plan)
	if err == nil {
		t.Fatal("Apply() did not report the changed versions path")
	}
	if _, err := os.Lstat(versionsPath); err != nil {
		t.Fatalf("unowned versions link was removed: %v", err)
	}
	specOS := runtime.GOOS
	if specOS == "darwin" {
		specOS = "macos"
	}
	extension := ""
	if runtime.GOOS == "windows" {
		extension = ".exe"
	}
	for _, arch := range []string{"amd64", "arm64"} {
		outsideFile := filepath.Join(outsideVersions, "v1.2.3", "bin", specOS+"-"+arch, "haws"+extension)
		if _, err := os.Stat(outsideFile); err != nil {
			t.Fatalf("external updater file was removed: %s: %v; result=%#v", outsideFile, err, result)
		}
	}
}

func TestPreviewAndApplyRemoveVerifiedBasePackageWithoutTouchingPersonalData(t *testing.T) {
	root := t.TempDir()
	files := makeOwnedBasePackage(t, root)
	writeActiveMarker(t, root, "base")
	personal := filepath.Join(filepath.Dir(root), "keep-personal.txt")
	if err := os.WriteFile(personal, []byte("personal"), 0o600); err != nil {
		t.Fatal(err)
	}
	plan, err := Preview(root, "/not-the-running-binary")
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Items()) != 6 {
		t.Fatalf("base package preview items = %v", plan.Items())
	}
	result, err := Apply(plan)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Removed) < 6 {
		t.Fatalf("base package removal result = %#v", result)
	}
	for _, filename := range append(files, filepath.Join(root, "package-manifest.json")) {
		if _, err := os.Lstat(filename); !errors.Is(err, os.ErrNotExist) {
			t.Fatalf("owned base package path remains at %s: %v", filename, err)
		}
	}
	contents, err := os.ReadFile(personal)
	if err != nil || string(contents) != "personal" {
		t.Fatalf("personal data = %q, %v", contents, err)
	}
}
