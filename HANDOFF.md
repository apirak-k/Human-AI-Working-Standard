# Session Checkpoint & Comprehensive Cross-Device Handoff — HAWS v2.0

> **Checkpoint Date**: 2026-09-04 17:10:00 (Local Time)  
> **Active Branch**: `main`  
> **Status**: In-Progress Review Checkpoint (Cross-Device Ready)  
> **Permanent Historical Audit**: See [docs/SESSION_ANALYSIS_AND_AUDIT.md](docs/SESSION_ANALYSIS_AND_AUDIT.md)

---

## 🧭 1. User Review Progress Tracker (สถานะการตรวจรีวิวของผู้ใช้)

ก่อนเดินทางกลับบ้าน การรีวิวทีละหมวดหมู่คืบหน้าไปดังนี้ เพื่อให้กลับไปเปิดตรวจต่อที่บ้านได้ทันที:

| Domain / Category | Status | Details & Progress |
| :--- | :---: | :--- |
| **หมวด 1: พฤติกรรม & กฎ AI (Grounding & Behavior)** | 🟢 ตรวจแล้ว | Anti-hallucination, Empirical evidence, Caveman mode, Skill banner. |
| **หมวด 2: Context Window & Token** | 🟢 ตรวจแล้ว & คอนเฟิร์ม | ตัดการแสดงผลตัวเลข Token/Context Window ออก แต่คงวินัย Lean Context (Summary + Pointer / Progressive Disclosure). |
| **หมวด 3: เทมเพลตมาตรฐาน 8 ไฟล์ & `.env`** | 🟢 ตรวจแล้ว & คอนเฟิร์ม | ตัดความซ้ำซ้อนใน `AGENTS.md` ให้ชี้ Pointer ไป `CONSTRAINTS.md`, เติมคำสั่ง Build/Test สากล, เคลียร์เรื่อง `.env`. |
| **หมวด 4: Subagents & Custom Skill** | 🟢 ตรวจแล้ว & คอนเฟิร์ม | • Agent Harness (`<task_assignment>` / `<task_report>`): คอนเฟิร์ม<br>• `ponytail` (Lazy Dev Ladder): คอนเฟิร์ม<br>• Bounded Loop: คอนเฟิร์ม 3 ครั้ง<br>• Custom Skill (`keyboard-layout-fixer`): คอนเฟิร์มเก็บเป็นสกิลแรก พร้อมเติม Case 4 ในการ implement |
| **หมวด 5: Tooling & Dashboard** | 🟢 ตรวจแล้ว & คอนเฟิร์ม | สั่งลบแดชบอร์ดถาวร (`dashboard/` ถูกลบแล้วเพื่อความ Minimalist). |
| **หมวด 6: Git Hooks & Guardrails** | 🟢 ตรวจแล้ว & คอนเฟิร์ม | คอนเฟิร์มใช้ 2 Hooks หลัก (`pre-commit` ดัก .env/LF และ `pre-push` บล็อก push อัตโนมัติ) ไม่เพิ่ม Hook อื่นให้รก |

---

## 🧠 2. Deep Discussions, Thoughts & Ideas (ข้อคิดและไอเดียที่คุยกันล่าสุด)

### A. บทบาทการ Prune: Gitmodule Auto-Prune vs @organizer Watchdog
* **ฝั่ง Gitmodule (การเก็บกวาด)**: เมื่อคุณตัดสินใจจะลบอะไร ระบบ Auto-Prune จะทำหน้าที่ "เก็บกวาดอันนั้นให้เกลี้ยง 100%" (ปลด Submodule, ลบ `.gitmodules`, ล้าง Cache `.git/modules/`, และลบ Directory จริง ไม่เหลือไฟล์หลอน)
* **ฝั่ง @organizer (การแจ้งเตือน)**: ตัว `@organizer` ทำหน้าที่สแกนดูว่าสกิลไหนไม่ได้ใช้แล้ว ถ้ามันเห็นว่าควรลบ "ก็แค่มาบอกคุณ และรอให้คุณเป็นคนตัดสินใจ" (ไม่ลบเองโดยพลการ) พอคุณอนุมัติ ระบบ Auto-Prune จึงจะลงมือเก็บกวาดจริง

