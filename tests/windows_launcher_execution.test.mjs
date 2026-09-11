import test from "node:test";
import assert from "node:assert/strict";
import { execSync, spawnSync } from "node:child_process";
import os from "node:os";

const isWindows = os.platform() === "win32";

test("haws.bat execution suite", { skip: !isWindows }, async (t) => {
  await t.test("unknown command exits with 1 and prints usage", () => {
    const res = spawnSync("cmd.exe", ["/c", "haws.bat", "unknown"], {
      cwd: process.cwd(),
      encoding: "utf8",
    });
    assert.equal(res.status, 1);
    assert.match(res.stdout, /Usage: \.\/haws\.sh/);
  });

  await t.test("bare launch non-interactive exits with 0 and prints guidance", () => {
    const res = spawnSync("cmd.exe", ["/c", "haws.bat"], {
      cwd: process.cwd(),
      encoding: "utf8",
    });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /HAWS is non-interactive/);
  });

  await t.test("forwards subcommands cleanly to haws.sh", () => {
    const res = spawnSync("cmd.exe", ["/c", "haws.bat", "codex-agents", "check"], {
      cwd: process.cwd(),
      encoding: "utf8",
    });
    assert.equal(res.status, 0);
    assert.match(res.stdout, /PASS: 5\/5 native Codex HAWS profiles/);
  });

  await t.test("TUI cancel key cancels with no changes saved", () => {
    const res = spawnSync("cmd.exe", ["/c", "haws.bat", "settings"], {
      cwd: process.cwd(),
      encoding: "utf8",
      env: { ...process.env, HAWS_TEST_KEYS: "cancel" },
    });
    assert.equal(res.status, 1);
    assert.match(res.stdout, /Cancelled\. No changes saved\./);
  });
});
