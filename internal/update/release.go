package update

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	githubOwner      = "apirak-k"
	githubRepository = "Human-AI-Working-Standard"
	githubAPIVersion = "2026-03-10"
	latestReleaseURL = "https://api.github.com/repos/apirak-k/Human-AI-Working-Standard/releases/latest"
	maxMetadataBytes = 2 << 20
	maxAssetBytes    = 128 << 20
	maxChecksumBytes = 4 << 10
	maxRedirects     = 5
)

var allowedGitHubHosts = map[string]struct{}{
	"api.github.com":                        {},
	"github.com":                            {},
	"release-assets.githubusercontent.com":  {},
	"objects.githubusercontent.com":         {},
	"objects-origin.githubusercontent.com":  {},
	"github-releases.githubusercontent.com": {},
}

type ReleasePackage struct {
	Version string
	Name    string
	Data    []byte
	SHA256  string
}

type ReleaseClient struct {
	httpClient *http.Client
}

type releaseMetadata struct {
	TagName    string         `json:"tag_name"`
	Draft      bool           `json:"draft"`
	Prerelease bool           `json:"prerelease"`
	Assets     []releaseAsset `json:"assets"`
}

type releaseAsset struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
	Digest             string `json:"digest"`
}

type latestRelease struct {
	version       string
	packageName   string
	archiveAsset  releaseAsset
	checksumAsset releaseAsset
}

func NewReleaseClient() *ReleaseClient {
	return &ReleaseClient{httpClient: &http.Client{
		Timeout:       30 * time.Second,
		CheckRedirect: checkGitHubRedirect,
	}}
}

func (c *ReleaseClient) DownloadLatest(ctx context.Context, goos string) (ReleasePackage, error) {
	latest, err := c.latestRelease(ctx, goos)
	if err != nil {
		return ReleasePackage{}, err
	}
	return c.downloadRelease(ctx, latest)
}

// DownloadLatestIfChanged checks only release metadata when the active version
// already matches, avoiding a large package download on every Sync.
func (c *ReleaseClient) DownloadLatestIfChanged(ctx context.Context, goos, activeVersion string) (ReleasePackage, bool, error) {
	latest, err := c.latestRelease(ctx, goos)
	if err != nil {
		return ReleasePackage{}, false, err
	}
	if latest.version == activeVersion {
		return ReleasePackage{}, false, nil
	}
	packageData, err := c.downloadRelease(ctx, latest)
	if err != nil {
		return ReleasePackage{}, false, err
	}
	return packageData, true, nil
}

func (c *ReleaseClient) latestRelease(ctx context.Context, goos string) (latestRelease, error) {
	if c == nil || c.httpClient == nil {
		return latestRelease{}, errors.New("release client is not configured")
	}
	packageName, err := packageNameForOS(goos)
	if err != nil {
		return latestRelease{}, err
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, latestReleaseURL, nil)
	if err != nil {
		return latestRelease{}, fmt.Errorf("create latest release request: %w", err)
	}
	request.Header.Set("Accept", "application/vnd.github+json")
	request.Header.Set("X-GitHub-Api-Version", githubAPIVersion)
	request.Header.Set("User-Agent", "HAWS-Go-Update")

	response, err := c.httpClient.Do(request)
	if err != nil {
		return latestRelease{}, fmt.Errorf("request latest HAWS release: %w", err)
	}
	defer response.Body.Close()
	metadataBytes, err := readResponseBody(response, maxMetadataBytes)
	if err != nil {
		return latestRelease{}, fmt.Errorf("read latest HAWS release: %w", err)
	}
	if response.StatusCode != http.StatusOK {
		return latestRelease{}, fmt.Errorf("latest HAWS release returned HTTP %d", response.StatusCode)
	}

	var metadata releaseMetadata
	if err := json.Unmarshal(metadataBytes, &metadata); err != nil {
		return latestRelease{}, fmt.Errorf("decode latest HAWS release: %w", err)
	}
	if !validVersion(metadata.TagName) {
		return latestRelease{}, errors.New("latest HAWS release has an invalid version tag")
	}
	if metadata.Draft || metadata.Prerelease {
		return latestRelease{}, errors.New("latest HAWS release is not a stable published release")
	}

	archiveAsset, checksumAsset, err := findReleaseAssets(metadata.Assets, metadata.TagName, packageName)
	if err != nil {
		return latestRelease{}, err
	}
	return latestRelease{
		version:       metadata.TagName,
		packageName:   packageName,
		archiveAsset:  archiveAsset,
		checksumAsset: checksumAsset,
	}, nil
}