### B. นิยามของ "HAWS Starter Kit"
* **KIT ไม่ใช่โฟลเดอร์แยก**: KIT คือ **"ชุดบันเดิลรวมทั้งหมดของ HAWS"** (The Complete HAWS Kit Manifest)
* รวมทั้งรีโปที่เป็น **Agent Skills** (อยู่ใน `skills/`) และรีโปที่ **ไม่ใช่สกิล** (เช่น รีโปที่คุณ Starred ไว้: Ponytail, Archify ฯลฯ)
* **Out-of-the-box**: คนติดตั้งครั้งแรกได้ของครบพร้อมใช้ทันที แต่เปิดให้ปรับแต่ง (Customize) ถอดหรือเพิ่มได้อิสระในภายหลัง

### C. สถาปัตยกรรมการอัปเดต HAWS vs Git Submodule (ไอเดียที่คุณเสนอ)
* **ปัญหาเดิมของ Submodule**: ถ้าผู้ใช้ลบสกิลใน Kit ทิ้งในเครื่อง พอสั่งอัปเดต Git จะดึงกลับมาฟื้นคืนชีพ ทำให้รำคาญ
* **แนวทางที่ถูกต้องตามที่คุณเสนอ**:
  1. **ติดตั้งครั้งแรก**: ลง HAWS พร้อมชุด KIT พื้นฐานครบชุด
  2. **ปรับแต่งในเครื่อง (Adjust)**: ผู้ใช้ปรับแต่ง/ปิดสกิลในเครื่องของตัวเอง
  3. **การอัปเดต HAWS**: ให้อัปเดตเฉพาะตัวระบบแกนของ HAWS และสโคปเฉพาะลิงก์ commit ใน `.gitmodules` **โดยไม่ไป overwrite หรือกระทบสิ่งที่ผู้ใช้ปรับแต่งไว้ในเครื่อง**
  4. **ระบบ Soft-Disable & Prune จริง**:
     - `haws.sh kit add --skill <url>` / `haws.sh kit add --tool <url>`
     - `haws.sh kit prune <name>`: ปลดออกจาก AI ➔ ลบ Submodule ➔ ลบ cache ใน `.git/modules/` ➔ ลบ Directory เกลี้ยง
     - `.gitattributes`: `.gitmodules merge=ours` ป้องกัน Repo แม่ดึงสกิลที่ prune แล้วกลับมาฟื้นคืนชีพ

### D. การแยกห้องเด็ดขาด: Core Framework vs secondbrain/
* **`core/` (ของกลางสากล)**: กฎสากล, เทมเพลต, สคริปต์ ดึงอัปเดตจาก Repo แม่ได้ตลอดเวลา
* **`secondbrain/` (ของส่วนตัว)**: Second Brain, ความชอบส่วนตัว, ข้อห้าม ถูกกั้นด้วย `.gitignore` ไม่มีวันหลุดไปโผล่บน Repo แม่ 100%
* **Local-First**: คนใช้คอมเครื่องเดียว **ไม่ต้องสร้าง GitHub Repo อะไรทั้งสิ้น** ใช้งานในเครื่องได้ทันที 100% (Zero Setup)
* **`plugins/`**: โฟลเดอร์สำหรับเก็บ Submodule เครื่องมือเสริมภายนอก (เช่น Ponytail, Archify) แยกจาก `skills/` ไม่กิน Token

### E. 1-Click Symmetrical Cross-Device (สมมาตรทุกเครื่องผ่าน Standalone Private Repo)
* **ไม่ใช้การ Fork**: เพราะ Fork บน GitHub บังคับเป็น Public และโชว์ชื่อหราบน Repo แม่
* **ใช้ Standalone Private Repo**: สร้าง Private Repo ลับของตัวเองชื่อ `my-haws-brain`
* **สมมาตรทุกเครื่อง**: ทั้งเครื่องที่ 1 และเครื่องที่ 2 ทำเหมือนกัน 100% คือแค่วางลิงก์ GitHub ตัวเอง
  - ถ้าเป็น Repo เปล่า (เครื่องแรก) ➔ Pure Push ยกความจำขึ้นคลาวด์
  - ถ้าเป็น Repo มีข้อมูล (เครื่องสอง) ➔ รัน Auto-Merge

