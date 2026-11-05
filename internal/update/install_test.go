package update

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"debug/buildinfo"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/ownership"
)

type archiveEntryFixture struct {
	name       string
	data       []byte
	mode       os.FileMode
	typeFlag   byte
	linkTarget string
}

func packageOSForTest() string {
	if runtime.GOOS == "darwin" {
		return "macos"
	}
	return runtime.GOOS
}

func packageLauncherForTest() string {
	switch packageOSForTest() {
	case "windows":
		return "haws.bat"
	case "macos":
		return "haws.command"
	default:
		return "haws.sh"
	}
}

func packageRootForTest(t *testing.T) string {
	t.Helper()
	_, filename, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller() failed")
	}
	root, err := filepath.Abs(filepath.Join(filepath.Dir(filename), "../.."))
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func setEnvironment(env []string, key, value string) []string {
	prefix := key + "="
	filtered := make([]string, 0, len(env)+1)
	for _, entry := range env {
		if !strings.HasPrefix(entry, prefix) {
			filtered = append(filtered, entry)
		}
	}
	return append(filtered, prefix+value)
}

func buildFixtureBinaries(t *testing.T, version string) map[string][]byte {
	t.Helper()
	root := packageRootForTest(t)
	goos := runtime.GOOS
	platform := packageOSForTest()
	result := make(map[string][]byte, 2)
	for _, arch := range []string{"amd64", "arm64"} {
		t.Run("build-"+arch, func(t *testing.T) {
			temp := t.TempDir()
			binary := filepath.Join(temp, "haws")
			if goos == "windows" {
				binary += ".exe"
			}
			cmd := exec.Command("go", "build", "-trimpath", "-buildvcs=false", "-ldflags", "-X main.version="+version, "-o", binary, "./cmd/haws")
			cmd.Dir = root
			cmd.Env = setEnvironment(setEnvironment(os.Environ(), "GOOS", goos), "GOARCH", arch)
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("go build %s/%s failed: %v\n%s", goos, arch, err, output)
			}
			info, err := buildinfo.ReadFile(binary)
			if err != nil {
				t.Fatalf("read build info: %v", err)
			}
			if info.Path != "github.com/apirak-k/Human-AI-Working-Standard/cmd/haws" {
				t.Fatalf("main package path = %q", info.Path)
			}
			settings := map[string]string{}
			for _, setting := range info.Settings {
				settings[setting.Key] = setting.Value
			}
			if settings["GOOS"] != goos || settings["GOARCH"] != arch {
				t.Fatalf("binary target = %s/%s, want %s/%s", settings["GOOS"], settings["GOARCH"], goos, arch)
			}
			data, err := os.ReadFile(binary)
			if err != nil {
				t.Fatal(err)
			}
			result[platform+"-"+arch] = data
		})
	}
	return result
}

