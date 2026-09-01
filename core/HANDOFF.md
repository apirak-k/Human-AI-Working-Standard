# Handoff & Checkpoint — Human-AI Working Standard (HAWS)

## 📌 สรุปบริบทและเป้าหมายของเซสชันนี้ (Current Goal & Context)
บันทึกประเด็นการพูดคุย การตัดสินใจเชิงสถาปัตยกรรม การทดสอบระบบ และแนวทางการตรวจสอบเมื่อนำไปติดตั้ง/ทดสอบที่บ้าน เพื่อให้ผู้ใช้สามารถตรวจสอบความถูกต้องทั้งหมดได้อย่างครบถ้วน 100%

---

## 🗣️ ประเด็นสำคัญทั้งหมดที่พูดคุยและตกลงร่วมกัน (Key Discussion Points & Clarifications)

### 1. ขอบเขตการติดตั้งแบบ Global ทั้งเครื่อง (Global Installation Scope)
- การติดตั้งผ่าน `bash install.sh` หรือ `curl ... | bash` เป็นแบบ **Global ทั้งเครื่อง 100%**
- ไฟล์ถูกเชื่อมโยงไปยัง Home Directory ของผู้ใช้ (`~/.claude/` และ `~/.gemini/`)
- ทุกโปรเจกต์ในเครื่อง ไม่ว่าจะเปิดโฟลเดอร์ไหน ไดรฟ์ไหน จะมองเห็นกฎ HAWS, Second Brain, Subagents ทั้ง 4 ตัว และคลัง Skills ทั้งหมดโดยอัตโนมัติ

### 2. หลักการใช้งาน SKILL: คนใช้ผ่าน Slash Command vs AI ใช้แบบ Auto (Dual-Mode Invocation)
- **สำหรับคน (Human)**: ทุกสกิลที่มีไฟล์ `SKILL.md` จะกลายเป็นคำสั่ง **Slash Command (`/<ชื่อสกิล>`)** ให้พิมพ์เรียกใช้งานได้โดยตรงในแชท
- **สำหรับ AI (Main Agent & Subagents)**: สามารถตรวจจับบริบทงานและหยิบสกิลที่เกี่ยวข้องมาใช้งานเบื้องหลังได้เองแบบ **อัตโนมัติ (Auto-Skill)** แม้ผู้ใช้จะไม่ได้พิมพ์ Slash Command
- **การเรียกใช้สกิลของ Subagent**: ใช้หลักการเดียวกับ Main Agent คือมีความยืดหยุ่นตามบริบทหน้างาน (Recommended Skills) ไม่บังคับตายตัว เพื่อประหยัด Token และทำงานได้รวดเร็ว

### 3. ชี้แจงเรื่องชื่อคำสั่งของ Superpowers และ Taste Skill
- สกิลของ Superpowers ในระบบ Antigravity จะยึดชื่อตามฟังก์ชันจริง (ไม่มีคำว่า `superpowers-` นำหน้า) เช่น:
  - `/using-superpowers` (สกิลแม่บท บังคับวินัยวิศวกรรม)
  - `/brainstorming` (ระดมสมองและร่าง Spec)
  - `/writing-plans` (ซอยแผนงานย่อย)
  - `/test-driven-development` (บังคับเขียนเทส TDD)
  - `/systematic-debugging` (แกะรอยบั๊กเป็นระบบ)
  - `/verification-before-completion` (ตรวจหลักฐานเทสผ่านจริง)
- สกิล `taste-skill` ได้รับการปรับแก้ `name: taste-skill` ในหัวไฟล์เรียบร้อยแล้ว ทำให้สามารถพิมพ์คำสั่ง **`/taste-skill`** ได้ตรงตัว

### 4. กฎเกณฑ์คัดกรองขนาด Skill Pack (> 100 Skills Threshold Rule)
- **Core Packs ($\le 100$ สกิล)**: Superpowers (14), Anthropic (19), Addy Osmani (25), Matt Pocock (37), Single Skills (7) รวม **102 สกิลหลักระดับพรีเมียม** ➔ ระบบติดตั้งและสร้าง Slash Command ให้ทันทีอัตโนมัติ
- **Mega Packs ($> 100$ สกิล เช่น ECC ~900 ตัว)**:
  - ค่าเริ่มต้นจะเก็บไฟล์จริงไว้ใน `skills/ecc` เพื่อให้ AI ค้นหาความรู้เฉพาะทางได้ โดยไม่เอามาสร้าง Slash Command ให้รกหน้าจอแชท
  - หากต้องการติดตั้งทั้งหมด สามารถใช้คำสั่ง `bash install.sh --all-skills` หรือดึงเฉพาะสกิลย่อยที่สนใจมาใช้งานได้ตามคู่มือ `core/ADDON_GUIDE.md`