### F. Forced Auto-Merge & Transaction Ordering (รวมสมอง ไม่ทิ้งข้อมูล)
* **Forced Auto-Merge (Union)**: ถ้ารีโปมีข้อมูล และในเครื่องก็มีข้อมูล ระบบจะรวมข้อมูลเข้าด้วยกันทันที ไม่ถามจุกจิก
* **ตัดข้อซ้ำ**: เทียบ Key ตัวหนาใน Preferences และชื่อเรื่องใน Anti-Patterns
* **Transaction Sorting**: จัดเรียงกฎและข้อห้ามตาม **วันที่/เวลา (`YYYY-MM-DD`)** เสมือนสมุดบันทึกประวัติการเรียนรู้
* **Lean Checkpoint**: ไม่สร้างโฟลเดอร์ `.haws_backup/` ขยะ แต่ใช้ Git Checkpoint Commit ในเครื่อง ย้อนเวลาได้ใน 0.1 วินาที

### G. Windows File Explorer Launcher (`brain-online.bat`)
* **`brain-online.bat`**: ดับเบิลคลิกสลับสถานะ
  - ถ้ายังไม่ต่อ ➔ เด้งหน้าต่างให้วางลิงก์
  - ถ้าต่อแล้ว ➔ เด้งหน้าต่าง Safety Guard สีเหลืองถามยืนยันก่อนปลด (มีผลเฉพาะเครื่องนั้น ไม่ลบคลาวด์)
* **ซิงค์ประจำวัน**: รัน `bash haws.sh sync` ใน Terminal คำสั่งเดียวจบ

### H. การเชื่อมต่อ AI ของแต่ละโปรแกรม
* **Google Antigravity**: เขียน Path ลง `~/.gemini/config/skills.json` 100% (ไม่ใช้ Symlink)
* **Claude Code**: ทำ Directory Symlink เข้า `~/.claude/skills/`

---

## 🔄 3. Detailed Change Ledger (Before vs After รายไฟล์ของระบบ)

เก็บข้อมูลเดิมไว้ครบถ้วน 100% เพื่อให้คุณตรวจย้อนหลังได้ทุกจุด:

### 1. Root & Core Governance
* **`.gitattributes`**:
  * *Before*: Minimal configuration.
  * *After*: บังคับ universal LF line endings (`* text=auto eol=lf`) ทั่วทั้งโปรเจกต์ กำจัดปัญหา Windows CRLF diff ผีหลอก
* **`core/HAWS.md`**:
  * *Before*: กฎทั่วไป ขาดการบังคับหลักฐานเชิงประจักษ์
  * *After*: 
    - Sec 3.1: Anti-Hallucination Defense (ต้องแสดงผล Terminal จริง, ติดป้าย `[Unverified]` ถ้ายังไม่ได้รัน)
    - Sec 5.1: Minimalist Engineering (Ponytail Lazy Senior Dev Ladder 7 ขั้น)
    - Sec 7.1: Bounded Self-Correction Loop (จำกัดแก้ไม่เกิน 3 ครั้ง ห้าม bypass test หรือใส่ `@ts-ignore`)
    - Sec 10: Caveman Standard (Lite สำหรับรายงาน, Full/Ultra สำหรับคำถามปิด)
* **`core/WORK_INSTRUCTIONS.md`**:
  * *Before*: ขาดการจัดระเบียบบริบท
  * *After*: 
    - Sec 1.1: Context Discipline (ซอยไฟล์ ~200-300 บรรทัดด้วย Summary + Pointer, Progressive Disclosure, On-demand loading, ตัดตัวเลข token display ออกตามคำสั่งผู้ใช้)
    - Sec 2.1: Top-line Skill Declaration (ประกาศชื่อสกิลบรรทัดแรกเสมอ)
    - Sec 4.2: English Reload Window alert (`[ACTION REQUIRED: RELOAD WINDOW]`)
* **`core/ANTI_PATTERNS.md`**:
  * *Before*: 8 ข้อพื้นฐาน
  * *After*: เพิ่ม 5 ข้อปฏิบัติสำคัญ (แบน `.env` บน git, แบน CRLF, แบน bypass test, แบน loop เกิน 3 ครั้ง, แบนการใช้สกิลเงียบๆ)

### 2. Specialist Subagents (`agents/*.md`)
* ครอบสัญญา **Agent Harness**: รับงานผ่าน `<task_assignment>` และส่งงานผ่าน `<task_report>` (Summary, Evidence, Skills used, Unverified)