func makePackageArchive(t *testing.T, entries []archiveEntryFixture) []byte {
	t.Helper()
	var buffer bytes.Buffer
	if packageOSForTest() == "windows" {
		writer := zip.NewWriter(&buffer)
		for _, entry := range entries {
			header := &zip.FileHeader{Name: entry.name, Method: zip.Deflate}
			header.SetMode(entry.mode)
			file, err := writer.CreateHeader(header)
			if err != nil {
				t.Fatal(err)
			}
			if entry.mode&os.ModeSymlink != 0 {
				if _, err := io.WriteString(file, entry.linkTarget); err != nil {
					t.Fatal(err)
				}
			} else if _, err := file.Write(entry.data); err != nil {
				t.Fatal(err)
			}
		}
		if err := writer.Close(); err != nil {
			t.Fatal(err)
		}
		return buffer.Bytes()
	}

	gz := gzip.NewWriter(&buffer)
	writer := tar.NewWriter(gz)
	for _, entry := range entries {
		typeFlag := entry.typeFlag
		if typeFlag == 0 {
			typeFlag = tar.TypeReg
		}
		header := &tar.Header{
			Name:     entry.name,
			Mode:     int64(entry.mode.Perm()),
			Size:     int64(len(entry.data)),
			Typeflag: typeFlag,
			Linkname: entry.linkTarget,
			ModTime:  time.Unix(1, 0),
		}
		if typeFlag == tar.TypeSymlink || typeFlag == tar.TypeLink {
			header.Size = 0
		}
		if err := writer.WriteHeader(header); err != nil {
			t.Fatal(err)
		}
		if typeFlag == tar.TypeReg || typeFlag == tar.TypeRegA {
			if _, err := writer.Write(entry.data); err != nil {
				t.Fatal(err)
			}
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func releaseArchiveFixture(t *testing.T, version string, binaries map[string][]byte, extra ...archiveEntryFixture) []byte {
	t.Helper()
	root := packageRootForTest(t)
	platform := packageOSForTest()
	launcher, err := os.ReadFile(filepath.Join(root, "launchers", platform, packageLauncherForTest()))
	if err != nil {
		t.Fatal(err)
	}
	launcherName := packageLauncherForTest()
	extension := ""
	if platform == "windows" {
		extension = ".exe"
	}
	entries := []archiveEntryFixture{
		{
			name: "haws-go/" + platform + "/README.txt",
			data: []byte("fixture package"),
			mode: 0o644,
		},
		{
			name: "haws-go/" + platform + "/package-manifest.json",
			data: []byte("{}"),
			mode: 0o600,
		},
		{
			name: "haws-go/" + platform + "/" + launcherName,
			data: launcher,
			mode: 0o755,
		},
	}
	for _, arch := range []string{"amd64", "arm64"} {
		key := platform + "-" + arch
		data, ok := binaries[key]
		if !ok {
			t.Fatalf("fixture binary missing for %s", key)
		}
		entries = append(entries, archiveEntryFixture{
			name: "haws-go/" + platform + "/bin/" + platform + "-" + arch + "/haws" + extension,
			data: data,
			mode: 0o755,
		})
	}
	_ = version
	providedRuntime := make(map[string]bool)
	for _, entry := range extra {
		for _, file := range ownership.RuntimeFiles {
			if entry.name == "haws-go/"+platform+"/runtime/"+file {
				providedRuntime[file] = true
			}
		}
	}
	for _, file := range ownership.RuntimeFiles {
		if providedRuntime[file] {
			continue
		}
		var data []byte
		if file == "source-revisions.tsv" {
			data = []byte("skills/packs/fixture\t" + strings.Repeat("a", 40) + "\n")
		} else {
			var err error
			data, err = os.ReadFile(filepath.Join(root, filepath.FromSlash(file)))
			if err != nil {
				t.Fatalf("read fixture runtime file %s: %v", file, err)
			}
		}
		entries = append(entries, archiveEntryFixture{
			name: "haws-go/" + platform + "/runtime/" + file,
			data: data,
			mode: 0644,
		})
	}
	return makePackageArchive(t, append(entries, extra...))
}

func newAppRoot(t *testing.T, binaries map[string][]byte) string {
	t.Helper()
	root := t.TempDir()
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	files := map[string][]byte{
		"README.txt":  []byte("HAWS package fixture"),
		spec.launcher: []byte("launcher fixture"),
	}
	for _, arch := range []string{"amd64", "arm64"} {
		relative := filepath.ToSlash(filepath.Join("bin", spec.packageOS+"-"+arch, "haws"+spec.extension))
		data, ok := binaries[spec.packageOS+"-"+arch]
		if !ok {
			t.Fatalf("fixture binary missing for %s-%s", spec.packageOS, arch)
		}
		files[relative] = data
	}
	for relative, data := range files {
		filename := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filename, data, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	manifest := ownership.Manifest{
		SchemaVersion: 1,
		Version:       "v1.2.3",
		Platform:      spec.packageOS,
		Files:         make(map[string]string, len(files)),
	}
	for relative, data := range files {
		hash := sha256.Sum256(data)
		manifest.Files[relative] = hex.EncodeToString(hash[:])
	}
	contents, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ownership.ManifestName), contents, 0o600); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestInstallActivatesVersionsAndRollbackKeepsBothPackages(t *testing.T) {
	v1Binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, v1Binaries)
	if got, err := ActiveVersion(root); err != nil || got != "base" {
		t.Fatalf("initial active version = %q, %v", got, err)
	}
	v1Archive := releaseArchiveFixture(t, "v1.2.3", v1Binaries)
	if err := Install(root, "v1.2.3", v1Archive); err != nil {
		t.Fatalf("Install(v1) error = %v", err)
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.3" {
		t.Fatalf("active version after v1 = %q, %v", got, err)
	}
	if err := Install(root, "v1.2.3", v1Archive); err != nil {
		t.Fatalf("repeated Install(v1) error = %v", err)
	}

	v2Binaries := buildFixtureBinaries(t, "v1.2.4")
	v2Archive := releaseArchiveFixture(t, "v1.2.4", v2Binaries)
	if err := Install(root, "v1.2.4", v2Archive); err != nil {
		t.Fatalf("Install(v2) error = %v", err)
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.4" {
		t.Fatalf("active version after v2 = %q, %v", got, err)
	}
	if err := Rollback(root); err != nil {
		t.Fatalf("Rollback() error = %v", err)
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.3" {
		t.Fatalf("active version after rollback = %q, %v", got, err)
	}
	if err := Rollback(root); err != nil {
		t.Fatalf("second Rollback() error = %v", err)
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.4" {
		t.Fatalf("active version after rollback toggle = %q, %v", got, err)
	}
}

func TestFailedInstallLeavesActiveVersionUnchanged(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
		t.Fatal(err)
	}
	if err := Install(root, "v1.2.4", []byte("not a package archive")); err == nil {
		t.Fatal("Install() accepted a corrupt package")
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.3" {
		t.Fatalf("active version after failed install = %q, %v", got, err)
	}
}

func TestInstallFailureDuringActivationLeavesMarkerUnchanged(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
		t.Fatal(err)
	}
	installer := NewInstaller()
	installer.activate = func(string, activeState) error { return errors.New("simulated marker write failure") }
	err := installer.Install(root, "v1.2.4", releaseArchiveFixture(t, "v1.2.4", buildFixtureBinaries(t, "v1.2.4")))
	if err == nil {
		t.Fatal("Install() succeeded despite marker write failure")
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.3" {
		t.Fatalf("active version after activation failure = %q, %v", got, err)
	}
}

