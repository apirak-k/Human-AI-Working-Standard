package settings

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func writeGeminiJSON(t *testing.T, path string, value any, mode os.FileMode) []byte {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	data = append(data, '\n')
	if err := os.WriteFile(path, data, mode); err != nil {
		t.Fatal(err)
	}
	return data
}

func readGeminiJSON(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var value map[string]any
	if err := json.Unmarshal(data, &value); err != nil {
		t.Fatalf("invalid JSON in %s: %v", path, err)
	}
	return value
}

func TestApplyGeminiSkillConfigPreservesUsersAndPrunesOnlyMissingCacheEntries(t *testing.T) {
	root := t.TempDir()
	state := filepath.Join(root, ".haws", "state")
	sourceRoot := filepath.Join(state, "skill-sources", "packs", "example")
	current := filepath.Join(sourceRoot, "current-skill")
	desired := filepath.Join(sourceRoot, "new-skill")
	stale := filepath.Join(sourceRoot, "removed-skill")
	userMissing := filepath.Join(root, "user-managed", "not-installed")
	customMissing := filepath.Join(sourceRoot, "custom", "not-installed")
	for _, path := range []string{current, desired} {
		if err := os.MkdirAll(path, 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(path, "SKILL.md"), []byte("fixture"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	config := filepath.Join(root, "skills.json")
	manifest := filepath.Join(state, "gemini-skills-ownership.json")
	candidate := filepath.Join(root, "candidate.json")
	originalConfig := writeGeminiJSON(t, config, map[string]any{
		"version": "user metadata",
		"entries": []any{
			map[string]any{"path": current},
			map[string]any{"path": stale},
			map[string]any{"path": userMissing},
			map[string]any{"path": customMissing, "label": "user-owned metadata"},
		},
	}, 0o640)
	writeGeminiJSON(t, manifest, map[string]any{"version": 1, "paths": []string{}, "createdTarget": false}, 0o600)
	writeGeminiJSON(t, candidate, map[string]any{"entries": []any{
		map[string]any{"path": current},
		map[string]any{"path": desired},
	}}, 0o600)

	result, err := ApplyGeminiSkillConfig(config, manifest, candidate, false)
	if err != nil {
		t.Fatal(err)
	}
	if result != (GeminiSkillConfigResult{Added: 1, Preserved: 3, Pruned: 1}) {
		t.Fatalf("apply result = %+v", result)
	}
	entries := readGeminiJSON(t, config)["entries"].([]any)
	if len(entries) != 4 {
		t.Fatalf("entries = %#v; want current, user, custom metadata, and desired", entries)
	}
	if !reflect.DeepEqual(entries[0], map[string]any{"path": current}) ||
		!reflect.DeepEqual(entries[1], map[string]any{"path": userMissing}) ||
		!reflect.DeepEqual(entries[2], map[string]any{"path": customMissing, "label": "user-owned metadata"}) ||
		!reflect.DeepEqual(entries[3], map[string]any{"path": desired}) {
		t.Fatalf("preserved entries/order = %#v", entries)
	}
	if got := readGeminiJSON(t, config)["version"]; got != "user metadata" {
		t.Fatalf("unrelated root property = %#v", got)
	}
	owned := readGeminiJSON(t, manifest)
	if !reflect.DeepEqual(owned["paths"], []any{desired}) || owned["createdTarget"] != false {
		t.Fatalf("ownership record = %#v", owned)
	}
	info, err := os.Stat(config)
	if err != nil || info.Mode().Perm() != 0o640 {
		t.Fatalf("config mode = %v, %v; want 0640", info, err)
	}
	if strings.Contains(string(originalConfig), "new-skill") {
		t.Fatal("fixture config unexpectedly contained desired entry")
	}
}

func TestApplyGeminiSkillConfigLeavesAmbiguousAndDecoratedEntriesUnowned(t *testing.T) {
	root := t.TempDir()
	config := filepath.Join(root, "skills.json")
	manifest := filepath.Join(root, "gemini-skills-ownership.json")
	candidate := filepath.Join(root, "candidate.json")
	duplicate := filepath.Join(root, "duplicate-skill")
	decorated := filepath.Join(root, "decorated-skill")
	writeGeminiJSON(t, config, map[string]any{"entries": []any{
		map[string]any{"path": duplicate},
		map[string]any{"path": duplicate},
		map[string]any{"path": decorated, "label": "keep"},
	}}, 0o600)
	writeGeminiJSON(t, manifest, map[string]any{"version": 1, "paths": []string{}}, 0o600)
	writeGeminiJSON(t, candidate, map[string]any{"entries": []any{
		map[string]any{"path": duplicate},
		map[string]any{"path": decorated},
	}}, 0o600)

	result, err := ApplyGeminiSkillConfig(config, manifest, candidate, false)
	if err != nil {
		t.Fatal(err)
	}
	if result.Added != 0 || result.Preserved != 3 || result.Pruned != 0 {
		t.Fatalf("result = %+v", result)
	}
	if _, err := os.Lstat(manifest); !os.IsNotExist(err) {
		t.Fatalf("ambiguous/user-owned entries created an ownership file: %v", err)
	}
}

func TestApplyGeminiSkillConfigRollsBackConfigWhenManifestWriteFails(t *testing.T) {
	root := t.TempDir()
	config := filepath.Join(root, "skills.json")
	manifest := filepath.Join(root, "missing-parent", "ownership.json")
	candidate := filepath.Join(root, "candidate.json")
	original := writeGeminiJSON(t, config, map[string]any{"entries": []any{}, "preserved": true}, 0o600)
	writeGeminiJSON(t, candidate, map[string]any{"entries": []any{map[string]any{"path": filepath.Join(root, "desired")}}}, 0o600)
	if _, err := ApplyGeminiSkillConfig(config, manifest, candidate, false); err == nil {
		t.Fatal("apply unexpectedly succeeded with an unavailable manifest directory")
	}
	got, err := os.ReadFile(config)
	if err != nil || string(got) != string(original) {
		t.Fatalf("config after failed commit = %q, %v; want original %q", got, err, original)
	}
	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), ".haws-gemini-skills-") {
			t.Fatalf("temporary file left behind: %s", entry.Name())
		}
	}
}

