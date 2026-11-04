package update

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
)

type fakeResponse struct {
	status   int
	body     []byte
	location string
	err      error
}

type fakeTransport func(*http.Request) (*http.Response, error)

func (f fakeTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}

type releaseAssetFixture struct {
	Name               string `json:"name"`
	BrowserDownloadURL string `json:"browser_download_url"`
	Size               int64  `json:"size"`
	Digest             string `json:"digest,omitempty"`
}

type releaseFixture struct {
	TagName    string                `json:"tag_name"`
	Draft      bool                  `json:"draft"`
	Prerelease bool                  `json:"prerelease"`
	Assets     []releaseAssetFixture `json:"assets"`
}

func makeReleaseMetadata(t *testing.T, tag, packageName string, packageBytes, checksumBytes []byte) []byte {
	t.Helper()
	digest := sha256.Sum256(packageBytes)
	assets := []releaseAssetFixture{
		{
			Name:               packageName,
			BrowserDownloadURL: releaseDownloadURL(tag, packageName),
			Size:               int64(len(packageBytes)),
			Digest:             fmt.Sprintf("sha256:%x", digest),
		},
		{
			Name:               packageName + ".sha256",
			BrowserDownloadURL: releaseDownloadURL(tag, packageName+".sha256"),
			Size:               int64(len(checksumBytes)),
		},
	}
	body, err := json.Marshal(releaseFixture{TagName: tag, Assets: assets})
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func makeChecksum(packageName string, contents []byte) []byte {
	digest := sha256.Sum256(contents)
	return []byte(fmt.Sprintf("%x  %s", digest, packageName))
}

func clientForRoutes(routes map[string]fakeResponse) *ReleaseClient {
	client := NewReleaseClient()
	checkRedirect := client.httpClient.CheckRedirect
	client.httpClient = &http.Client{
		Timeout:       client.httpClient.Timeout,
		CheckRedirect: checkRedirect,
		Transport: fakeTransport(func(req *http.Request) (*http.Response, error) {
			response, ok := routes[req.URL.String()]
			if !ok {
				return nil, fmt.Errorf("unexpected request %s", req.URL)
			}
			if response.err != nil {
				return nil, response.err
			}
			header := make(http.Header)
			if response.location != "" {
				header.Set("Location", response.location)
			}
			statusText := http.StatusText(response.status)
			return &http.Response{
				StatusCode:    response.status,
				Status:        fmt.Sprintf("%d %s", response.status, statusText),
				Header:        header,
				Body:          io.NopCloser(strings.NewReader(string(response.body))),
				ContentLength: int64(len(response.body)),
				Request:       req,
			}, nil
		}),
	}
	return client
}

func validRoutes(t *testing.T, goos string, tag string, packageBytes, checksumBytes []byte) map[string]fakeResponse {
	t.Helper()
	packageName, err := packageNameForOS(goos)
	if err != nil {
		t.Fatal(err)
	}
	metadataURL := latestReleaseURL
	assetURL := releaseDownloadURL(tag, packageName)
	checksumURL := releaseDownloadURL(tag, packageName+".sha256")
	return map[string]fakeResponse{
		metadataURL: {status: http.StatusOK, body: makeReleaseMetadata(t, tag, packageName, packageBytes, checksumBytes)},
		assetURL:    {status: http.StatusFound, location: "https://release-assets.githubusercontent.com/download/package"},
		"https://release-assets.githubusercontent.com/download/package": {status: http.StatusOK, body: packageBytes},
		checksumURL: {status: http.StatusOK, body: checksumBytes},
	}
}

func mutateReleaseFixture(t *testing.T, routes map[string]fakeResponse, mutate func(*releaseFixture)) {
	t.Helper()
	response := routes[latestReleaseURL]
	var metadata releaseFixture
	if err := json.Unmarshal(response.body, &metadata); err != nil {
		t.Fatal(err)
	}
	mutate(&metadata)
	response.body, _ = json.Marshal(metadata)
	routes[latestReleaseURL] = response
}

func TestDownloadLatestValidatesAndDownloadsPinnedPackage(t *testing.T) {
	packageBytes := []byte("release package fixture")
	packageName := "haws-linux.tar.gz"
	checksum := makeChecksum(packageName, packageBytes)
	routes := validRoutes(t, "linux", "v1.2.3", packageBytes, checksum)
	client := clientForRoutes(routes)
	client.httpClient.Transport = fakeTransport(func(req *http.Request) (*http.Response, error) {
		if req.URL.String() == latestReleaseURL {
			if req.Header.Get("Accept") != "application/vnd.github+json" {
				t.Errorf("API Accept = %q", req.Header.Get("Accept"))
			}
			if req.Header.Get("X-GitHub-Api-Version") != githubAPIVersion {
				t.Errorf("API version = %q", req.Header.Get("X-GitHub-Api-Version"))
			}
			if req.Header.Get("Authorization") != "" {
				t.Error("public release request unexpectedly sent credentials")
			}
		}
		response, ok := routes[req.URL.String()]
		if !ok {
			return nil, fmt.Errorf("unexpected request %s", req.URL)
		}
		if response.location != "" {
			return &http.Response{StatusCode: response.status, Header: http.Header{"Location": []string{response.location}}, Body: io.NopCloser(strings.NewReader("")), Request: req}, nil
		}
		return &http.Response{StatusCode: response.status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(string(response.body))), ContentLength: int64(len(response.body)), Request: req}, nil
	})

	got, err := client.DownloadLatest(context.Background(), "linux")
	if err != nil {
		t.Fatalf("DownloadLatest() error = %v", err)
	}
	if got.Version != "v1.2.3" || got.Name != packageName {
		t.Fatalf("release identity = %q/%q", got.Version, got.Name)
	}
	if string(got.Data) != string(packageBytes) {
		t.Fatalf("downloaded package = %q", got.Data)
	}
}