func TestInstallRejectsTraversalIncompleteAndSymlinkEntries(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	tests := []struct {
		name    string
		entries []archiveEntryFixture
		wantErr string
	}{
		{
			name: "path traversal",
			entries: []archiveEntryFixture{{
				name: "haws-go/" + packageOSForTest() + "/../../outside",
				data: []byte("outside"),
				mode: 0o644,
			}},
			wantErr: "unsafe path",
		},
		{
			name: "symlink",
			entries: []archiveEntryFixture{{
				name:       "haws-go/" + packageOSForTest() + "/bin/" + packageOSForTest() + "-amd64/haws",
				mode:       os.ModeSymlink | 0o777,
				linkTarget: "../../../../outside",
				typeFlag:   tar.TypeSymlink,
			}},
			wantErr: "unsupported entry type",
		},
		{
			name: "missing architecture binary",
			entries: []archiveEntryFixture{
				{name: "haws-go/" + packageOSForTest() + "/README.txt", data: []byte("fixture"), mode: 0o644},
				{name: "haws-go/" + packageOSForTest() + "/package-manifest.json", data: []byte("{}"), mode: 0o600},
				{name: "haws-go/" + packageOSForTest() + "/" + packageLauncherForTest(), data: []byte("launcher"), mode: 0o755},
				{name: "haws-go/" + packageOSForTest() + "/bin/" + packageOSForTest() + "-amd64/haws", data: []byte("binary"), mode: 0o755},
			},
			wantErr: "missing haws-go/",
		},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			root := newAppRoot(t, binaries)
			archive := makePackageArchive(t, test.entries)
			err := Install(root, "v1.2.3", archive)
			if err == nil {
				t.Fatal("Install() accepted unsafe or incomplete archive")
			}
			if !strings.Contains(err.Error(), test.wantErr) {
				t.Fatalf("Install() error = %q, want %q", err, test.wantErr)
			}
			if got, err := ActiveVersion(root); err != nil || got != "base" {
				t.Fatalf("active version changed after rejection: %q, %v", got, err)
			}
			if _, err := os.Stat(filepath.Join(root, "outside")); !errors.Is(err, os.ErrNotExist) {
				t.Fatalf("path traversal created outside file: %v", err)
			}
		})
	}
}

