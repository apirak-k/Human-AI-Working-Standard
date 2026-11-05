package update

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/ownership"
)

func TestRemoveInstalledVersionRejectsReplacedVersionsParent(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
		t.Fatal(err)
	}
	versions, err := InstalledVersions(root)
	if err != nil || len(versions) != 1 {
		t.Fatalf("InstalledVersions() = %#v, %v; want one installed version", versions, err)
	}

	outsideRoot := t.TempDir()
	outsideVersions := filepath.Join(outsideRoot, "versions")
	if err := os.Rename(filepath.Join(root, "versions"), outsideVersions); err != nil {
		t.Fatal(err)
	}
	versionsPath := filepath.Join(root, "versions")
	if runtime.GOOS == "windows" {
		cmd := exec.Command("powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", "$ErrorActionPreference = 'Stop'; New-Item -ItemType Junction -Path $env:HAWS_TEST_LINK -Target $env:HAWS_TEST_TARGET | Out-Null")
		cmd.Env = setEnvironment(setEnvironment(os.Environ(), "HAWS_TEST_LINK", versionsPath), "HAWS_TEST_TARGET", outsideVersions)
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("create test junction: %v\n%s", err, output)
		}
	} else if err := os.Symlink(outsideVersions, versionsPath); err != nil {
		t.Skipf("creating a directory symlink is unavailable on %s: %v", runtime.GOOS, err)
	}
	defer os.Remove(versionsPath)

	err = RemoveInstalledVersion(root, versions[0], "")
	if err == nil {
		t.Fatal("RemoveInstalledVersion() followed a replaced versions parent")
	}
	for _, arch := range []string{"amd64", "arm64"} {
		binary := binaryPath(filepath.Join(outsideVersions, versions[0].Version), platformSpecForTest(), arch)
		if _, err := os.Stat(binary); err != nil {
			t.Fatalf("external version binary %q was removed: %v", binary, err)
		}
	}
}

func TestRemoveInstalledVersionRemovesOnlyFingerprintedRuntime(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	archive := releaseArchiveFixture(t, "v1.2.3", binaries, archiveEntryFixture{
		name: "haws-go/" + packageOSForTest() + "/runtime/haws.sh",
		data: []byte("versioned runtime"),
		mode: 0644,
	})
	if err := Install(root, "v1.2.3", archive); err != nil {
		t.Fatal(err)
	}
	versions, err := InstalledVersions(root)
	if err != nil || len(versions) != 1 {
		t.Fatalf("InstalledVersions() = %#v, %v; want one version", versions, err)
	}
	if err := RemoveInstalledVersion(root, versions[0], ""); err != nil {
		t.Fatalf("RemoveInstalledVersion() failed: %v", err)
	}
	if _, err := os.Lstat(filepath.Join(root, "versions", "v1.2.3")); !os.IsNotExist(err) {
		t.Fatalf("version directory remains: %v", err)
	}
}

func TestRemoveInstalledVersionPreservesModifiedRuntime(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	archive := releaseArchiveFixture(t, "v1.2.3", binaries, archiveEntryFixture{
		name: "haws-go/" + packageOSForTest() + "/runtime/haws.sh",
		data: []byte("versioned runtime"),
		mode: 0644,
	})
	if err := Install(root, "v1.2.3", archive); err != nil {
		t.Fatal(err)
	}
	versions, err := InstalledVersions(root)
	if err != nil || len(versions) != 1 {
		t.Fatalf("InstalledVersions() = %#v, %v; want one version", versions, err)
	}
	runtimeFile := filepath.Join(root, "versions", "v1.2.3", "runtime", "haws.sh")
	if err := os.WriteFile(runtimeFile, []byte("user-modified runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := RemoveInstalledVersion(root, versions[0], ""); err == nil {
		t.Fatal("RemoveInstalledVersion() removed a modified runtime")
	}
	if contents, err := os.ReadFile(runtimeFile); err != nil || string(contents) != "user-modified runtime" {
		t.Fatalf("modified runtime = %q, %v; expected it to remain", contents, err)
	}
}

func TestActiveBinaryReturnsValidatedInstalledVersion(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if got, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err != nil || got != "" {
		t.Fatalf("ActiveBinary() before update = %q, %v; want empty base marker", got, err)
	}
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
		t.Fatal(err)
	}
	got, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	resolvedRoot, resolveErr := resolveInstallRoot(root)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	want := binaryPath(filepath.Join(resolvedRoot, "versions", "v1.2.3"), platformForRuntimeTest(t), runtime.GOARCH)
	if err != nil || got != want {
		t.Fatalf("ActiveBinary() = %q, %v; want %q", got, err, want)
	}
}

