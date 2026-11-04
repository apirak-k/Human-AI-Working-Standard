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
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	baseVersion         = "base"
	activeMarkerName    = "active-version"
	activeMarkerHeader  = "HAWS_GO_ACTIVE_V1"
	maxInstalledBinary  = 64 << 20
	maxInstalledTotal   = 132 << 20
	maxControlFileBytes = 256 << 10
)

type activeState struct {
	Active   string
	Previous string
}

type installManifest struct {
	Version       string            `json:"version"`
	Platform      string            `json:"platform"`
	ArchiveSHA256 string            `json:"archive_sha256"`
	Binaries      map[string]string `json:"binaries"`
}

type Installer struct {
	platform string
	activate func(string, activeState) error
}

type platformSpec struct {
	packageOS string
	goos      string
	launcher  string
	extension string
}

func NewInstaller() *Installer {
	return &Installer{platform: runtime.GOOS}
}

func Install(root, version string, archive []byte) error {
	return NewInstaller().Install(root, version, archive)
}

func Rollback(root string) error {
	return NewInstaller().Rollback(root)
}

func ActiveVersion(root string) (string, error) {
	root, err := resolveInstallRoot(root)
	if err != nil {
		return "", err
	}
	state, err := readActiveState(root)
	if err != nil {
		return "", err
	}
	return state.Active, nil
}

func ActiveBinary(root, goos, goarch string) (string, error) {
	spec, err := platformForOS(goos)
	if err != nil {
		return "", err
	}
	if goarch != "amd64" && goarch != "arm64" {
		return "", fmt.Errorf("unsupported HAWS app architecture %q", goarch)
	}
	root, err = resolveInstallRoot(root)
	if err != nil {
		return "", err
	}
	state, err := readActiveState(root)
	if err != nil {
		return "", err
	}
	if state.Active == baseVersion {
		return "", nil
	}
	if err := validateInstalledVersion(root, state.Active, spec); err != nil {
		return "", fmt.Errorf("active HAWS app version is invalid: %w", err)
	}
	return binaryPath(filepath.Join(root, "versions", state.Active), spec, goarch), nil
}

func (i *Installer) Install(root, version string, archive []byte) error {
	if i == nil {
		return errors.New("installer is not configured")
	}
	if !validInstallVersion(version) {
		return fmt.Errorf("invalid HAWS version %q", version)
	}
	if len(archive) == 0 || int64(len(archive)) > maxAssetBytes {
		return errors.New("release package is empty or exceeds the size limit")
	}
	spec, err := platformForOS(i.platform)
	if err != nil {
		return err
	}
	root, err = resolveInstallRoot(root)
	if err != nil {
		return err
	}
	state, err := readActiveState(root)
	if err != nil {
		return err
	}
	if state.Active == baseVersion {
		if err := validateBasePackage(root, spec); err != nil {
			return fmt.Errorf("current HAWS package is not valid: %w", err)
		}
	} else if err := validateInstalledVersion(root, state.Active, spec); err != nil {
		return fmt.Errorf("current HAWS version is not valid: %w", err)
	}

	archiveDigest := sha256.Sum256(archive)
	archiveHash := hex.EncodeToString(archiveDigest[:])
	versionDir := filepath.Join(root, "versions", version)
	if info, statErr := os.Lstat(versionDir); statErr == nil {
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return fmt.Errorf("version path is not an HAWS-owned directory: %s", versionDir)
		}
		manifest, err := readInstallManifest(versionDir, version, spec)
		if err != nil {
			return err
		}
		if manifest.ArchiveSHA256 != archiveHash {
			return fmt.Errorf("version %s is already installed with different package contents", version)
		}
		if state.Active == version {
			return nil
		}
		return i.activateState(root, activeState{Active: version, Previous: state.Active})
	} else if !errors.Is(statErr, os.ErrNotExist) {
		return fmt.Errorf("inspect version path: %w", statErr)
	}

	versionsDir, err := ensureVersionsDirectory(root)
	if err != nil {
		return err
	}
	stageDir, err := os.MkdirTemp(versionsDir, ".stage-")
	if err != nil {
		return fmt.Errorf("create version staging directory: %w", err)
	}
	keepStage := false
	defer func() {
		if !keepStage {
			_ = os.RemoveAll(stageDir)
		}
	}()

	if err := extractPackage(spec, archive, stageDir); err != nil {
		return fmt.Errorf("validate release package: %w", err)
	}
	binaryHashes, err := validateVersionBinaries(stageDir, spec)
	if err != nil {
		return err
	}
	manifest := installManifest{
		Version:       version,
		Platform:      spec.packageOS,
		ArchiveSHA256: archiveHash,
		Binaries:      binaryHashes,
	}
	if err := writeInstallManifest(stageDir, manifest); err != nil {
		return err
	}
	if _, err := os.Lstat(versionDir); err == nil {
		return fmt.Errorf("version directory appeared during installation: %s", versionDir)
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("recheck version directory: %w", err)
	}
	if err := os.Rename(stageDir, versionDir); err != nil {
		return fmt.Errorf("publish staged HAWS version: %w", err)
	}
	keepStage = true

	return i.activateState(root, activeState{Active: version, Previous: state.Active})
}

