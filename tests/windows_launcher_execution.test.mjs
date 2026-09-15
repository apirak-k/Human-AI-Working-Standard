import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  copyFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from "node:fs";
import os from "node:os";
import path from "node:path";

const isWindows = os.platform() === "win32";
const projectRoot = path.resolve(import.meta.dirname, "..");
const launcher = path.join(projectRoot, "haws.bat");

function makeFixture({ script = true } = {}) {
  const root = mkdtempSync(path.join(os.tmpdir(), "haws-batch1-launcher-"));
  if (existsSync(launcher)) copyFileSync(launcher, path.join(root, "haws.bat"));
  if (script) {
    writeFileSync(
      path.join(root, "haws.sh"),
      '#!/usr/bin/env bash\nprintf \'<%s>\\n\' "$@" > "$(dirname "$0")/bash.log"\nexit "${FAKE_BASH_EXIT:-0}"\n',
      "utf8",
    );
  }
  return root;
}

function launcherEnv(root, extra = {}) {
  const system32 = path.join(process.env.SystemRoot, "System32");
  const gitBin = "C:\\Program Files\\Git\\bin";
  const cleanEnv = Object.fromEntries(
    Object.entries(process.env).filter(([key]) => key.toLowerCase() !== "path"),
  );
  return {
    ...cleanEnv,
    Path: `${gitBin};${system32}`,
    HAWS_NO_PAUSE: "1",
    BASH_LOG: path.join(root, "bash.log"),
    FAKE_BASH_EXIT: "0",
    ProgramFiles: root,
    "ProgramFiles(x86)": root,
    LocalAppData: root,
    USERPROFILE: root,
    ProgramData: root,
    ...extra,
  };
}

function runWindowsUninstall({ link, source, keep, unrelated, kind, root }) {
  const gitBash = path.join(
    process.env.ProgramFiles ?? "C:\\Program Files",
    "Git",
    "bin",
    "bash.exe",
  );
  const shellScript = [
    "set -eu",
    'project="$(cygpath -u -- "$HAWS_PROJECT_ROOT")"',
    'home="$(cygpath -u -- "$HAWS_TEST_HOME")"',
    'state="$(cygpath -u -- "$HAWS_TEST_STATE")"',
    'link="$(cygpath -u -- "$HAWS_TEST_LINK")"',
    'source_path="$(cygpath -u -- "$HAWS_TEST_SOURCE")"',
    'keep_path="$(cygpath -u -- "$HAWS_TEST_KEEP")"',
    'unrelated_path="$(cygpath -u -- "$HAWS_TEST_UNRELATED")"',
    'export HOME="$home" HAWS_REPO_DIR="$project" HAWS_STATE_DIR="$state" HAWS_SOURCE_ONLY=1',
    '. "$project/haws.sh"',
    "unset HAWS_SOURCE_ONLY",
    'if [ "$HAWS_TEST_KIND" != generated-file ]; then',
    '  link_target="$(readlink "$link" 2>/dev/null || true)"',
    '  if [ -z "$link_target" ] || ! [ -L "$link" ]; then',
    '    echo "[Unverified] Windows link type is not executable by Git Bash" >&2',
    "    exit 77",
    "  fi",
    "fi",
    'if [ "$HAWS_TEST_KIND" = generated-file ]; then',
    '  fingerprint="$(_haws_sha256 "$link")"',
    "else",
    '  fingerprint="$(canonical_path "$source_path")"',
    "fi",
    'ownership_record skills "$HAWS_TEST_KIND" "$link" "$source_path" "$fingerprint"',
    'plan="$(uninstall_plan skills)"',
    'uninstall_apply "$plan"',
    '! [ -e "$link" ] && ! [ -L "$link" ]',
    '[ -f "$keep_path" ]',
    '[ -f "$unrelated_path" ]',
  ].join("\n");
  return spawnSync(gitBash, ["-lc", shellScript], {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      HAWS_PROJECT_ROOT: projectRoot,
      HAWS_TEST_HOME: path.join(root, "home"),
      HAWS_TEST_STATE: path.join(root, "state"),
      HAWS_TEST_LINK: link,
      HAWS_TEST_SOURCE: source,
      HAWS_TEST_KEEP: keep,
      HAWS_TEST_UNRELATED: unrelated,
      HAWS_TEST_KIND: kind,
    },
    timeout: 10000,
    windowsHide: true,
  });
}