func TestInstallRejectsInvalidVersionAndMalformedActiveMarker(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	archive := releaseArchiveFixture(t, "v1.2.3", binaries)
	root := newAppRoot(t, binaries)
	if err := Install(root, "../escape", archive); err == nil {
		t.Fatal("Install() accepted a path-like version")
	}
	marker := filepath.Join(root, "active-version")
	if err := os.WriteFile(marker, []byte("active=../../outside\nprevious=base\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	if err := Install(root, "v1.2.3", archive); err == nil {
		t.Fatal("Install() accepted a malformed active marker")
	}
	after, err := os.ReadFile(marker)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("malformed active marker was modified")
	}
}

func TestInstallRejectsWrongArchitectureBinary(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	platform := packageOSForTest()
	launcher, err := os.ReadFile(filepath.Join(packageRootForTest(t), "launchers", platform, packageLauncherForTest()))
	if err != nil {
		t.Fatal(err)
	}
	extension := ""
	if platform == "windows" {
		extension = ".exe"
	}
	entries := []archiveEntryFixture{
		{name: "haws-go/" + platform + "/README.txt", data: []byte("fixture"), mode: 0o644},
		{name: "haws-go/" + platform + "/package-manifest.json", data: []byte("{}"), mode: 0o600},
		{name: "haws-go/" + platform + "/" + packageLauncherForTest(), data: launcher, mode: 0o755},
		{name: "haws-go/" + platform + "/bin/" + platform + "-amd64/haws" + extension, data: binaries[platform+"-amd64"], mode: 0o755},
		{name: "haws-go/" + platform + "/bin/" + platform + "-arm64/haws" + extension, data: binaries[platform+"-amd64"], mode: 0o755},
	}
	root := newAppRoot(t, binaries)
	if err := Install(root, "v1.2.3", makePackageArchive(t, entries)); err == nil {
		t.Fatal("Install() accepted an AMD64 binary labeled ARM64")
	}
}

func TestRollbackWithoutPreviousVersionFailsWithoutChangingBase(t *testing.T) {
	root := t.TempDir()
	if err := Rollback(root); err == nil {
		t.Fatal("Rollback() succeeded without a previous version")
	}
	if got, err := ActiveVersion(root); err != nil || got != "base" {
		t.Fatalf("active version after invalid rollback = %q, %v", got, err)
	}
}

