import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

test("haws.bat exists", { skip: !isWindows }, () => {
  assert.equal(existsSync(launcher), true);
});

test("main menu uses the shared old terminal interaction engine", { skip: !isWindows }, () => {
  const source = readFileSync(path.join(projectRoot, "haws.sh"), "utf8");
  const mainStart = source.indexOf("run_main_menu() {");
  const mainEnd = source.indexOf('case "${COMMAND}"', mainStart);
  assert.notEqual(mainStart, -1);
  assert.notEqual(mainEnd, -1);

  const mainMenu = source.slice(mainStart, mainEnd);
  assert.equal((source.match(/read -rsn1/g) || []).length, 1);
  assert.doesNotMatch(mainMenu, /read -rsn1/);
  assert.doesNotMatch(mainMenu, /render_main_menu/);
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
