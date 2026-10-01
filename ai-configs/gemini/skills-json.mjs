import {
  lstatSync,
  readFileSync,
  writeFileSync,
  renameSync,
  unlinkSync,
} from 'node:fs';
import { randomUUID } from 'node:crypto';

const [command, file, manifestFile, candidateFile, option, legacyCandidateFile] = process.argv.slice(2);

function stat(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error.code === 'ENOENT') return undefined;
    throw error;
  }
}

function readJsonFile(path, fallback, label) {
  const info = stat(path);
  if (!info) return { info: undefined, value: fallback, bytes: undefined };
  if (!info.isFile() || info.isSymbolicLink()) {
    throw new Error(`Preserving linked or non-file ${label}: ${path}`);
  }
  const bytes = readFileSync(path);
  let value;
  try {
    value = JSON.parse(bytes.toString('utf8'));
  } catch {
    throw new Error(`Preserving invalid JSON ${label}: ${path}`);
  }
  return { info, value, bytes };
}

function readRoot(path) {
  const { info, value, bytes } = readJsonFile(path, { entries: [] }, 'skills config');
  if (!value || Array.isArray(value) || typeof value !== 'object' || !Array.isArray(value.entries)) {
    throw new Error(`Preserving unsupported skills config structure: ${path}`);
  }
  return { info, value, bytes };
}

function readManifest(path) {
  const { info, value, bytes } = readJsonFile(path, { version: 1, paths: [] }, 'ownership record');
  if (value.version !== 1 || !Array.isArray(value.paths) ||
      value.paths.some(item => typeof item !== 'string') ||
      (value.createdTarget !== undefined && typeof value.createdTarget !== 'boolean')) {
    throw new Error(`Preserving unrecognized ownership record: ${path}`);
  }
  return { info, value, bytes };
}

function writeAtomic(path, contents, mode) {
  const temporary = `${path}.tmp-${process.pid}-${randomUUID()}`;
  let created = false;
  try {
    writeFileSync(temporary, contents, { mode, flag: 'wx' });
    created = true;
    renameSync(temporary, path);
    created = false;
  } catch (error) {
    if (created) {
      try { unlinkSync(temporary); } catch {}
    }
    throw error;
  }
}

function restore(path, previous, defaultMode = 0o600) {
  if (previous.bytes === undefined) {
    const current = stat(path);
    if (current) unlinkSync(path);
    return;
  }
  writeAtomic(path, previous.bytes, previous.info?.mode & 0o777 || defaultMode);
}

function commit(filePath, rootState, manifestPath, manifestState, nextRoot, nextPaths,
  createdTarget = false, removeCreatedRoot = false) {
  const oldRoot = { info: rootState.info, bytes: rootState.bytes };
  const oldManifest = { info: manifestState.info, bytes: manifestState.bytes };
  const rootText = `${JSON.stringify(nextRoot, null, 2)}\n`;
  const manifestText = nextPaths.length
    ? `${JSON.stringify({ version: 1, paths: nextPaths, createdTarget }, null, 2)}\n`
    : undefined;
  try {
    if (removeCreatedRoot && oldRoot.bytes !== undefined) {
      unlinkSync(filePath);
    } else if (rootText !== oldRoot.bytes?.toString('utf8') &&
        !(oldRoot.bytes === undefined && nextRoot.entries.length === 0)) {
      writeAtomic(filePath, rootText, rootState.info?.mode & 0o777 || 0o644);
    }
    if (manifestText === undefined) {
      if (manifestState.info) unlinkSync(manifestPath);
    } else if (manifestText !== oldManifest.bytes?.toString('utf8')) {
      writeAtomic(manifestPath, manifestText, manifestState.info?.mode & 0o777 || 0o600);
    }
  } catch (error) {
    restore(filePath, oldRoot, 0o644);
    restore(manifestPath, oldManifest, 0o600);
    throw error;
  }
}

function isPlainManagedEntry(entry, paths) {
  return entry && !Array.isArray(entry) && typeof entry === 'object' &&
    typeof entry.path === 'string' && paths.has(entry.path) &&
    Object.keys(entry).length === 1;
}

function splitManagedEntries(entries, ownedPaths) {
  const remaining = new Set(ownedPaths);
  const preserved = [];
  for (const entry of entries) {
    const path = entry && typeof entry === 'object' && !Array.isArray(entry)
      ? entry.path
      : undefined;
    if (typeof path === 'string' && remaining.has(path) &&
        isPlainManagedEntry(entry, remaining)) {
      remaining.delete(path);
    } else {
      preserved.push(entry);
    }
  }
  return preserved;
}

