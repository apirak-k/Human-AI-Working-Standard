import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const toolPath = fileURLToPath(new URL('../../ai-configs/gemini/skills-json.mjs', import.meta.url));

function writeJson(path, value) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function makeSkill(path) {
  mkdirSync(path, { recursive: true });
  writeFileSync(join(path, 'SKILL.md'), '---\nname: fixture\ndescription: fixture\n---\n');
}

function applyFixture(root, entries, desiredPaths) {
  const state = join(root, '.haws', 'state');
  const config = join(root, 'skills.json');
  const ownership = join(state, 'gemini-skills-ownership.json');
  const candidate = join(root, 'candidate.json');
  writeJson(config, { entries });
  writeJson(ownership, { version: 1, paths: [] });
  writeJson(candidate, { entries: desiredPaths.map(path => ({ path })) });

  const result = spawnSync(process.execPath, [toolPath, 'apply', config, ownership, candidate], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  return {
    config: JSON.parse(readFileSync(config, 'utf8')),
    output: result.stdout,
    ownership: existsSync(ownership)
      ? JSON.parse(readFileSync(ownership, 'utf8'))
      : { version: 1, paths: [] },
  };
}

const root = mkdtempSync(join(tmpdir(), 'haws-gemini-skills-json-fixture-'));
try {
  const sourceRoot = join(root, '.haws', 'state', 'skill-sources', 'packs', 'example');
  const existing = join(sourceRoot, 'current-skill');
  const desired = join(sourceRoot, 'new-skill');
  const stale = join(sourceRoot, 'removed-skill');
  const userMissing = join(root, 'user-managed', 'not-installed');
  const customMissing = join(sourceRoot, 'custom', 'not-installed');
  makeSkill(existing);
  makeSkill(desired);

  const result = applyFixture(root, [
    { path: existing },
    { path: stale },
    { path: userMissing },
    { path: customMissing, label: 'user-owned metadata' },
  ], [existing, desired]);
  try {
    assert.deepEqual(result.config.entries, [
      { path: existing },
      { path: userMissing },
      { path: customMissing, label: 'user-owned metadata' },
      { path: desired },
    ]);
    assert.deepEqual(result.ownership.paths, [desired]);
    assert.doesNotMatch(result.output, /adopted/);
    assert.match(result.output, /pruned 1 missing HAWS skill source entr/);
    assert.match(result.output, /preserved 3 existing entr/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }

  const duplicateRoot = mkdtempSync(join(tmpdir(), 'haws-gemini-skills-json-duplicate-'));
  const duplicatePath = join(duplicateRoot, '.haws', 'state', 'skill-sources', 'packs', 'duplicate');
  makeSkill(duplicatePath);
  const duplicate = applyFixture(
    duplicateRoot,
    [{ path: duplicatePath }, { path: duplicatePath }],
    [duplicatePath],
  );
  try {
    assert.deepEqual(duplicate.config.entries, [{ path: duplicatePath }, { path: duplicatePath }]);
    assert.deepEqual(duplicate.ownership.paths, []);
    assert.match(duplicate.output, /preserved 2 existing entr/);
    assert.doesNotMatch(duplicate.output, /adopted/);
  } finally {
    rmSync(duplicateRoot, { recursive: true, force: true });
  }

  console.log('PASS Antigravity skill config preserves user links and prunes only missing HAWS cache entries');
} finally {
  rmSync(root, { recursive: true, force: true });
}
