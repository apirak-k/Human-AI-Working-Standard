---
name: keyboard-layout-fixer
description: Detects and auto-fixes text accidentally typed in the wrong keyboard layout between Thai Kedmanee and English US QWERTY, or with inverted CapsLock (e.g. "g,nv", "ดกดก", "hELLO wORLD"). Use when user prompts appear garbled due to forgotten language switching or stuck CapsLock.
license: MIT
---

# Keyboard Layout & CapsLock Fixer

Automatically detects, translates, and normalizes user input that was accidentally typed in the wrong keyboard layout (Thai Kedmanee $\leftrightarrow$ English US QWERTY) or with accidental CapsLock inversion.

## When to Use
- **Case 1 (Thai on English Layout)**: User typed English letters while meaning Thai (e.g. `fdfd` $\rightarrow$ `ดกดก`, `grnhv` $\rightarrow$ `เพื้อ`).
- **Case 2 (English on Thai Layout)**: User typed Thai characters while meaning English (e.g. `ดกดก` $\rightarrow$ `fdfd`).
- **Case 3 (Inverted CapsLock)**: User accidentally pressed Shift while CapsLock was active (e.g. `hELLO wORLD` $\rightarrow$ `Hello World`, `tESTING` $\rightarrow$ `Testing`).
- **Case 4 (CapsLock Active while Typing Thai on EN Layout)**: User typed with CapsLock ON (e.g. `FDFD` $\rightarrow$ `ดกดก`, `GRNHV` $\rightarrow$ `เพื้อ`), cleanly converting without shifted upper vowel / tone mark distortion.
- **Safety Guard (Acronym & Tech Token Bypass)**: Common English acronyms and technical tokens (e.g. `API`, `SQL`, `HTML`, `README`, `JSON`, `URL`) are automatically detected and preserved without conversion.
- Trigger automatically whenever user input appears nonsensical or garbled.

## Core Capabilities & Script
A high-performance, deterministic Node.js converter is located at:
`skills/custom/keyboard-layout-fixer/scripts/layout_fixer.mjs`

### CLI Usage:
```bash
node skills/custom/keyboard-layout-fixer/scripts/layout_fixer.mjs "<garbled text>"
```

### Module Import:
```javascript
import { autoDetectAndFix, enToTh, thToEn, fixCapsLock } from "./scripts/layout_fixer.mjs";

const corrected = autoDetectAndFix(userInput);
```

## Quality & Behavioral Standards
1. **Zero Silent Guessing**: When converting garbled user input, the AI should seamlessly process the intended query while briefly acknowledging the converted input (e.g. `[Converted: 'ดกดก' ➔ 'fdfd']`).
2. **Hermetic & Offline**: Uses standard Unicode character mappings with zero external network or API dependencies.