test("haws.bat exists", { skip: !isWindows }, () => {
  assert.equal(existsSync(launcher), true);
});

test("single Home entrypoint uses the shared terminal interaction engine", { skip: !isWindows }, () => {
  const source = readFileSync(path.join(projectRoot, "haws.sh"), "utf8");
  assert.doesNotMatch(source, /run_main_menu\(\) \{/);
  assert.doesNotMatch(source, /\\033\[H\\033\[2J/);
  assert.match(source, /interactive_menu\s+menu/);
  assert.match(source, /interactive_menu\s+checklist/);
  assert.match(source, /printf "\\033\[\?25l"/);
  assert.match(source, /printf "\\033\[%dA"/);
  assert.match(source, /printf "\\033\[2K\\r/);
  assert.match(source, /printf "\\033\[\?25h"/);
});

test("bare launch forwards menu and preserves the child exit code", { skip: !isWindows }, () => {
  const root = makeFixture();
  try {
    const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat"], {
      cwd: root,
      encoding: "utf8",
      env: launcherEnv(root, { FAKE_BASH_EXIT: "37" }),
      timeout: 5000,
      windowsHide: true,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 37);
    const forwarded = readFileSync(path.join(root, "bash.log"), "utf8");
    assert.equal(forwarded, "<menu>\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("explicit arguments are forwarded unchanged", { skip: !isWindows }, () => {
  const root = makeFixture();
  try {
    const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat", "alpha", "two words"], {
      cwd: root,
      encoding: "utf8",
      env: launcherEnv(root),
      timeout: 5000,
      windowsHide: true,
    });
    assert.equal(result.status, 0);
    const forwarded = readFileSync(path.join(root, "bash.log"), "utf8");
    assert.equal(forwarded, "<alpha>\n<two words>\n");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("direct haws.bat sync pauses unless HAWS_NO_PAUSE=1", { skip: !isWindows }, () => {
  const root = makeFixture();
  try {
    const resultNoPause = spawnSync("cmd.exe", ["/d", "/c", "haws.bat", "sync"], {
      cwd: root,
      encoding: "utf8",
      env: launcherEnv(root, { HAWS_NO_PAUSE: "1" }),
      timeout: 5000,
      windowsHide: true,
    });
    assert.equal(resultNoPause.status, 0);
    const forwarded = readFileSync(path.join(root, "bash.log"), "utf8");
    assert.equal(forwarded, "<sync>\n");

    const batContent = readFileSync(path.join(root, "haws.bat"), "utf8");
    assert.match(batContent, /if\s+\/i\s+"%~1"=="sync"\s+set\s+"HAWS_PAUSE=1"/i);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("missing haws.sh is an explicit non-blocking error", { skip: !isWindows }, () => {
  const root = makeFixture({ script: false });
  try {
    const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat"], {
      cwd: root,
      encoding: "utf8",
      env: launcherEnv(root),
      timeout: 5000,
      windowsHide: true,
    });
    assert.equal(result.status, 1);
    assert.match(result.stdout, /haws\.sh was not found/i);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("launcher retains an explicit missing-Bash error", { skip: !isWindows }, () => {
  assert.match(readFileSync(launcher, "utf8"), /Git Bash was not found/i);
});

test("launcher establishes the HAWS window title before delegation", { skip: !isWindows }, () => {
  assert.match(readFileSync(launcher, "utf8"), /title HAWS — Human-AI Working Standard/);
});

test("real launcher and haws.sh bare q exit without mutating fixture HOME", { skip: !isWindows }, () => {
  const home = mkdtempSync(path.join(os.tmpdir(), "haws-batch1-home-"));
  try {
    const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat"], {
      cwd: projectRoot,
      encoding: "utf8",
      env: { ...process.env, HOME: home, HAWS_NO_PAUSE: "1" },
      input: "q",
      timeout: 5000,
      windowsHide: true,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0);
    assert.match(result.stdout, /HAWS Setup/);
    assert.equal(existsSync(path.join(home, ".haws_manifest")), false);
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});

test("real launcher help exits successfully", { skip: !isWindows }, () => {
  const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat", "--help"], {
    cwd: projectRoot,
    encoding: "utf8",
    env: { ...process.env, HAWS_NO_PAUSE: "1" },
    timeout: 5000,
    windowsHide: true,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stdout + "\n" + result.stderr);
  assert.match(result.stdout, /Usage:/);
});

test("launcher supplies Git Bash POSIX utilities when only its bin is on PATH", { skip: !isWindows }, () => {
  const system32 = path.join(process.env.SystemRoot, "System32");
  const gitBin = path.join(process.env.ProgramFiles ?? "C:\\Program Files", "Git", "bin");
  const cleanEnv = Object.fromEntries(
    Object.entries(process.env).filter(([key]) => key.toLowerCase() !== "path"),
  );
  const result = spawnSync("cmd.exe", ["/d", "/c", "haws.bat", "--help"], {
    cwd: projectRoot,
    encoding: "utf8",
    env: {
      ...cleanEnv,
      Path: `${gitBin};${system32}`,
      HAWS_NO_PAUSE: "1",
    },
    timeout: 5000,
    windowsHide: true,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.status, 0, result.stdout + "\n" + result.stderr);
  assert.match(result.stdout, /Usage:/);
});

test("Windows generated-file ownership is removed without touching its source", { skip: !isWindows }, () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "haws-batch6-windows-"));
  const home = path.join(root, "home", ".claude");
  const source = path.join(root, "source.txt");
  const link = path.join(home, "managed.txt");
  const keep = source;
  const unrelated = path.join(home, "unrelated.txt");
  try {
    writeFileSync(source, "source\n", "utf8");
    mkdirSync(home, { recursive: true });
    writeFileSync(link, "managed\n", "utf8");
    writeFileSync(unrelated, "unrelated\n", "utf8");
    const result = runWindowsUninstall({
      root,
      link,
      source,
      keep,
      unrelated,
      kind: "generated-file",
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stdout + "\n" + result.stderr);
    assert.equal(existsSync(link), false);
    assert.equal(existsSync(source), true);
    assert.equal(existsSync(unrelated), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Windows junction ownership removes only the junction when executable", { skip: !isWindows }, (t) => {
  const root = mkdtempSync(path.join(os.tmpdir(), "haws-batch6-windows-"));
  const target = path.join(root, "junction-target");
  const link = path.join(root, "home", ".claude", "junction");
  const source = target;
  const keep = path.join(target, "keep.txt");
  const unrelated = path.join(root, "home", ".claude", "unrelated.txt");
  try {
    mkdirSync(target, { recursive: true });
    mkdirSync(path.dirname(link), { recursive: true });
    writeFileSync(keep, "target\n", "utf8");
    writeFileSync(unrelated, "unrelated\n", "utf8");
    try {
      symlinkSync(target, link, "junction");
    } catch {
      t.skip("[Unverified] junction creation requires Windows link privilege");
      return;
    }
    if (!lstatSync(link).isSymbolicLink()) {
      t.skip("[Unverified] junction was not created as a link");
      return;
    }
    const result = runWindowsUninstall({
      root,
      link,
      source,
      keep,
      unrelated,
      kind: "junction",
    });
    if (result.status === 77) {
      t.skip(result.stderr.trim() || "[Unverified] Git Bash could not execute junction");
      return;
    }
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stdout + "\n" + result.stderr);
    assert.equal(existsSync(link), false);
    assert.equal(existsSync(keep), true);
    assert.equal(existsSync(unrelated), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Windows file symlink ownership removes only the symlink when executable", { skip: !isWindows }, (t) => {
  const root = mkdtempSync(path.join(os.tmpdir(), "haws-batch6-windows-"));
  const source = path.join(root, "source.txt");
  const link = path.join(root, "home", ".claude", "symlink");
  const keep = source;
  const unrelated = path.join(root, "home", ".claude", "unrelated.txt");
  try {
    mkdirSync(path.dirname(link), { recursive: true });
    writeFileSync(source, "source\n", "utf8");
    writeFileSync(unrelated, "unrelated\n", "utf8");
    try {
      symlinkSync(source, link, "file");
    } catch {
      t.skip("[Unverified] file symlink creation requires Windows link privilege");
      return;
    }
    if (!lstatSync(link).isSymbolicLink()) {
      t.skip("[Unverified] file symlink was not created as a link");
      return;
    }
    const result = runWindowsUninstall({
      root,
      link,
      source,
      keep,
      unrelated,
      kind: "symlink",
    });
    if (result.status === 77) {
      t.skip(result.stderr.trim() || "[Unverified] Git Bash could not execute symlink");
      return;
    }
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stdout + "\n" + result.stderr);
    assert.equal(existsSync(link), false);
    assert.equal(existsSync(keep), true);
    assert.equal(existsSync(unrelated), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