func (i *Installer) ActiveVersion(root string) (string, error) {
	return ActiveVersion(root)
}

func (i *Installer) Rollback(root string) error {
	if i == nil {
		return errors.New("installer is not configured")
	}
	spec, err := platformForOS(i.platform)
	if err != nil {
		return err
	}
	root, err = resolveInstallRoot(root)
	if err != nil {
		return err
	}
	state, err := readActiveState(root)
	if err != nil {
		return err
	}
	if state.Previous == "" {
		return errors.New("no previous HAWS version is available for rollback")
	}
	if state.Previous == baseVersion {
		if err := validateBasePackage(root, spec); err != nil {
			return fmt.Errorf("base HAWS package is not valid: %w", err)
		}
	} else if err := validateInstalledVersion(root, state.Previous, spec); err != nil {
		return fmt.Errorf("previous HAWS version is not valid: %w", err)
	}
	if state.Active != baseVersion {
		if err := validateInstalledVersion(root, state.Active, spec); err != nil {
			return fmt.Errorf("active HAWS version is not valid: %w", err)
		}
	}
	return i.activateState(root, activeState{Active: state.Previous, Previous: state.Active})
}

func (i *Installer) activateState(root string, state activeState) error {
	if i.activate != nil {
		return i.activate(root, state)
	}
	return writeActiveState(root, state)
}

func validInstallVersion(version string) bool {
	return version != baseVersion && validVersion(version)
}

func platformForOS(goos string) (platformSpec, error) {
	switch goos {
	case "windows":
		return platformSpec{packageOS: "windows", goos: "windows", launcher: "haws.bat", extension: ".exe"}, nil
	case "darwin":
		return platformSpec{packageOS: "macos", goos: "darwin", launcher: "haws.command"}, nil
	case "linux":
		return platformSpec{packageOS: "linux", goos: "linux", launcher: "haws.sh"}, nil
	default:
		return platformSpec{}, fmt.Errorf("unsupported HAWS install platform %q", goos)
	}
}

func resolveInstallRoot(root string) (string, error) {
	if strings.TrimSpace(root) == "" {
		return "", errors.New("HAWS application directory is required")
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS application directory: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS application directory: %w", err)
	}
	info, err := os.Stat(resolved)
	if err != nil {
		return "", fmt.Errorf("inspect HAWS application directory: %w", err)
	}
	if !info.IsDir() {
		return "", errors.New("HAWS application path is not a directory")
	}
	return resolved, nil
}

