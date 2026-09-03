import assert from "node:assert";
import { enToTh, thToEn, isCapsLockInverted, fixCapsLock, autoDetectAndFix } from "../scripts/layout_fixer.mjs";

console.log("Running Keyboard Layout Fixer Test Suite...");

// 1. English to Thai conversion
const thResult = enToTh("fdfd");
assert.strictEqual(thResult, "ดกดก", `Expected ดกดก, got ${thResult}`);
console.log("  [PASS] enToTh: 'fdfd' -> 'ดกดก'");

// 2. Thai to English conversion
const enResult = thToEn("ดกดก");
assert.strictEqual(enResult, "fdfd", `Expected fdfd, got ${enResult}`);
console.log("  [PASS] thToEn: 'ดกดก' -> 'fdfd'");

// 3. CapsLock detection & fix
assert.strictEqual(isCapsLockInverted("hELLO wORLD"), true);
assert.strictEqual(isCapsLockInverted("Hello World"), false);
assert.strictEqual(isCapsLockInverted("ดกดก"), false);
const fixedCaps = fixCapsLock("hELLO wORLD");
assert.strictEqual(fixedCaps, "Hello World", `Expected Hello World, got ${fixedCaps}`);
console.log("  [PASS] CapsLock Inversion: 'hELLO wORLD' -> 'Hello World'");

// 4. Auto-detect and fix
assert.strictEqual(autoDetectAndFix("fdfd"), "ดกดก");
assert.strictEqual(autoDetectAndFix("ดกดก"), "fdfd");
assert.strictEqual(autoDetectAndFix("tESTING"), "Testing");
console.log("  [PASS] autoDetectAndFix covers all modes");

console.log("\n=======================================================");
console.log("  [100% GREEN] All Keyboard Layout Fixer Tests Passed!");
console.log("=======================================================");