func TestAdoptGeminiSkillOwnershipRequiresUniqueExactLegacyMatches(t *testing.T) {
	root := t.TempDir()
	config := filepath.Join(root, "skills.json")
	manifest := filepath.Join(root, "state", "gemini-skills-ownership.json")
	candidate := filepath.Join(root, "candidate.json")
	legacyManifest := filepath.Join(root, "legacy-manifest")
	legacyMap := filepath.Join(root, "legacy-map.tsv")
	first := filepath.Join(root, "skills", "first")
	duplicate := filepath.Join(root, "skills", "duplicate")
	decorated := filepath.Join(root, "skills", "decorated")
	if err := os.MkdirAll(filepath.Dir(manifest), 0o700); err != nil {
		t.Fatal(err)
	}
	original := writeGeminiJSON(t, config, map[string]any{"entries": []any{
		map[string]any{"path": first},
		map[string]any{"path": duplicate},
		map[string]any{"path": duplicate},
		map[string]any{"path": decorated, "label": "user"},
	}}, 0o600)
	writeGeminiJSON(t, candidate, map[string]any{"entries": []any{
		map[string]any{"path": first},
		map[string]any{"path": duplicate},
		map[string]any{"path": decorated},
	}}, 0o600)
	if err := os.WriteFile(legacyManifest, []byte("agent:organizer\nskill:old\tfirst-target\nskill:duplicate-target\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(legacyMap, []byte(first+"\tfirst-target\n"+duplicate+"\tduplicate-target\n"+decorated+"\tdecorated-target\n"), 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := AdoptGeminiSkillOwnership(config, manifest, candidate, legacyManifest, legacyMap)
	if err != nil || result.Adopted != 1 || result.LegacyRecords != 2 {
		t.Fatalf("adopt = %+v, %v; want one unique exact match from two legacy records", result, err)
	}
	configAfter, err := os.ReadFile(config)
	if err != nil || string(configAfter) != string(original) {
		t.Fatalf("adoption changed skills config: %q, %v", configAfter, err)
	}
	owned := readGeminiJSON(t, manifest)
	if !reflect.DeepEqual(owned["paths"], []any{first}) || owned["createdTarget"] != false {
		t.Fatalf("adopted ownership = %#v", owned)
	}
}

func TestUninstallGeminiSkillConfigPreservesUserEntriesAndRemovesOwnedRoot(t *testing.T) {
	t.Run("preserves shared config", func(t *testing.T) {
		root := t.TempDir()
		config := filepath.Join(root, "skills.json")
		manifest := filepath.Join(root, "ownership.json")
		managed := filepath.Join(root, "managed")
		user := filepath.Join(root, "user")
		writeGeminiJSON(t, config, map[string]any{"entries": []any{
			map[string]any{"path": managed},
			map[string]any{"path": user},
			map[string]any{"path": managed},
		}, "userSetting": 7}, 0o600)
		writeGeminiJSON(t, manifest, map[string]any{"version": 1, "paths": []string{managed}, "createdTarget": false}, 0o600)
		result, err := UninstallGeminiSkillConfig(config, manifest)
		if err != nil {
			t.Fatal(err)
		}
		if result.Removed != 1 || result.Preserved != 2 {
			t.Fatalf("uninstall result = %+v", result)
		}
		entries := readGeminiJSON(t, config)["entries"].([]any)
		if len(entries) != 2 || entries[0].(map[string]any)["path"] != user || entries[1].(map[string]any)["path"] != managed {
			t.Fatalf("uninstall preserved entries = %#v", entries)
		}
		if _, err := os.Lstat(manifest); !os.IsNotExist(err) {
			t.Fatalf("ownership manifest remains: %v", err)
		}
	})

	t.Run("removes HAWS-created empty config", func(t *testing.T) {
		root := t.TempDir()
		config := filepath.Join(root, "skills.json")
		manifest := filepath.Join(root, "ownership.json")
		writeGeminiJSON(t, config, map[string]any{"entries": []any{map[string]any{"path": "/owned"}}}, 0o600)
		writeGeminiJSON(t, manifest, map[string]any{"version": 1, "paths": []string{"/owned"}, "createdTarget": true}, 0o600)
		if _, err := UninstallGeminiSkillConfig(config, manifest); err != nil {
			t.Fatal(err)
		}
		if _, err := os.Lstat(config); !os.IsNotExist(err) {
			t.Fatalf("HAWS-created empty config remains: %v", err)
		}
	})
}

func TestVerifyGeminiSkillConfigRejectsLinkedAndUnrecognizedFiles(t *testing.T) {
	t.Run("linked config", func(t *testing.T) {
		root := t.TempDir()
		target := filepath.Join(root, "target.json")
		if err := os.WriteFile(target, []byte(`{"entries":[]}`), 0o600); err != nil {
			t.Fatal(err)
		}
		link := filepath.Join(root, "link.json")
		if err := os.Symlink(target, link); err != nil {
			t.Skipf("symlink unavailable: %v", err)
		}
		if err := VerifyGeminiSkillConfig(link, filepath.Join(root, "manifest.json")); err == nil {
			t.Fatal("linked config was accepted")
		}
	})

	t.Run("unknown ownership schema", func(t *testing.T) {
		root := t.TempDir()
		config := filepath.Join(root, "skills.json")
		manifest := filepath.Join(root, "ownership.json")
		writeGeminiJSON(t, config, map[string]any{"entries": []any{}}, 0o600)
		writeGeminiJSON(t, manifest, map[string]any{"version": 2, "paths": []string{}}, 0o600)
		if err := VerifyGeminiSkillConfig(config, manifest); err == nil {
			t.Fatal("unknown ownership schema was accepted")
		}
	})
}