func TestDownloadLatestIfChangedAvoidsDownloadingAnActiveRelease(t *testing.T) {
	packageBytes := []byte("release package fixture")
	packageName := "haws-linux.tar.gz"
	routes := validRoutes(t, "linux", "v1.2.3", packageBytes, makeChecksum(packageName, packageBytes))
	client := clientForRoutes(routes)
	assetRequests := 0
	client.httpClient.Transport = fakeTransport(func(req *http.Request) (*http.Response, error) {
		if req.URL.String() != latestReleaseURL {
			assetRequests++
		}
		response, ok := routes[req.URL.String()]
		if !ok {
			return nil, fmt.Errorf("unexpected request %s", req.URL)
		}
		return &http.Response{
			StatusCode:    response.status,
			Header:        make(http.Header),
			Body:          io.NopCloser(strings.NewReader(string(response.body))),
			ContentLength: int64(len(response.body)),
			Request:       req,
		}, nil
	})

	got, changed, err := client.DownloadLatestIfChanged(context.Background(), "linux", "v1.2.3")
	if err != nil {
		t.Fatalf("DownloadLatestIfChanged() error = %v", err)
	}
	if changed || got.Version != "" || assetRequests != 0 {
		t.Fatalf("unchanged release result = %#v, changed=%v, asset requests=%d", got, changed, assetRequests)
	}
}