### 3. Canonical Blueprints & Templates (`templates/`)
* **`templates/ARCHITECTURE.md`**: ใส่ Mermaid Topology Diagram + Archify JSON IR structure
* **`templates/AGENTS.md`**: ใส่คำสั่ง Build & Test สากล และตัดความซ้ำซ้อนโดยชี้ Pointer ไปที่ `CONSTRAINTS.md`
* **`templates/CONSTRAINTS.md`**: ศูนย์รวมเกณฑ์คุณภาพและ Anti-patterns

### 4. Custom Skill (`skills/custom/keyboard-layout-fixer/`)
* สร้างสกิลแปลงภาษาไทย Kedmanee <-> อังกฤษ QWERTY พร้อมแก้ CapsLock สลับ ตรงตามมาตรฐาน Anthropic Skill Standard พร้อม Automated Tests 100%

### 5. Git Security & Hooks (`.githooks/`)
* **`pre-commit`**: ตรวจจับ secret ป้องกัน `.env*` หลุด, บังคับ LF, รัน `haws.sh doctor`
* **`pre-push`**: บล็อกการ push อัตโนมัติ ("Push github ต้องผ่านผมก่อน") เว้นแต่มี `HAWS_ALLOW_PUSH=1`

---

## 📋 4. Traceability: 39 ข้อความต้องการเดิม สู่ 22 หัวข้อหลัก

