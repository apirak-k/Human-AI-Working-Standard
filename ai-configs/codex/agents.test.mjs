import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, writeFileSync, existsSync, rmSync, symlinkSync, lstatSync, unlinkSync, copyFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./agents.mjs', import.meta.url));
const source = resolve(process.env.HAWS_TEST_SOURCE || join(dirname(script), '../..'));
const roles = ['backend-engineer', 'frontend-engineer', 'organizer', 'researcher', 'tester'];

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'haws-codex-agents-test-'));
  const home = join(root, 'codex home');
  t.after(() => {
    assert.ok(root.startsWith(resolve(tmpdir()) + sep));
    rmSync(root, { recursive: true, force: true });
  });
  return { root, home, agents: join(home, 'agents') };
}

function run(action, home, args = [], sourceRoot = source) {
  const result = spawnSync(process.execPath, [script, action, '--source', sourceRoot, '--codex-home', home, ...args], { encoding: 'utf8' });
  assert.ifError(result.error);
  return result;
}

function succeeds(result) {
  assert.equal(result.status, 0, result.stdout + result.stderr);
}

function contents(directory) {
  return Object.fromEntries(readdirSync(directory).sort().map(name => [name, readFileSync(join(directory, name), 'utf8')]));
}

test('install creates all five native profiles and check accepts them', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  assert.deepEqual(readdirSync(agents).sort(), roles.map(role => `${role}.toml`));
  for (const role of roles) {
    const profile = readFileSync(join(agents, `${role}.toml`), 'utf8');
    assert.match(profile, new RegExp(`^name\\s*=\\s*["']${role}["']`, 'm'));
    assert.match(profile, /^description\s*=/m);
    assert.match(profile, /^developer_instructions\s*=/m);
    assert.ok(profile.includes(`${role}.md`));
    assert.ok(profile.includes('HAWS.md'));
    assert.ok(profile.includes('SKILL.md'));
    assert.ok(profile.includes('task_report'));
    assert.doesNotMatch(profile, /^model\s*=/m);
  }
  assert.match(readFileSync(join(agents, 'researcher.toml'), 'utf8'), /^sandbox_mode\s*=\s*["']read-only["']/m);
  succeeds(run('check', home));
});

test('install is idempotent and preserves unrelated profiles', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  writeFileSync(join(agents, 'personal.toml'), 'name = "personal"\n');
  const before = contents(agents);
  succeeds(run('install', home));
  assert.deepEqual(contents(agents), before);
});

test('install dry-run creates no directories or files', t => {
  const { root, home } = fixture(t);
  succeeds(run('install', home, ['--dry-run']));
  assert.deepEqual(readdirSync(root), []);
});

test('check fails when profiles are absent and never writes', t => {
  const { root, home } = fixture(t);
  assert.notEqual(run('check', home).status, 0);
  assert.deepEqual(readdirSync(root), []);
});

test('check detects a deleted profile', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  unlinkSync(join(agents, 'tester.toml'));
  assert.notEqual(run('check', home).status, 0);
  assert.equal(existsSync(join(agents, 'tester.toml')), false);
});

test('check and install reject a modified profile without changing any files', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  writeFileSync(join(agents, 'tester.toml'), 'name = "my-tester"\n');
  const before = contents(agents);
  assert.notEqual(run('check', home).status, 0);
  assert.notEqual(run('install', home).status, 0);
  assert.deepEqual(contents(agents), before);
});

test('install preflights every conflict before creating other profiles', t => {
  const { home, agents } = fixture(t);
  mkdirSync(agents, { recursive: true });
  writeFileSync(join(agents, 'tester.toml'), 'name = "owned-by-user"\n');
  const before = contents(agents);
  assert.notEqual(run('install', home).status, 0);
  assert.deepEqual(contents(agents), before);
});

test('uninstall removes generated profiles and preserves unrelated files', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  writeFileSync(join(agents, 'personal.toml'), 'name = "personal"\n');
  succeeds(run('uninstall', home));
  assert.deepEqual(contents(agents), { 'personal.toml': 'name = "personal"\n' });
});