func (c *ReleaseClient) downloadRelease(ctx context.Context, latest latestRelease) (ReleasePackage, error) {
	archiveBytes, err := c.downloadAsset(ctx, latest.archiveAsset, maxAssetBytes)
	if err != nil {
		return ReleasePackage{}, fmt.Errorf("download %s: %w", latest.packageName, err)
	}
	checksumBytes, err := c.downloadAsset(ctx, latest.checksumAsset, maxChecksumBytes)
	if err != nil {
		return ReleasePackage{}, fmt.Errorf("download %s checksum: %w", latest.packageName, err)
	}

	expectedHash, err := parseChecksumManifest(checksumBytes, latest.packageName)
	if err != nil {
		return ReleasePackage{}, err
	}
	actualDigest := sha256.Sum256(archiveBytes)
	actualHash := hex.EncodeToString(actualDigest[:])
	if actualHash != expectedHash {
		return ReleasePackage{}, errors.New("release package SHA-256 does not match its checksum manifest")
	}
	if latest.archiveAsset.Digest != "" {
		apiHash, err := parseAPIDigest(latest.archiveAsset.Digest)
		if err != nil {
			return ReleasePackage{}, err
		}
		if apiHash != actualHash {
			return ReleasePackage{}, errors.New("release package SHA-256 does not match the GitHub release asset digest")
		}
	}

	return ReleasePackage{Version: latest.version, Name: latest.packageName, Data: archiveBytes, SHA256: actualHash}, nil
}

func packageNameForOS(goos string) (string, error) {
	switch goos {
	case "windows":
		return "haws-windows.zip", nil
	case "darwin", "macos":
		return "haws-macos.tar.gz", nil
	case "linux":
		return "haws-linux.tar.gz", nil
	default:
		return "", fmt.Errorf("unsupported HAWS release platform %q", goos)
	}
}

func releaseDownloadURL(tag, name string) string {
	return "https://github.com/" + githubOwner + "/" + githubRepository + "/releases/download/" + url.PathEscape(tag) + "/" + url.PathEscape(name)
}

func findReleaseAssets(assets []releaseAsset, tag, packageName string) (releaseAsset, releaseAsset, error) {
	if len(assets) > 64 {
		return releaseAsset{}, releaseAsset{}, errors.New("latest HAWS release has too many assets")
	}
	archiveName := packageName
	checksumName := packageName + ".sha256"
	seen := make(map[string]struct{}, len(assets))
	var archive, checksum releaseAsset
	for _, asset := range assets {
		if asset.Name == "" {
			return releaseAsset{}, releaseAsset{}, errors.New("latest HAWS release contains an unnamed asset")
		}
		if _, exists := seen[asset.Name]; exists {
			return releaseAsset{}, releaseAsset{}, fmt.Errorf("latest HAWS release contains duplicate asset %q", asset.Name)
		}
		seen[asset.Name] = struct{}{}
		if asset.Name != archiveName && asset.Name != checksumName {
			continue
		}
		if asset.BrowserDownloadURL != releaseDownloadURL(tag, asset.Name) {
			return releaseAsset{}, releaseAsset{}, fmt.Errorf("release asset %q has an untrusted download URL", asset.Name)
		}
		if asset.Size <= 0 {
			return releaseAsset{}, releaseAsset{}, fmt.Errorf("release asset %q has an invalid size", asset.Name)
		}
		if asset.Name == archiveName {
			if asset.Size > maxAssetBytes {
				return releaseAsset{}, releaseAsset{}, fmt.Errorf("release asset %q exceeds the size limit", asset.Name)
			}
			archive = asset
		} else {
			if asset.Size > maxChecksumBytes {
				return releaseAsset{}, releaseAsset{}, fmt.Errorf("release asset %q exceeds the size limit", asset.Name)
			}
			checksum = asset
		}
	}
	if archive.Name == "" || checksum.Name == "" {
		return releaseAsset{}, releaseAsset{}, errors.New("latest HAWS release is missing the platform package or its SHA-256 manifest")
	}
	return archive, checksum, nil
}

