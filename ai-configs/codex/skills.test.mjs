import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('./skills.mjs', import.meta.url));
const graphify = fileURLToPath(new URL('../../skills/standalone/graphify/graphify/', import.meta.url));

test('installs the upstream Codex-specific Graphify skill layout', t => {
  const root = mkdtempSync(join(tmpdir(), 'haws-codex-skill-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const result = spawnSync(process.execPath, [helper, 'graphify', '--source', graphify, '--target', root], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(readFileSync(join(root, 'SKILL.md'), 'utf8'), /^name:\s*graphify$/m);
  assert.ok(readdirSync(join(root, 'references')).includes('extraction-spec.md'));
  assert.equal(readdirSync(root).includes('skill.md'), false);
  const repeated = spawnSync(process.execPath, [helper, 'graphify', '--source', graphify, '--target', root], { encoding: 'utf8' });
  assert.equal(repeated.status, 0, repeated.stdout + repeated.stderr);
});