test('uninstall preserves modified profiles', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  writeFileSync(join(agents, 'tester.toml'), 'name = "user-edited"\n');
  run('uninstall', home);
  assert.equal(readFileSync(join(agents, 'tester.toml'), 'utf8'), 'name = "user-edited"\n');
});

test('uninstall dry-run preserves all installed profiles', t => {
  const { home, agents } = fixture(t);
  succeeds(run('install', home));
  const before = contents(agents);
  succeeds(run('uninstall', home, ['--dry-run']));
  assert.deepEqual(contents(agents), before);
});

test('install check and uninstall refuse linked profile destinations', t => {
  const { root, home, agents } = fixture(t);
  const external = join(root, 'user directory');
  mkdirSync(external);
  writeFileSync(join(external, 'valuable.txt'), 'preserve me');
  mkdirSync(agents, { recursive: true });
  const link = join(agents, 'tester.toml');
  symlinkSync(external, link, process.platform === 'win32' ? 'junction' : 'dir');
  assert.notEqual(run('install', home).status, 0);
  assert.notEqual(run('check', home).status, 0);
  run('uninstall', home);
  assert.ok(lstatSync(link).isSymbolicLink());
  assert.equal(readFileSync(join(external, 'valuable.txt'), 'utf8'), 'preserve me');
  assert.deepEqual(readdirSync(agents), ['tester.toml']);
});

test('install and check support source paths containing spaces', t => {
  const { root, home } = fixture(t);
  const sourceWithSpaces = join(root, 'HAWS source with spaces');
  symlinkSync(source, sourceWithSpaces, process.platform === 'win32' ? 'junction' : 'dir');
  succeeds(run('install', home, [], sourceWithSpaces));
  succeeds(run('check', home, [], sourceWithSpaces));
});

function copyRoles(root) {
  const copiedSource = join(root, 'canonical source');
  mkdirSync(join(copiedSource, 'agents'), { recursive: true });
  for (const role of roles) {
    copyFileSync(join(source, 'agents', `${role}.md`), join(copiedSource, 'agents', `${role}.md`));
  }
  return copiedSource;
}

function changeTesterDescription(copiedSource) {
  const roleFile = join(copiedSource, 'agents', 'tester.md');
  const previous = readFileSync(roleFile, 'utf8');
  const next = previous.replace(/^description:.*$/m, 'description: Updated canonical tester requirements for the next HAWS release.');
  assert.notEqual(next, previous);
  writeFileSync(roleFile, next);
}

test('install upgrades an unchanged generated profile after canonical role changes', t => {
  const { root, home, agents } = fixture(t);
  const copiedSource = copyRoles(root);
  succeeds(run('install', home, [], copiedSource));
  const originalProfile = readFileSync(join(agents, 'tester.toml'), 'utf8');
  changeTesterDescription(copiedSource);
  succeeds(run('install', home, [], copiedSource));
  const upgradedProfile = readFileSync(join(agents, 'tester.toml'), 'utf8');
  assert.notEqual(upgradedProfile, originalProfile);
  assert.ok(upgradedProfile.includes('Updated canonical tester requirements'));
  succeeds(run('check', home, [], copiedSource));
  succeeds(run('uninstall', home, [], copiedSource));
  for (const role of roles) assert.equal(existsSync(join(agents, `${role}.toml`)), false);
});

test('a source upgrade preserves a user-edited older profile during install and uninstall', t => {
  const { root, home, agents } = fixture(t);
  const copiedSource = copyRoles(root);
  succeeds(run('install', home, [], copiedSource));
  const profileFile = join(agents, 'tester.toml');
  const userContent = readFileSync(profileFile, 'utf8') + '\n# My personal tester settings\n';
  writeFileSync(profileFile, userContent);
  const before = contents(agents);
  changeTesterDescription(copiedSource);
  assert.notEqual(run('install', home, [], copiedSource).status, 0);
  assert.deepEqual(contents(agents), before);
  run('uninstall', home, [], copiedSource);
  assert.equal(readFileSync(profileFile, 'utf8'), userContent);
});
