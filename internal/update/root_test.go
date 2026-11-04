package update

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func TestFindInstallRootFromBaseAndVersionedBinaries(t *testing.T) {
	spec, err := platformForOS(runtime.GOOS)
	if err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, spec.launcher), []byte("launcher"), 0o700); err != nil {
		t.Fatal(err)
	}
	wantRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, relative := range []string{
		filepath.Join("bin", spec.packageOS+"-amd64", "haws"+spec.extension),
		filepath.Join("versions", "v1.2.3", "bin", spec.packageOS+"-arm64", "haws"+spec.extension),
	} {
		executable := filepath.Join(root, relative)
		if err := os.MkdirAll(filepath.Dir(executable), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(executable, []byte("fixture"), 0o700); err != nil {
			t.Fatal(err)
		}
		got, err := FindInstallRoot(executable, runtime.GOOS)
		if err != nil || got != wantRoot {
			t.Fatalf("FindInstallRoot(%q) = %q, %v; want %q", relative, got, err, wantRoot)
		}
	}
}

func TestFindInstallRootRejectsUnpackagedExecutable(t *testing.T) {
	executable := filepath.Join(t.TempDir(), "haws")
	if err := os.WriteFile(executable, []byte("fixture"), 0o700); err != nil {
		t.Fatal(err)
	}
	if _, err := FindInstallRoot(executable, runtime.GOOS); err == nil {
		t.Fatal("FindInstallRoot() accepted an executable without its package launcher")
	}
}