func TestActiveBinaryRecoversCorruptActiveVersionToValidatedPrevious(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	v2Binaries := buildFixtureBinaries(t, "v1.2.4")
	if err := Install(root, "v1.2.4", releaseArchiveFixture(t, "v1.2.4", v2Binaries)); err != nil {
		t.Fatal(err)
	}

	spec := platformForRuntimeTest(t)
	activeBinary := binaryPath(filepath.Join(root, "versions", "v1.2.4"), spec, runtime.GOARCH)
	if err := os.WriteFile(activeBinary, []byte("corrupt active executable"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	if err != nil {
		t.Fatalf("ActiveBinary() did not recover: %v", err)
	}
	resolvedRoot, err := resolveInstallRoot(root)
	if err != nil {
		t.Fatal(err)
	}
	want := binaryPath(filepath.Join(resolvedRoot, "versions", "v1.2.3"), spec, runtime.GOARCH)
	if got != want {
		t.Fatalf("ActiveBinary() = %q, want validated previous binary %q", got, want)
	}
	if active, err := ActiveVersion(root); err != nil || active != "v1.2.3" {
		t.Fatalf("active version after recovery = %q, %v; want v1.2.3", active, err)
	}
	state, err := readActiveState(root)
	if err != nil || state.Previous != "v1.2.4" {
		t.Fatalf("previous version after recovery = %q, %v; want failed v1.2.4 retained for inspection", state.Previous, err)
	}
}

func TestActiveBinaryRecoversCorruptActiveVersionToBasePackage(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	writeOwnedBasePackageForTest(t, root)
	spec := platformForRuntimeTest(t)
	activeBinary := binaryPath(filepath.Join(root, "versions", "v1.2.3"), spec, runtime.GOARCH)
	if err := os.WriteFile(activeBinary, []byte("corrupt active executable"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	if err != nil || got != "" {
		t.Fatalf("ActiveBinary() = %q, %v; want empty path for recovered base package", got, err)
	}
	if active, err := ActiveVersion(root); err != nil || active != baseVersion {
		t.Fatalf("active version after base recovery = %q, %v; want base", active, err)
	}
}

func TestActiveBinaryRejectsBaseWithModifiedButValidGoBinary(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	writeOwnedBasePackageForTest(t, root)
	spec := platformForRuntimeTest(t)
	corruptVersionBinary(t, root, "v1.2.3", spec)

	baseBinary := binaryPath(root, spec, runtime.GOARCH)
	changedBinaries := buildFixtureBinaries(t, "v1.2.4")
	contents := changedBinaries[spec.packageOS+"-"+runtime.GOARCH]
	if err := os.WriteFile(baseBinary, contents, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := validateGoBinary(baseBinary, spec.goos, runtime.GOARCH); err != nil {
		t.Fatalf("test fixture lost valid Go metadata: %v", err)
	}
	assertActiveRecoveryFailsWithoutChangingMarker(t, root)
}

func TestActiveBinaryRejectsBaseBehindSymlinkedBinParent(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	writeOwnedBasePackageForTest(t, root)
	spec := platformForRuntimeTest(t)
	corruptVersionBinary(t, root, "v1.2.3", spec)

	binPath := filepath.Join(root, "bin")
	externalBin := filepath.Join(t.TempDir(), "bin")
	if err := os.Rename(binPath, externalBin); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(externalBin, binPath); err != nil {
		t.Skipf("creating directory symlink is unavailable: %v", err)
	}
	assertActiveRecoveryFailsWithoutChangingMarker(t, root)
	externalBinary := filepath.Join(externalBin, spec.packageOS+"-"+runtime.GOARCH, "haws"+spec.extension)
	if _, err := os.Stat(externalBinary); err != nil {
		t.Fatalf("external base binary was changed: %v", err)
	}
}

func TestActiveBinaryRequiresBaseOwnershipManifestForRecovery(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(root, ownership.ManifestName)); err != nil {
		t.Fatal(err)
	}
	corruptVersionBinary(t, root, "v1.2.3", platformForRuntimeTest(t))
	assertActiveRecoveryFailsWithoutChangingMarker(t, root)
}

func TestActiveBinaryRejectsSymlinkedVersionsParentForRecovery(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	v2Binaries := buildFixtureBinaries(t, "v1.2.4")
	if err := Install(root, "v1.2.4", releaseArchiveFixture(t, "v1.2.4", v2Binaries)); err != nil {
		t.Fatal(err)
	}
	versionsPath := filepath.Join(root, "versions")
	externalVersions := filepath.Join(t.TempDir(), "versions")
	if err := os.Rename(versionsPath, externalVersions); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(externalVersions, versionsPath); err != nil {
		t.Skipf("creating directory symlink is unavailable: %v", err)
	}
	assertActiveRecoveryFailsWithoutChangingMarker(t, root)
	if _, err := os.Stat(filepath.Join(externalVersions, "v1.2.3")); err != nil {
		t.Fatalf("external previous version was changed: %v", err)
	}
}

func TestActiveBinaryRejectsMalformedMarkerWithoutRecovery(t *testing.T) {
	root := newAppRoot(t, buildFixtureBinaries(t, "v1.2.3"))
	marker := filepath.Join(root, activeMarkerName)
	contents := []byte("unowned marker content\n")
	if err := os.WriteFile(marker, contents, 0o600); err != nil {
		t.Fatal(err)
	}
	assertActiveRecoveryFailsWithoutChangingMarker(t, root)
}

func writeOwnedBasePackageForTest(t *testing.T, root string) {
	t.Helper()
	spec := platformForRuntimeTest(t)
	files := map[string][]byte{
		"README.txt":  []byte("HAWS package fixture"),
		spec.launcher: []byte("launcher fixture"),
	}
	for _, arch := range []string{"amd64", "arm64"} {
		relative := filepath.ToSlash(filepath.Join("bin", spec.packageOS+"-"+arch, "haws"+spec.extension))
		contents, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(relative)))
		if err != nil {
			t.Fatal(err)
		}
		files[relative] = contents
	}
	manifest := ownership.Manifest{
		SchemaVersion: 1,
		Version:       "v1.2.3",
		Platform:      spec.packageOS,
		Files:         make(map[string]string, len(files)),
	}
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
	contents, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ownership.ManifestName), contents, 0o600); err != nil {
		t.Fatal(err)
	}
}

