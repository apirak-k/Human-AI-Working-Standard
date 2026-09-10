import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('./skills.mjs', import.meta.url));

test('installs the Codex-specific Graphify skill layout from a valid upstream source', t => {
  const root = mkdtempSync(join(tmpdir(), 'haws-codex-skill-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const graphify = join(root, 'graphify');
  const references = join(graphify, 'skills', 'codex', 'references');
  mkdirSync(references, { recursive: true });
  writeFileSync(join(graphify, 'skill-codex.md'), '---\nname: graphify\n---\n\nCodex instructions.\n');
  writeFileSync(join(references, 'extraction-spec.md'), 'Fixture extraction reference.\n');
  const target = join(root, 'adapter');
  const result = spawnSync(process.execPath, [helper, 'graphify', '--source', graphify, '--target', target], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(readFileSync(join(target, 'SKILL.md'), 'utf8'), /^name:\s*graphify$/m);
  assert.ok(readdirSync(join(target, 'references')).includes('extraction-spec.md'));
  assert.equal(readdirSync(target).includes('skill.md'), false);
  const repeated = spawnSync(process.execPath, [helper, 'graphify', '--source', graphify, '--target', target], { encoding: 'utf8' });
  assert.equal(repeated.status, 0, repeated.stdout + repeated.stderr);
});
