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
console.log("  [PASS] autoDetectAndFix: Cases 1, 2, 3 pass");

// 5. Case 4: CapsLock on while typing Thai on EN layout
const case4_1 = autoDetectAndFix("FDFD");
assert.strictEqual(case4_1, "ดกดก", `Expected ดกดก, got ${case4_1}`);
console.log("  [PASS] Case 4: 'FDFD' -> 'ดกดก' (no vowel distortion)");

const case4_2 = autoDetectAndFix("GRNHV");
assert.strictEqual(case4_2, "เพื้อ", `Expected เพื้อ, got ${case4_2}`);
console.log("  [PASS] Case 4: 'GRNHV' -> 'เพื้อ' (no stacked tone distortion)");

// 6. Safety Guard: English Tech Acronyms should NOT be converted
assert.strictEqual(autoDetectAndFix("API"), "API");
assert.strictEqual(autoDetectAndFix("SQL"), "SQL");
assert.strictEqual(autoDetectAndFix("HTML"), "HTML");
assert.strictEqual(autoDetectAndFix("README"), "README");
assert.strictEqual(autoDetectAndFix("JSON API"), "JSON API");
console.log("  [PASS] Safety Guard: 'API', 'SQL', 'HTML', 'README', 'JSON API' preserved");

console.log("\n=======================================================");
console.log("  [100% GREEN] All 4 Cases & Acronym Tests Passed!");
console.log("=======================================================");