func TestReleaseArchiveAcceptsPackagedRuntimeResources(t *testing.T) {
	spec := platformForRuntimeTest(t)
	prefix := "haws-go/" + spec.packageOS
	runtimeContents, err := os.ReadFile(filepath.Join(packageRootForTest(t), "haws.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if len(runtimeContents) <= maxControlFileBytes {
		t.Fatalf("fixture haws.sh is %d bytes; expected it to exceed the package control-file limit", len(runtimeContents))
	}
	stage := t.TempDir()
	if err := acceptPackageFile(spec, stage, prefix+"/runtime/haws.sh", runtimeContents, map[string]bool{}); err != nil {
		t.Fatalf("runtime rejected: %v", err)
	}
	if _, err := runtimeHashes(filepath.Join(stage, "runtime")); err != nil {
		t.Fatalf("packaged runtime hashes rejected: %v", err)
	}
	if err := acceptPackageFile(spec, t.TempDir(), prefix+"/runtime/.haws/state/settings", []byte("state"), map[string]bool{}); err == nil {
		t.Fatal("personal state accepted")
	}
}

func TestRuntimeHashesRejectUnownedFiles(t *testing.T) {
	runtimeDir := filepath.Join(t.TempDir(), "runtime")
	if err := os.MkdirAll(runtimeDir, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(runtimeDir, "haws.sh"), []byte("runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := runtimeHashes(runtimeDir); err != nil {
		t.Fatalf("owned runtime rejected: %v", err)
	}
	if err := os.WriteFile(filepath.Join(runtimeDir, "unowned.txt"), []byte("user file"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := runtimeHashes(runtimeDir); err == nil {
		t.Fatal("unowned runtime file accepted")
	}
}

func TestInstallActivatesChangedRuntimeAlongsideGoBinary(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if err := os.MkdirAll(filepath.Join(root, "runtime"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "runtime", "haws.sh"), []byte("installed"), 0600); err != nil {
		t.Fatal(err)
	}
	newRuntime := []byte("updated runtime")
	archive := releaseArchiveFixture(t, "v1.2.3", binaries, archiveEntryFixture{name: "haws-go/" + packageOSForTest() + "/runtime/haws.sh", data: newRuntime, mode: 0644})
	if err := Install(root, "v1.2.3", archive); err != nil {
		t.Fatalf("Install() rejected a valid runtime update: %v", err)
	}
	installedRuntime, err := os.ReadFile(filepath.Join(root, "versions", "v1.2.3", "runtime", "haws.sh"))
	if err != nil || !bytes.Equal(installedRuntime, newRuntime) {
		t.Fatalf("installed runtime = %q, %v; want %q", installedRuntime, err, newRuntime)
	}
	if got, err := ActiveVersion(root); err != nil || got != "v1.2.3" {
		t.Fatalf("active = %q, %v; want v1.2.3", got, err)
	}
	activeRuntime, err := ActiveRuntime(root, runtime.GOOS)
	resolvedRoot, resolveErr := resolveInstallRoot(root)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	wantRuntime := filepath.Join(resolvedRoot, "versions", "v1.2.3", "runtime")
	if err != nil || activeRuntime != wantRuntime {
		t.Fatalf("ActiveRuntime() = %q, %v; want %q", activeRuntime, err, wantRuntime)
	}
}

func TestCorruptActiveRuntimeRecoversBinaryAndRuntimeTogether(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	archive := func(version, contents string) []byte {
		return releaseArchiveFixture(t, version, binaries, archiveEntryFixture{
			name: "haws-go/" + packageOSForTest() + "/runtime/haws.sh",
			data: []byte(contents),
			mode: 0644,
		})
	}
	if err := Install(root, "v1.2.3", archive("v1.2.3", "first runtime")); err != nil {
		t.Fatal(err)
	}
	if err := Install(root, "v1.2.4", archive("v1.2.4", "second runtime")); err != nil {
		t.Fatal(err)
	}
	activeRuntime := filepath.Join(root, "versions", "v1.2.4", "runtime", "haws.sh")
	if err := os.WriteFile(activeRuntime, []byte("corrupted runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	activeBinary, err := ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	resolvedRoot, resolveErr := resolveInstallRoot(root)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	wantBinary := binaryPath(filepath.Join(resolvedRoot, "versions", "v1.2.3"), platformForRuntimeTest(t), runtime.GOARCH)
	if err != nil || activeBinary != wantBinary {
		t.Fatalf("ActiveBinary() after runtime corruption = %q, %v; want %q", activeBinary, err, wantBinary)
	}
	selectedRuntime, err := ActiveRuntime(root, runtime.GOOS)
	wantRuntime := filepath.Join(resolvedRoot, "versions", "v1.2.3", "runtime")
	if err != nil || selectedRuntime != wantRuntime {
		t.Fatalf("ActiveRuntime() after recovery = %q, %v; want %q", selectedRuntime, err, wantRuntime)
	}
}

func TestLegacyInstalledVersionWithoutRuntimeUsesBaseRuntime(t *testing.T) {
	binaries := buildFixtureBinaries(t, "v1.2.3")
	root := newAppRoot(t, binaries)
	if err := os.MkdirAll(filepath.Join(root, "runtime"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "runtime", "haws.sh"), []byte("base runtime"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := Install(root, "v1.2.3", releaseArchiveFixture(t, "v1.2.3", binaries)); err != nil {
		t.Fatal(err)
	}
	versionDir := filepath.Join(root, "versions", "v1.2.3")
	manifest, err := readInstallManifest(versionDir, "v1.2.3", platformForRuntimeTest(t))
	if err != nil {
		t.Fatal(err)
	}
	manifest.Runtime = nil
	contents, err := json.Marshal(manifest)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(versionDir, "install.json"), contents, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(versionDir, "runtime")); err != nil {
		t.Fatal(err)
	}
	activeRuntime, err := ActiveRuntime(root, runtime.GOOS)
	resolvedRoot, resolveErr := resolveInstallRoot(root)
	if resolveErr != nil {
		t.Fatal(resolveErr)
	}
	wantRuntime := filepath.Join(resolvedRoot, "runtime")
	if err != nil || activeRuntime != wantRuntime {
		t.Fatalf("ActiveRuntime() for a legacy version = %q, %v; want %q", activeRuntime, err, wantRuntime)
	}
}