func ensureVersionsDirectory(root string) (string, error) {
	path := filepath.Join(root, "versions")
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.Mkdir(path, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
			return "", fmt.Errorf("create versions directory: %w", err)
		}
		info, err = os.Lstat(path)
	}
	if err != nil {
		return "", fmt.Errorf("inspect versions directory: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return "", errors.New("versions path is not a regular directory")
	}
	return path, nil
}

func readActiveState(root string) (activeState, error) {
	marker := filepath.Join(root, activeMarkerName)
	info, err := os.Lstat(marker)
	if errors.Is(err, os.ErrNotExist) {
		return activeState{Active: baseVersion}, nil
	}
	if err != nil {
		return activeState{}, fmt.Errorf("inspect active version marker: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > 512 {
		return activeState{}, errors.New("active version marker is not a valid HAWS-owned file")
	}
	contents, err := os.ReadFile(marker)
	if err != nil {
		return activeState{}, fmt.Errorf("read active version marker: %w", err)
	}
	contents = bytes.ReplaceAll(contents, []byte("\r\n"), []byte("\n"))
	lines := strings.Split(strings.TrimSuffix(string(contents), "\n"), "\n")
	if len(lines) != 3 || lines[0] != activeMarkerHeader || !strings.HasPrefix(lines[1], "active=") || !strings.HasPrefix(lines[2], "previous=") {
		return activeState{}, errors.New("active version marker is malformed or unowned")
	}
	state := activeState{Active: strings.TrimPrefix(lines[1], "active="), Previous: strings.TrimPrefix(lines[2], "previous=")}
	if !validStateVersion(state.Active, false) || !validStateVersion(state.Previous, true) {
		return activeState{}, errors.New("active version marker contains an invalid version")
	}
	return state, nil
}

func validStateVersion(version string, allowEmpty bool) bool {
	if version == "" {
		return allowEmpty
	}
	return version == baseVersion || validInstallVersion(version)
}

func writeActiveState(root string, state activeState) error {
	if !validStateVersion(state.Active, false) || !validStateVersion(state.Previous, true) {
		return errors.New("refusing to write an invalid active version marker")
	}
	marker := filepath.Join(root, activeMarkerName)
	if info, err := os.Lstat(marker); err == nil {
		if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
			return errors.New("refusing to replace an unowned active version marker")
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect active version marker before activation: %w", err)
	}

	temp, err := os.CreateTemp(root, ".active-version-*.tmp")
	if err != nil {
		return fmt.Errorf("create active version marker: %w", err)
	}
	tempName := temp.Name()
	defer os.Remove(tempName)
	contents := fmt.Sprintf("%s\nactive=%s\nprevious=%s\n", activeMarkerHeader, state.Active, state.Previous)
	if _, err := io.WriteString(temp, contents); err != nil {
		_ = temp.Close()
		return fmt.Errorf("write active version marker: %w", err)
	}
	if err := temp.Sync(); err != nil {
		_ = temp.Close()
		return fmt.Errorf("sync active version marker: %w", err)
	}
	if err := temp.Close(); err != nil {
		return fmt.Errorf("close active version marker: %w", err)
	}
	if err := os.Rename(tempName, marker); err != nil {
		return fmt.Errorf("activate HAWS version: %w", err)
	}
	return nil
}

func validateBasePackage(root string, spec platformSpec) error {
	for _, arch := range []string{"amd64", "arm64"} {
		if _, err := validateGoBinary(binaryPath(root, spec, arch), spec.goos, arch); err != nil {
			return fmt.Errorf("invalid base %s binary: %w", arch, err)
		}
	}
	return nil
}

func validateVersionBinaries(versionDir string, spec platformSpec) (map[string]string, error) {
	hashes := make(map[string]string, 2)
	for _, arch := range []string{"amd64", "arm64"} {
		hash, err := validateGoBinary(binaryPath(versionDir, spec, arch), spec.goos, arch)
		if err != nil {
			return nil, fmt.Errorf("invalid %s/%s HAWS binary: %w", spec.packageOS, arch, err)
		}
		hashes[arch] = hash
	}
	return hashes, nil
}

func validateGoBinary(filename, goos, goarch string) (string, error) {
	info, err := os.Lstat(filename)
	if err != nil {
		return "", err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxInstalledBinary {
		return "", errors.New("binary is not a bounded regular file")
	}
	build, err := buildinfo.ReadFile(filename)
	if err != nil {
		return "", fmt.Errorf("read Go build information: %w", err)
	}
	if build.Path != "github.com/apirak-k/Human-AI-Working-Standard/cmd/haws" {
		return "", errors.New("binary is not the HAWS application")
	}
	settings := make(map[string]string, len(build.Settings))
	for _, setting := range build.Settings {
		settings[setting.Key] = setting.Value
	}
	if settings["GOOS"] != goos || settings["GOARCH"] != goarch {
		return "", fmt.Errorf("binary target is %s/%s, expected %s/%s", settings["GOOS"], settings["GOARCH"], goos, goarch)
	}
	data, err := os.ReadFile(filename)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:]), nil
}

