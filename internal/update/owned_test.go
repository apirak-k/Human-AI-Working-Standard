package update

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
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

func TestActiveBinaryRejectsChangedOrUnownedPaths(t *testing.T) {
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
		if _, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH); err == nil {
			t.Fatal("ActiveBinary() returned a modified installed executable")
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
