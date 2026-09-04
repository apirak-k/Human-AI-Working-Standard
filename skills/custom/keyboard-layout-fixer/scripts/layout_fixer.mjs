/**
 * Keyboard Layout & CapsLock Fixer
 * Bidirectional conversion between Thai Kedmanee and English US QWERTY layouts,
 * with automatic CapsLock inversion detection.
 */

// 47 Unshifted Keys
const EN_UNSHIFTED = [
  '`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=',
  'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\\',
  'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', "'",
  'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/'
];

const TH_UNSHIFTED = [
  '_', 'ๅ', '/', '-', 'ภ', 'ถ', 'ุ', 'ึ', 'ค', 'ต', 'จ', 'ข', 'ช',
  'ๆ', 'ไ', 'ำ', 'พ', 'ะ', 'ั', 'ี', 'ร', 'น', 'ย', 'บ', 'ล', 'ฃ',
  'ฟ', 'ห', 'ก', 'ด', 'เ', '้', '่', 'า', 'ส', 'ว', 'ง',
  'ผ', 'ป', 'แ', 'อ', 'ิ', 'ื', 'ท', 'ม', 'ใ', 'ฝ'
];

// 47 Shifted Keys
const EN_SHIFTED = [
  '~', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+',
  'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '|',
  'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"',
  'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?'
];

const TH_SHIFTED = [
  '%', '+', '๑', '๒', '๓', '๔', 'ู', '฿', '๕', '๖', '๗', '๘', '๙',
  '๐', '"', 'ฎ', 'ฑ', 'ธ', 'ํ', '๊', 'ณ', 'ฯ', 'ญ', 'ฐ', ',', 'ฅ',
  'ฤ', 'ฆ', 'ฏ', 'โ', 'ฌ', '็', '๋', 'ษ', 'ศ', 'ซ', '.',
  '(', ')', 'ฉ', 'ฮ', 'ฺ', '์', '?', 'ฒ', 'ฬ', 'ฦ'
];

const enToThMap = new Map();
const thToEnMap = new Map();

for (let i = 0; i < EN_UNSHIFTED.length; i++) {
  enToThMap.set(EN_UNSHIFTED[i], TH_UNSHIFTED[i]);
  thToEnMap.set(TH_UNSHIFTED[i], EN_UNSHIFTED[i]);
}

for (let i = 0; i < EN_SHIFTED.length; i++) {
  enToThMap.set(EN_SHIFTED[i], TH_SHIFTED[i]);
  thToEnMap.set(TH_SHIFTED[i], EN_SHIFTED[i]);
}

export function enToTh(text) {
  return Array.from(text).map(c => enToThMap.get(c) || c).join('');
}

export function thToEn(text) {
  return Array.from(text).map(c => thToEnMap.get(c) || c).join('');
}

export function isCapsLockInverted(text) {
  // Only applicable to texts containing Latin letters with case distinctions
  if (!/[a-zA-Z]/.test(text)) return false;

  const words = text.split(/\s+/).filter(Boolean);
  if (words.length === 0) return false;
  let count = 0;
  for (const w of words) {
    if (w.length > 1 && /[a-z]/.test(w[0]) && /[A-Z]/.test(w.slice(1))) {
      if (w[0] === w[0].toLowerCase() && w.slice(1) === w.slice(1).toUpperCase()) {
        count++;
      }
    }
  }
  return count > 0 && count >= words.length / 2;
}

export function fixCapsLock(text) {
  return Array.from(text).map(c => {
    return c === c.toUpperCase() ? c.toLowerCase() : c.toUpperCase();
  }).join('');
}

const COMMON_TECH_ACRONYMS = new Set([
  'API', 'SQL', 'HTML', 'CSS', 'JSON', 'XML', 'YAML', 'YML', 'CSV', 'TSV',
  'URL', 'URI', 'HTTP', 'HTTPS', 'REST', 'CRUD', 'SDK', 'CLI', 'IDE', 'GUI',
  'AWS', 'GCP', 'S3', 'EC2', 'AI', 'LLM', 'ML', 'DL', 'NLP', 'UI', 'UX',
  'PR', 'CI', 'CD', 'SOT', 'HAWS', 'LF', 'CRLF', 'README', 'TODO', 'NOTE',
  'FIXME', 'PASS', 'FAIL', 'WARN', 'INFO', 'DEBUG', 'ERROR', 'GET', 'POST',
  'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS', 'DB', 'ID', 'UUID', 'IP',
  'TCP', 'UDP', 'DNS', 'SSH', 'SSL', 'TLS', 'JWT', 'OAUTH', 'OK', 'HELP',
  'PORT', 'HOST', 'TRUE', 'FALSE', 'NULL', 'GIT', 'NPM', 'PNPM', 'YARN', 'PIP'
]);

export function isAcronymOrTechTerm(text) {
  const trimmed = text.trim();
  if (!trimmed) return false;
  const words = trimmed.split(/\s+/);
  return words.length > 0 && words.every(w => {
    const clean = w.replace(/[^a-zA-Z0-9]/g, '');
    return COMMON_TECH_ACRONYMS.has(clean.toUpperCase());
  });
}

export function autoDetectAndFix(text) {
  if (!text) return text;

  // Safety Check: Never accidentally convert intentional English technical acronyms
  if (isAcronymOrTechTerm(text)) {
    return text;
  }

  // Case 3: Inverted CapsLock English (e.g. "hELLO wORLD" -> "Hello World")
  if (isCapsLockInverted(text)) {
    return fixCapsLock(text);
  }

  let thCount = 0;
  let enCount = 0;
  let upperCount = 0;
  for (const c of text) {
    const code = c.charCodeAt(0);
    if (code >= 0x0E00 && code <= 0x0E7F) {
      thCount++;
    } else if (/[a-zA-Z]/.test(c)) {
      enCount++;
      if (/[A-Z]/.test(c)) {
        upperCount++;
      }
    }
  }

  // Case 2: Thai -> English (e.g. "ดกดก" -> "fdfd")
  if (thCount > enCount) {
    return thToEn(text);
  } else if (enCount > 0) {
    // Case 4: CapsLock on while typing Thai on EN layout (e.g. "FDFD" -> "ดกดก", "GRNHV" -> "เพื้อ")
    if (upperCount > 0 && upperCount >= enCount * 0.8) {
      return enToTh(text.toLowerCase());
    }
    // Case 1: English -> Thai (e.g. "fdfd" -> "ดกดก")
    return enToTh(text);
  }
  return text;
}

// CLI Execution Support
if (process.argv[1] && process.argv[1].replace(/\\/g, '/').endsWith('layout_fixer.mjs')) {
  const args = process.argv.slice(2);
  if (args.length > 0) {
    console.log(autoDetectAndFix(args.join(' ')));
  }
}