func corruptVersionBinary(t *testing.T, root, version string, spec platformSpec) {
	t.Helper()
	binary := binaryPath(filepath.Join(root, "versions", version), spec, runtime.GOARCH)
	if err := os.WriteFile(binary, []byte("corrupt active executable"), 0o755); err != nil {
		t.Fatal(err)
	}
}

func assertActiveRecoveryFailsWithoutChangingMarker(t *testing.T, root string) {
	t.Helper()
	marker := filepath.Join(root, activeMarkerName)
	before, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err == nil {
		t.Fatal("ActiveBinary() recovered using an untrusted base package")
	}
	after, err := os.ReadFile(marker)
	if err != nil || string(after) != string(before) {
		t.Fatalf("failed recovery changed marker: before %q after %q (%v)", before, after, err)
	}
}

func TestActiveBinaryDoesNotSelectPreviousIfRecoveryCannotCommit(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows does not enforce Unix directory write bits")
	}
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	v2Binaries := buildFixtureBinaries(t, "v1.2.4")
	if err := Install(root, "v1.2.4", releaseArchiveFixture(t, "v1.2.4", v2Binaries)); err != nil {
		t.Fatal(err)
	}
	activeBinary := binaryPath(filepath.Join(root, "versions", "v1.2.4"), platformForRuntimeTest(t), runtime.GOARCH)
	if err := os.WriteFile(activeBinary, []byte("corrupt active executable"), 0o755); err != nil {
		t.Fatal(err)
	}
	markerBefore, err := os.ReadFile(filepath.Join(root, activeMarkerName))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(root, 0o500); err != nil {
		t.Fatal(err)
	}
	defer func() { _ = os.Chmod(root, 0o700) }()
	if _, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err == nil {
		t.Fatal("ActiveBinary() returned a prior version without persisting recovery")
	}
	if err := os.Chmod(root, 0o700); err != nil {
		t.Fatal(err)
	}
	markerAfter, err := os.ReadFile(filepath.Join(root, activeMarkerName))
	if err != nil || string(markerAfter) != string(markerBefore) {
		t.Fatalf("failed recovery changed marker: before %q after %q (%v)", markerBefore, markerAfter, err)
	}
}