func binaryPath(root string, spec platformSpec, arch string) string {
	name := "haws" + spec.extension
	return filepath.Join(root, "bin", spec.packageOS+"-"+arch, name)
}

func writeInstallManifest(versionDir string, manifest installManifest) error {
	contents, err := json.Marshal(manifest)
	if err != nil {
		return fmt.Errorf("encode installed version manifest: %w", err)
	}
	filename := filepath.Join(versionDir, "install.json")
	file, err := os.OpenFile(filename, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create installed version manifest: %w", err)
	}
	if _, err := file.Write(contents); err != nil {
		_ = file.Close()
		return fmt.Errorf("write installed version manifest: %w", err)
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return fmt.Errorf("sync installed version manifest: %w", err)
	}
	if err := file.Close(); err != nil {
		return fmt.Errorf("close installed version manifest: %w", err)
	}
	return nil
}

func readInstallManifest(versionDir, version string, spec platformSpec) (installManifest, error) {
	filename := filepath.Join(versionDir, "install.json")
	info, err := os.Lstat(filename)
	if err != nil {
		return installManifest{}, fmt.Errorf("inspect installed version manifest: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > 16<<10 {
		return installManifest{}, errors.New("installed version manifest is not a bounded regular file")
	}
	contents, err := os.ReadFile(filename)
	if err != nil {
		return installManifest{}, fmt.Errorf("read installed version manifest: %w", err)
	}
	var manifest installManifest
	if err := json.Unmarshal(contents, &manifest); err != nil {
		return installManifest{}, fmt.Errorf("decode installed version manifest: %w", err)
	}
	if manifest.Version != version || manifest.Platform != spec.packageOS || !isSHA256Hex(manifest.ArchiveSHA256) || len(manifest.Binaries) != 2 {
		return installManifest{}, errors.New("installed version manifest does not match the requested version")
	}
	actualHashes, err := validateVersionBinaries(versionDir, spec)
	if err != nil {
		return installManifest{}, err
	}
	for arch, hash := range actualHashes {
		if manifest.Binaries[arch] != hash {
			return installManifest{}, fmt.Errorf("installed %s binary fingerprint does not match its manifest", arch)
		}
	}
	return manifest, nil
}

func validateInstalledVersion(root, version string, spec platformSpec) error {
	if !validInstallVersion(version) {
		return errors.New("active version is invalid")
	}
	versionsDir := filepath.Join(root, "versions")
	versionsInfo, err := os.Lstat(versionsDir)
	if err != nil {
		return err
	}
	if versionsInfo.Mode()&os.ModeSymlink != 0 || !versionsInfo.IsDir() {
		return errors.New("versions path is not a regular directory")
	}
	versionDir := filepath.Join(root, "versions", version)
	info, err := os.Lstat(versionDir)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return errors.New("active version path is not a regular directory")
	}
	if !ownedVersionTreeOnly(versionDir, spec) {
		return errors.New("active version contains unowned files or path types")
	}
	_, err = readInstallManifest(versionDir, version, spec)
	return err
}