try {
  if (!['adopt', 'apply', 'uninstall', 'verify'].includes(command) || !file || !manifestFile ||
      (['adopt', 'apply'].includes(command) && !candidateFile)) {
    throw new Error('Usage: skills-json.mjs adopt <file> <manifest> <candidate> <legacy-manifest> <legacy-skill-map> | apply <file> <manifest> <candidate> | uninstall <file> <manifest>');
  }

  const rootState = readRoot(file);
  const manifestState = readManifest(manifestFile);

  if (command === 'adopt') {
    const legacyManifestFile = option;
    if (!legacyManifestFile || !legacyCandidateFile || manifestState.info) {
      throw new Error('Legacy adoption requires a matching skill map and no current ownership record.');
    }
    const legacyManifest = readFileSync(legacyManifestFile, 'utf8');
    const legacyTargets = new Set(legacyManifest.split(/\r?\n/)
      .filter(line => line.startsWith('skill:'))
      .map(line => {
        const tab = line.indexOf('\t');
        if (tab >= 0) return line.slice(tab + 1);
        const separator = line.lastIndexOf('::');
        return separator >= 0 ? line.slice(separator + 2) : line.slice('skill:'.length);
      }));
    if (!legacyTargets.size) {
      console.log('OK: no legacy skill records to adopt.');
    } else {
      const candidateState = readRoot(candidateFile);
      const candidatePaths = new Set(candidateState.value.entries.map(entry => {
        if (!entry || typeof entry.path !== 'string' || !entry.path) {
          throw new Error(`Invalid generated skill entry in ${candidateFile}`);
        }
        return entry.path;
      }));
      const eligiblePaths = new Set();
      for (const line of readFileSync(legacyCandidateFile, 'utf8').split(/\r?\n/)) {
        if (!line) continue;
        const tab = line.indexOf('\t');
        if (tab <= 0 || tab === line.length - 1) {
          throw new Error(`Invalid legacy skill map in ${legacyCandidateFile}`);
        }
        const path = line.slice(0, tab);
        const target = line.slice(tab + 1);
        if (candidatePaths.has(path) && legacyTargets.has(target)) eligiblePaths.add(path);
      }
      const counts = new Map();
      for (const entry of rootState.value.entries) {
        if (entry && !Array.isArray(entry) && typeof entry === 'object' &&
            typeof entry.path === 'string' && eligiblePaths.has(entry.path) &&
            Object.keys(entry).length === 1) {
          counts.set(entry.path, (counts.get(entry.path) || 0) + 1);
        }
      }
      const adopted = [...counts]
        .filter(([, count]) => count === 1)
        .map(([path]) => path);
      if (adopted.length) {
        writeAtomic(manifestFile,
          `${JSON.stringify({ version: 1, paths: adopted, createdTarget: false }, null, 2)}\n`,
          0o600);
        console.log(`OK: adopted ${adopted.length} exact legacy HAWS skill entries; left skills config unchanged.`);
      } else {
        console.log('OK: no exact legacy HAWS skill entries to adopt.');
      }
    }
  }

  if (command !== 'adopt') {
  const replaceOwned = command === 'apply' && option === '--replace-owned';
  const preserved = replaceOwned
    ? []
    : splitManagedEntries(rootState.value.entries, manifestState.value.paths);

  if (command === 'verify') {
    console.log('OK: Antigravity skills config and ownership record are readable.');
  } else if (command === 'apply') {
    const candidateState = readRoot(candidateFile);
    const desiredPaths = [...new Set(candidateState.value.entries.map(entry => {
      if (!entry || typeof entry.path !== 'string' || !entry.path) {
        throw new Error(`Invalid generated skill entry in ${candidateFile}`);
      }
      return entry.path;
    }))];
    const preservedPaths = new Set(preserved
      .filter(entry => entry && typeof entry === 'object' && typeof entry.path === 'string')
      .map(entry => entry.path));
    const nextPaths = [];
    const additions = [];
    for (const path of desiredPaths) {
      if (preservedPaths.has(path)) continue;
      additions.push({ path });
      nextPaths.push(path);
    }
    const createdTarget = replaceOwned || manifestState.value.createdTarget === true ||
      (!rootState.info && additions.length > 0);
    const removeCreatedRoot = nextPaths.length === 0 && createdTarget &&
      preserved.length === 0 && Object.keys(rootState.value).length === 1;
    commit(file, rootState, manifestFile, manifestState,
      { ...rootState.value, entries: [...preserved, ...additions] }, nextPaths,
      createdTarget, removeCreatedRoot);
    console.log(`OK: merged ${additions.length} HAWS Antigravity skill entries; preserved ${preserved.length} existing entries.`);
  } else {
    const removed = rootState.value.entries.length - preserved.length;
    const removeCreatedRoot = manifestState.value.createdTarget === true &&
      preserved.length === 0 && Object.keys(rootState.value).length === 1;
    commit(file, rootState, manifestFile, manifestState,
      { ...rootState.value, entries: preserved }, [], false, removeCreatedRoot);
    console.log(`OK: removed ${removed} HAWS Antigravity skill entries; preserved ${preserved.length} other entries.`);
  }
  }
} catch (error) {
  console.error(`HAWS Antigravity skills: ${error.message}`);
  process.exitCode = 1;
}