func TestActiveBinaryFailsClosedWhenActiveAndPreviousAreCorrupt(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", v1Binaries)); err != nil {
		t.Fatal(err)
	}
	v2Binaries := buildFixtureBinaries(t, "v1.2.4")
	if err := Install(root, "v1.2.4", releaseArchiveFixture(t, "v1.2.4", v2Binaries)); err != nil {
		t.Fatal(err)
	}
	spec := platformForRuntimeTest(t)
	for _, version := range []string{"v1.2.3", "v1.2.4"} {
		binary := binaryPath(filepath.Join(root, "versions", version), spec, runtime.GOARCH)
		if err := os.WriteFile(binary, []byte("corrupt "+version), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	markerBefore, err := os.ReadFile(filepath.Join(root, activeMarkerName))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err == nil {
		t.Fatal("ActiveBinary() succeeded without a valid active or previous version")
	}
	markerAfter, err := os.ReadFile(filepath.Join(root, activeMarkerName))
	if err != nil || string(markerAfter) != string(markerBefore) {
		t.Fatalf("failed recovery changed marker: before %q after %q (%v)", markerBefore, markerAfter, err)
	}
}

func TestActiveBinaryRecoversChangedBinaryAndRejectsUnownedMarker(t *testing.T) {
	t.Run("changed binary", func(t *testing.T) {
		binaries := buildFixtureBinaries(t, "v1.2.3")
		root := newAppRoot(t, binaries)
		if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
			t.Fatal(err)
		}
		versionDir := filepath.Join(root, "versions", "v1.2.3")
		binary := binaryPath(versionDir, platformSpecForTest(), runtime.GOARCH)
		if err := os.WriteFile(binary, []byte("modified after installation"), 0o755); err != nil {
			t.Fatal(err)
		}
		if got, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err != nil || got != "" {
			t.Fatalf("ActiveBinary() = %q, %v; want validated base package fallback", got, err)
		}
		if active, err := ActiveVersion(root); err != nil || active != baseVersion {
			t.Fatalf("active version after recovery = %q, %v; want base", active, err)
		}
	})

	t.Run("symlinked active marker", func(t *testing.T) {
		root := newAppRoot(t, buildFixtureBinaries(t, "v1.2.3"))
		outside := filepath.Join(t.TempDir(), "active-version")
		if err := os.WriteFile(outside, []byte("HAWS_GO_ACTIVE_V1\nactive=base\nprevious=\n"), 0o600); err != nil {
			t.Fatal(err)
		}
		marker := filepath.Join(root, activeMarkerName)
		if err := os.Symlink(outside, marker); err != nil {
			t.Skipf("creating a file symlink is unavailable on %s: %v", runtime.GOOS, err)
		}
		if _, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err == nil {
			t.Fatal("ActiveBinary() followed an unowned marker symlink")
		}
	})
}

func platformSpecForTest() platformSpec {
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		panic(err)
	}
	return spec
}

func platformForRuntimeTest(t *testing.T) platformSpec {
	t.Helper()
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	return spec
}