func TestDownloadLatestRejectsMetadataAndAssetFailures(t *testing.T) {
	packageBytes := []byte("release package fixture")
	packageName := "haws-linux.tar.gz"
	checksum := makeChecksum(packageName, packageBytes)
	base := validRoutes(t, "linux", "v1.2.3", packageBytes, checksum)

	tests := []struct {
		name   string
		mutate func(map[string]fakeResponse)
	}{
		{
			name: "metadata HTTP failure",
			mutate: func(routes map[string]fakeResponse) {
				routes[latestReleaseURL] = fakeResponse{status: http.StatusServiceUnavailable, body: []byte("unavailable")}
			},
		},
		{
			name: "malformed metadata",
			mutate: func(routes map[string]fakeResponse) {
				routes[latestReleaseURL] = fakeResponse{status: http.StatusOK, body: []byte("{")}
			},
		},
		{
			name: "draft release",
			mutate: func(routes map[string]fakeResponse) {
				mutateReleaseFixture(t, routes, func(metadata *releaseFixture) { metadata.Draft = true })
			},
		},
		{
			name: "prerelease",
			mutate: func(routes map[string]fakeResponse) {
				mutateReleaseFixture(t, routes, func(metadata *releaseFixture) { metadata.Prerelease = true })
			},
		},
		{
			name: "missing checksum asset",
			mutate: func(routes map[string]fakeResponse) {
				mutateReleaseFixture(t, routes, func(metadata *releaseFixture) { metadata.Assets = metadata.Assets[:1] })
			},
		},
		{
			name: "oversized archive metadata",
			mutate: func(routes map[string]fakeResponse) {
				mutateReleaseFixture(t, routes, func(metadata *releaseFixture) { metadata.Assets[0].Size = maxAssetBytes + 1 })
			},
		},
		{
			name: "invalid GitHub asset digest",
			mutate: func(routes map[string]fakeResponse) {
				mutateReleaseFixture(t, routes, func(metadata *releaseFixture) { metadata.Assets[0].Digest = "sha512:bad" })
			},
		},
		{
			name: "malformed checksum manifest",
			mutate: func(routes map[string]fakeResponse) {
				routes[releaseDownloadURL("v1.2.3", packageName+".sha256")] = fakeResponse{status: http.StatusOK, body: []byte("not a checksum")}
			},
		},
		{
			name: "checksum mismatch",
			mutate: func(routes map[string]fakeResponse) {
				routes[releaseDownloadURL("v1.2.3", packageName+".sha256")] = fakeResponse{status: http.StatusOK, body: makeChecksum(packageName, []byte("different package"))}
			},
		},
		{
			name: "truncated package body",
			mutate: func(routes map[string]fakeResponse) {
				metadata := makeReleaseMetadata(t, "v1.2.3", packageName, packageBytes, checksum)
				var decoded releaseFixture
				if err := json.Unmarshal(metadata, &decoded); err != nil {
					t.Fatal(err)
				}
				decoded.Assets[0].Size++
				body, _ := json.Marshal(decoded)
				routes[latestReleaseURL] = fakeResponse{status: http.StatusOK, body: body}
			},
		},
		{
			name: "package asset from untrusted host",
			mutate: func(routes map[string]fakeResponse) {
				metadata := makeReleaseMetadata(t, "v1.2.3", packageName, packageBytes, checksum)
				var decoded releaseFixture
				if err := json.Unmarshal(metadata, &decoded); err != nil {
					t.Fatal(err)
				}
				decoded.Assets[0].BrowserDownloadURL = "https://evil.example/haws-linux.tar.gz"
				body, _ := json.Marshal(decoded)
				routes[latestReleaseURL] = fakeResponse{status: http.StatusOK, body: body}
			},
		},
		{
			name: "redirect to non-HTTPS destination",
			mutate: func(routes map[string]fakeResponse) {
				routes[releaseDownloadURL("v1.2.3", packageName)] = fakeResponse{status: http.StatusFound, location: "http://127.0.0.1/private"}
			},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			routes := make(map[string]fakeResponse, len(base))
			for key, value := range base {
				routes[key] = value
			}
			test.mutate(routes)
			if _, err := clientForRoutes(routes).DownloadLatest(context.Background(), "linux"); err == nil {
				t.Fatal("DownloadLatest() unexpectedly succeeded")
			}
		})
	}
}

func TestDownloadLatestMapsDarwinToMacOSPackage(t *testing.T) {
	packageBytes := []byte("macOS archive")
	packageName := "haws-macos.tar.gz"
	routes := validRoutes(t, "darwin", "v3.0.0", packageBytes, makeChecksum(packageName, packageBytes))
	got, err := clientForRoutes(routes).DownloadLatest(context.Background(), "darwin")
	if err != nil {
		t.Fatalf("DownloadLatest() error = %v", err)
	}
	if got.Name != packageName {
		t.Fatalf("package name = %q, want %q", got.Name, packageName)
	}
}

func TestDownloadLatestRejectsUnsupportedPlatform(t *testing.T) {
	if _, err := NewReleaseClient().DownloadLatest(context.Background(), "plan9"); err == nil {
		t.Fatal("DownloadLatest() accepted an unsupported operating system")
	}
}