func extractPackage(spec platformSpec, archive []byte, stageDir string) error {
	if int64(len(archive)) > maxAssetBytes {
		return errors.New("archive exceeds the size limit")
	}
	if spec.packageOS == "windows" {
		return extractZipPackage(spec, archive, stageDir)
	}
	return extractTarPackage(spec, archive, stageDir)
}

func extractZipPackage(spec platformSpec, archive []byte, stageDir string) error {
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return fmt.Errorf("open ZIP archive: %w", err)
	}
	seen := make(map[string]bool, len(reader.File))
	var total int64
	for _, file := range reader.File {
		name, err := cleanArchiveName(file.Name)
		if err != nil {
			return err
		}
		if seen[name] {
			return fmt.Errorf("archive contains duplicate path %q", name)
		}
		seen[name] = true
		mode := file.Mode()
		if mode&os.ModeSymlink != 0 || mode&os.ModeNamedPipe != 0 || mode&os.ModeDevice != 0 {
			return fmt.Errorf("archive contains unsupported file type at %q", name)
		}
		if file.FileInfo().IsDir() {
			if !allowedArchiveDirectory(spec, name) {
				return fmt.Errorf("archive contains unexpected directory %q", name)
			}
			continue
		}
		if !mode.IsRegular() || file.UncompressedSize64 > maxInstalledTotal {
			return fmt.Errorf("archive contains an invalid or oversized file %q", name)
		}
		total += int64(file.UncompressedSize64)
		if total > maxInstalledTotal {
			return errors.New("archive exceeds the total extracted size limit")
		}
		input, err := file.Open()
		if err != nil {
			return fmt.Errorf("open archive entry %q: %w", name, err)
		}
		contents, readErr := io.ReadAll(io.LimitReader(input, maxInstalledTotal+1))
		closeErr := input.Close()
		if readErr != nil {
			return fmt.Errorf("read archive entry %q: %w", name, readErr)
		}
		if closeErr != nil {
			return fmt.Errorf("close archive entry %q: %w", name, closeErr)
		}
		if uint64(len(contents)) != file.UncompressedSize64 {
			return fmt.Errorf("archive entry %q is truncated", name)
		}
		if err := acceptPackageFile(spec, stageDir, name, contents, seen); err != nil {
			return err
		}
	}
	return requirePackageFiles(spec, seen)
}

func extractTarPackage(spec platformSpec, archive []byte, stageDir string) error {
	gzipReader, err := gzip.NewReader(bytes.NewReader(archive))
	if err != nil {
		return fmt.Errorf("open gzip archive: %w", err)
	}
	defer gzipReader.Close()
	reader := tar.NewReader(gzipReader)
	seen := make(map[string]bool)
	var total int64
	for {
		header, err := reader.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("read TAR archive: %w", err)
		}
		name, err := cleanArchiveName(header.Name)
		if err != nil {
			return err
		}
		if seen[name] {
			return fmt.Errorf("archive contains duplicate path %q", name)
		}
		seen[name] = true
		switch header.Typeflag {
		case tar.TypeDir:
			if !allowedArchiveDirectory(spec, name) {
				return fmt.Errorf("archive contains unexpected directory %q", name)
			}
			continue
		case tar.TypeReg, tar.TypeRegA:
			if header.Size < 0 || header.Size > maxInstalledTotal {
				return fmt.Errorf("archive contains an oversized file %q", name)
			}
		default:
			return fmt.Errorf("archive contains an unsupported entry type at %q", name)
		}
		total += header.Size
		if total > maxInstalledTotal {
			return errors.New("archive exceeds the total extracted size limit")
		}
		contents, err := io.ReadAll(io.LimitReader(reader, maxInstalledTotal+1))
		if err != nil {
			return fmt.Errorf("read archive entry %q: %w", name, err)
		}
		if int64(len(contents)) != header.Size {
			return fmt.Errorf("archive entry %q is truncated", name)
		}
		if err := acceptPackageFile(spec, stageDir, name, contents, seen); err != nil {
			return err
		}
	}
	return requirePackageFiles(spec, seen)
}

