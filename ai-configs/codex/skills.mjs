import { copyFileSync, cpSync, lstatSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { parseArgs } from 'node:util';

try {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { source: { type: 'string' }, target: { type: 'string' } },
  });
  if (positionals[0] !== 'graphify' || positionals.length !== 1 || !values.source || !values.target) {
    throw new Error('Usage: skills.mjs graphify --source PATH --target PATH');
  }
  const source = resolve(values.source);
  const target = resolve(values.target);
  const sourceSkill = join(source, 'skill-codex.md');
  const sourceReferences = join(source, 'skills', 'codex', 'references');
  const frontmatter = readFileSync(sourceSkill, 'utf8');
  if (!/^---\r?\nname:\s*graphify\r?$/m.test(frontmatter)) {
    throw new Error(`Invalid upstream Codex Graphify skill: ${sourceSkill}`);
  }
  try {
    const targetStat = lstatSync(target);
    if (!targetStat.isDirectory() || targetStat.isSymbolicLink()) {
      throw new Error(`Refusing linked or non-directory adapter target: ${target}`);
    }
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  mkdirSync(join(target, 'references'), { recursive: true });
  copyFileSync(sourceSkill, join(target, 'SKILL.md'));
  cpSync(sourceReferences, join(target, 'references'), { recursive: true, force: true });
  console.log(`OK: prepared Codex Graphify adapter (${target}).`);
} catch (error) {
  console.error(`HAWS Codex skills: ${error.message}`);
  process.exitCode = 1;
}