func (c *ReleaseClient) downloadAsset(ctx context.Context, asset releaseAsset, limit int64) ([]byte, error) {
	if err := validateGitHubURL(asset.BrowserDownloadURL); err != nil {
		return nil, err
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, asset.BrowserDownloadURL, nil)
	if err != nil {
		return nil, fmt.Errorf("create asset request: %w", err)
	}
	request.Header.Set("Accept", "application/octet-stream")
	request.Header.Set("User-Agent", "HAWS-Go-Update")
	response, err := c.httpClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("HTTP %d", response.StatusCode)
	}
	if response.ContentLength > limit {
		return nil, errors.New("response exceeds the size limit")
	}
	body, err := readResponseBody(response, limit)
	if err != nil {
		return nil, err
	}
	if int64(len(body)) != asset.Size {
		return nil, fmt.Errorf("download size %d does not match release metadata size %d", len(body), asset.Size)
	}
	return body, nil
}

func readResponseBody(response *http.Response, limit int64) ([]byte, error) {
	if response.ContentLength > limit {
		return nil, errors.New("response exceeds the size limit")
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(body)) > limit {
		return nil, errors.New("response exceeds the size limit")
	}
	return body, nil
}

func parseChecksumManifest(contents []byte, expectedName string) (string, error) {
	lines := strings.Split(strings.TrimSpace(string(contents)), "\n")
	if len(lines) != 1 {
		return "", errors.New("release checksum manifest must contain exactly one entry")
	}
	fields := strings.Fields(strings.TrimSuffix(strings.TrimSpace(lines[0]), "\r"))
	if len(fields) != 2 || fields[1] != expectedName || !isSHA256Hex(fields[0]) {
		return "", errors.New("release checksum manifest has an invalid entry")
	}
	return strings.ToLower(fields[0]), nil
}

func parseAPIDigest(value string) (string, error) {
	algorithm, digest, ok := strings.Cut(value, ":")
	if !ok || algorithm != "sha256" || !isSHA256Hex(digest) {
		return "", errors.New("GitHub release asset has an invalid SHA-256 digest")
	}
	return strings.ToLower(digest), nil
}

func isSHA256Hex(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func validVersion(value string) bool {
	if value == "" {
		return false
	}
	for index, char := range value {
		if char > 127 {
			return false
		}
		ascii := byte(char)
		if index == 0 && !isASCIIAlphaNumeric(ascii) {
			return false
		}
		if !isASCIIAlphaNumeric(ascii) && char != '.' && char != '_' && char != '+' && char != '-' {
			return false
		}
	}
	return true
}

func isASCIIAlphaNumeric(value byte) bool {
	return value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9'
}

func checkGitHubRedirect(request *http.Request, via []*http.Request) error {
	if len(via) >= maxRedirects {
		return errors.New("too many GitHub redirects")
	}
	return validateGitHubURL(request.URL.String())
}

func validateGitHubURL(raw string) error {
	parsed, err := url.Parse(raw)
	if err != nil {
		return errors.New("invalid GitHub URL")
	}
	if parsed.Scheme != "https" || parsed.User != nil || parsed.Hostname() == "" || parsed.Port() != "" && parsed.Port() != "443" {
		return errors.New("GitHub requests must use HTTPS without credentials or custom ports")
	}
	if _, ok := allowedGitHubHosts[strings.ToLower(parsed.Hostname())]; !ok {
		return fmt.Errorf("GitHub request redirected to an untrusted host %q", parsed.Hostname())
	}
	return nil
}