func cleanArchiveName(name string) (string, error) {
	trimmed := strings.TrimSuffix(name, "/")
	if trimmed == "" || strings.ContainsRune(trimmed, 0) || strings.Contains(trimmed, "\\") || path.IsAbs(trimmed) {
		return "", fmt.Errorf("archive contains an unsafe path %q", name)
	}
	clean := path.Clean(trimmed)
	if clean != trimmed || clean == "." || clean == ".." || strings.HasPrefix(clean, "../") {
		return "", fmt.Errorf("archive contains an unsafe path %q", name)
	}
	return clean, nil
}

func allowedArchiveDirectory(spec platformSpec, name string) bool {
	prefix := "haws-go/" + spec.packageOS
	allowed := map[string]struct{}{
		"haws-go":       {},
		prefix:          {},
		prefix + "/bin": {},
		prefix + "/bin/" + spec.packageOS + "-amd64": {},
		prefix + "/bin/" + spec.packageOS + "-arm64": {},
	}
	_, ok := allowed[name]
	return ok
}

func acceptPackageFile(spec platformSpec, stageDir, name string, contents []byte, seen map[string]bool) error {
	prefix := "haws-go/" + spec.packageOS
	switch name {
	case prefix + "/README.txt":
		if len(contents) == 0 || len(contents) > maxControlFileBytes {
			return errors.New("package README is empty or oversized")
		}
		return nil
	case prefix + "/package-manifest.json":
		if len(contents) == 0 || len(contents) > maxControlFileBytes {
			return errors.New("package ownership manifest is empty or oversized")
		}
		return nil
	case prefix + "/" + spec.launcher:
		if len(contents) == 0 || len(contents) > maxControlFileBytes {
			return errors.New("package launcher is empty or oversized")
		}
		return nil
	}

	for _, arch := range []string{"amd64", "arm64"} {
		extension := ""
		if spec.packageOS == "windows" {
			extension = ".exe"
		}
		expected := prefix + "/bin/" + spec.packageOS + "-" + arch + "/haws" + extension
		if name != expected {
			continue
		}
		if len(contents) == 0 || int64(len(contents)) > maxInstalledBinary {
			return fmt.Errorf("package binary %s is empty or oversized", arch)
		}
		destination := filepath.Join(stageDir, "bin", spec.packageOS+"-"+arch, "haws"+extension)
		if err := os.MkdirAll(filepath.Dir(destination), 0o700); err != nil {
			return fmt.Errorf("create staged binary directory: %w", err)
		}
		if err := os.WriteFile(destination, contents, 0o700); err != nil {
			return fmt.Errorf("stage %s binary: %w", arch, err)
		}
		if err := os.Chmod(destination, 0o755); err != nil {
			return fmt.Errorf("set %s binary permissions: %w", arch, err)
		}
		return nil
	}
	return fmt.Errorf("archive contains an unexpected file %q", name)
}

func requirePackageFiles(spec platformSpec, seen map[string]bool) error {
	prefix := "haws-go/" + spec.packageOS
	required := []string{prefix + "/README.txt", prefix + "/package-manifest.json", prefix + "/" + spec.launcher}
	for _, arch := range []string{"amd64", "arm64"} {
		extension := ""
		if spec.packageOS == "windows" {
			extension = ".exe"
		}
		required = append(required, prefix+"/bin/"+spec.packageOS+"-"+arch+"/haws"+extension)
	}
	for _, name := range required {
		if !seen[name] {
			return fmt.Errorf("release package is missing %s", name)
		}
	}
	return nil
}