| Domain | Master Topic | Raw User Inputs (#) | Status | Key Artifact / File |
| :--- | :--- | :---: | :---: | :--- |
| **Domain 1** | 1.1 Grounding & Anti-Hallucination | #9, #13 | ✅ ตรวจแล้ว | `core/HAWS.md` Sec 3.1, `core/WORK_INSTRUCTIONS.md` Sec 4.1 |
| | 1.2 Skill Usage Transparency | #8, #12 | ✅ ตรวจแล้ว | `core/HAWS.md` Sec 9.2, `agents/*.md` |
| | 1.3 Caveman Compression Standard | #28, #38 | ✅ ตรวจแล้ว | `core/HAWS.md` Sec 10, `core/USER_PREFERENCES.md` |
| | 1.4 Window Reload Notifications | #20 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md` Sec 4.2 |
| **Domain 2** | 2.1 Markdown Partitioning & Context | #2, #24 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md` Sec 1.1 |
| | 2.2 Token Budget vs Context Window | #23, #34 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md` Sec 1.1 (Streamlined) |
| | 2.3 On-Demand Loading & Lazy Context | #35 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md` Sec 1.1 |
| | 2.4 Telemetry & Metrics Tracking | #31 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md` Sec 1.1 |
| **Domain 3** | 3.1 Canonical Project Files (8 Blueprints) | #16 | ✅ ตรวจแล้ว | `templates/` (8 canonical files) |
| | 3.2 Architecture Graph ("Graft") | #17 | ✅ ตรวจแล้ว | `templates/ARCHITECTURE.md` (Mermaid + Archify) |
| | 3.3 Configuration & Secrets Management | #18 | ✅ ตรวจแล้ว | `core/ANTI_PATTERNS.md` |
| | 3.4 Design Standards & React Components | #1, #7 | ✅ ตรวจแล้ว | `templates/DESIGN.md`, `core/ANTI_PATTERNS.md` |
| | 3.5 Repository Normalization (LF) | #21 | ✅ ตรวจแล้ว | `.gitattributes`, `haws.sh` |
| **Domain 4** | 4.1 Skill Taxonomy & Bloat Management | #3, #11 | ✅ ตรวจแล้ว | `core/SKILL_TAXONOMY.md`, `core/HAWS.md` Sec 9 |
| | 4.2 Organizer Role & Hygiene | #10 | ✅ ตรวจแล้ว | `agents/organizer.md`, `haws.sh doctor` |
| | 4.3 Subagents, Personas & Harness | #14, #30, #36 | ✅ ตรวจแล้ว & คอนเฟิร์ม | `agents/*.md` (`<task_assignment>` / `<task_report>`), Ponytail 7-Rung Ladder |
| | 4.4 Self-Correcting Loops & Engineering | #33, #39 | ✅ ตรวจแล้ว & คอนเฟิร์ม | `core/HAWS.md` Sec 7.1 (Max 3 iterations, no test bypassing) |
| | 4.5 Candidate Custom Skills | #19, #22 | ✅ ตรวจแล้ว & คอนเฟิร์ม | `skills/custom/keyboard-layout-fixer/` (ล็อค 4 เคส + เช็คคำ/ตัวย่อ ไม่เพิ่มอะไรเกินจำเป็น) |
| **Domain 5** | 5.1 Ready-to-Use Installation Guide | #5 | ✅ ตรวจแล้ว | `docs/INSTALLATION.md`, `haws.sh setup` |
| | 5.2 Diagnostic Verification Suite | #6 | ✅ ตรวจแล้ว | `haws.sh doctor` (27/27 checks PASS) |
| | 5.3 SWE Fundamentals & Testing Discipline | #27, #32 | ✅ ตรวจแล้ว | `core/HAWS.md` Sec 5.1, Sec 7.1 |
| | 5.4 MCP & RAG Integrations | #25, #29 | ✅ ตรวจแล้ว | `core/WORK_INSTRUCTIONS.md`, `core/HAWS.md` Sec 9 |
| | 5.5 External Knowledge & Starred Repos | #4, #15 | ✅ ตรวจแล้ว | Direct upstream references in `core/HAWS.md` Sec 5.1 (Ponytail ladder) + `plugins/` (No synthetic doc bloat) |
| | 5.6 HAWS Visual Dashboard | #26 | 🗑️ สั่งลบแล้ว | โฟลเดอร์ `dashboard/` ถูกลบถาวรตามคำสั่ง |
| **Domain 6 / Guardrail** | Git Remote Push Protection & Hooks | #37 | ✅ ตรวจแล้ว & คอนเฟิร์ม | คง 2 Hooks หลัก (`pre-commit`, `pre-push`), ห้าม Git push อัตโนมัติเด็ดขาด |

---

## 🚀 5. Actionable Roadmap & Checklist — Status: 100% COMPLETED

ทุกหัวข้อรีวิว การปรับแต่ง และสถาปัตยกรรมระบบใหม่เสร็จสมบูรณ์ 100%:
1. **การปรับแต่ง `keyboard-layout-fixer`**:
   - ✅ เคส 1: EN -> TH (`fdfd` -> `ดกดก`)
   - ✅ เคส 2: TH -> EN (`้ำสสน` -> `hello`)
   - ✅ เคส 3: Inverted CapsLock อังกฤษ (`hELLO wORLD` -> `Hello World`)
   - ✅ เคส 4: ลืมปิด CapsLock ขณะพิมพ์ไทย (`FDFD` -> `ดกดก`, `GRNHV` -> `เพื้อ`)
   - ✅ Safety Check: ตรวจ Acronym ภาษาอังกฤษทั่วไป (`API`, `SQL`, `HTML`, `README`, `JSON`) ไม่ถูกแปลงมั่ว
   - ✅ Automated Unit Tests: ผ่าน 100% (`node skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`)

2. **สถาปัตยกรรมระบบใหม่ (Symmetrical Cross-Device & Decoupled Brain)**:
   - ✅ ย้ายไฟล์ส่วนตัวไป `secondbrain/` (ใส่ใน `.gitignore` + ทำ Local Git Repo ในตัว)
   - ✅ สร้างเทมเพลตตั้งต้นใน `templates/` (`USER_PREFERENCES.example.md`, `ANTI_PATTERNS.example.md`)
   - ✅ เพิ่มคำสั่ง `haws.sh kit add / prune` พร้อม `.gitmodules merge=ours`
   - ✅ เพิ่มระบบ 1-Click Symmetrical Cross-Device Sync (`haws.sh user connect/disconnect/status`)
   - ✅ สร้าง Windows Launcher `brain-online.bat` (ตรวจจับ Git Bash อัตโนมัติ)
   - ✅ เพิ่ม SWE Blueprints (`Dockerfile.template`, `.dockerignore.template`, `docker-compose.yml.template`, `vite.config.ts.template`, `.devcontainer/devcontainer.json`)
   - ✅ รวมคู่มือลง `README.md` หน้าแรก
   - ✅ รัน `haws.sh doctor` ตรวจสอบ 37/37 checks ผ่าน 100% (Zero Errors)