### 5. สกิลสร้างสกิลของ Anthropic (`skill-creator`)
- ยืนยันว่า **มีอยู่จริง 100%** ในแพ็กเกจ `anthropics-skills`
- สามารถพิมพ์เรียกใช้งานผ่าน Slash Command: **`/skill-creator`**

---

## 🛠️ งานที่ดำเนินการเสร็จสิ้นทั้งหมด (Completed Work)

1. **รวม Subagents ไว้ที่เดียว (`agents/`)**:
   - `frontend-engineer.md`, `backend-engineer.md`, `tester.md`, `researcher.md`
   - รองรับทุกค่าย AI (YAML frontmatter: `model: inherit`, `tools: [...]`)
2. **ลบไฟล์เก่า/ซ้ำซ้อนออกหมดจด**:
   - ลบ `agents-claude-code/`, `agents-antigravity/`, `plugins/`, `.claude-plugin/`, และไฟล์ Prompt เก่าทิ้งทั้งหมด
3. **ผสานระบบ Second Brain เข้าสู่แกนกลาง**:
   - `core/USER_PREFERENCES.md` (สไตล์การสื่อสาร chat-first, มาตรฐาน UI/UX)
   - `core/ANTI_PATTERNS.md` (ข้อห้าม, กฎเหล็ก, บันทึกบทเรียน `/learn`)
   - `core/ADDON_GUIDE.md` (คู่มือการสร้างและเพิ่ม Skill / Subagent)
4. **อัปเกรดสคริปต์ติดตั้งและอัปเดต (`install.sh` & `update.sh`)**:
   - เพิ่มระบบดึง Git Submodule อัตโนมัติตั้งแต่เริ่มรัน
   - เพิ่มระบบ Smart Recursive Flattener แตกโฟลเดอร์ซ้อนลึก 1-level deep
   - แก้ไขไวยากรณ์ Bash `local` และแก้ปัญหา Conflict
5. **ดาวน์โหลดและเชื่อมโยงคลัง SKILL ครบถ้วน**:
   - Single Skills (7)
   - Superpowers (14)
   - Anthropic Skills (19) รวม `skill-creator`
   - Addy Osmani Agent Skills (25)
   - Matt Pocock Skills (37) รวม `grill-me`
   - ECC Frameworks & Stacks (379 unique English / 898 total)
6. **การทดสอบจริงเชิงประจักษ์ (Empirical Live Testing)**:
   - `install.sh` และ `update.sh`: **Exit Code 0, Warnings 0, Errors 0**
   - ทดสอบ Antigravity Global Pointer: โหลด `<RULE[user_global]>` อัตโนมัติหลังรีสตาร์ท
   - ทดสอบส่งงาน Subagent จริง: `tester` (รัน QA Audit ผ่าน 100%) และ `researcher` (นับบรรทัดถูกต้อง)

---

## 🏠 เช็กลิสต์สำหรับตรวจสอบที่บ้าน (Home Machine Verification Checklist)

เมื่อนำ HAWS ไปติดตั้งและทดสอบบนคอมพิวเตอร์ที่บ้าน ให้ตรวจสอบตามลำดับดังนี้:

- [ ] **1. รันคำสั่งติดตั้ง**: `bash install.sh` (หรือ `curl -fsSL ... | bash`)
- [ ] **2. ตรวจสอบ Global Pointer**: เช็กว่ามีบล็อก `<!-- HAWS_GLOBAL_POINTER_START -->` ใน `~/.claude/CLAUDE.md` และ `~/.gemini/GEMINI.md`
- [ ] **3. ตรวจสอบ Subagents**: เช็กว่ามีไฟล์ใน `~/.claude/agents/` (4 ไฟล์) และ `~/.gemini/config/agents/` (4 โฟลเดอร์)
- [ ] **4. ตรวจสอบและทดสอบ Slash Commands**:
  - ทดสอบ `/using-superpowers`, `/brainstorming`, `/test-driven-development`, `/systematic-debugging`
  - ทดสอบ `/skill-creator` (ของ Anthropic)
  - ทดสอบ `/grill-me` (ของ Matt Pocock)
  - ทดสอบ `/taste-skill`, `/ui-ux-pro-max`, `/drawio`, `/caveman`, `/humanizer`
  - ทดสอบ `/security-review` (ของ ECC)
- [ ] **5. ทดสอบการสั่งงาน Subagent**: ลองส่งงานให้ `tester` หรือ `researcher` ทำงานในเบื้องหลัง

---

## 🎯 สถานะปัจจุบัน (Exact Resume Point)
ระบบ HAWS, Subagents และ Skills ทั้งหมด อยู่ในสถานะ **เสร็จสมบูรณ์ 100% พร้อมทดสอบและใช้งานจริง** ครับ!
