# HAWS DEV Workflow — มาตรฐานการพัฒนาและปรับปรุงต้นทาง

> **Status**: Official Developer & Core Maintainer Standard  
> **Target Audience**: Core Maintainers, Developers, and Coding AI Agents  
> **Applies To**: `Human-AI-Working-Standard` Upstream Core Development  

---

## 1. ปรัชญาและเป้าหมายหลัก (Core Philosophy)

1. **Zero Contamination (Main ต้องบริสุทธิ์เสมอ)**:
   - Branch `main` คือสภาพแวดล้อม Production-Ready ที่เสถียร 100% มีไว้ให้ผู้ใช้ทั่วไปและระบบนำไปติดตั้งใช้งานจริง ห้ามทดลองหรือแก้ไขโค้ดดิบลงบน `main` โดยเด็ดขาด
2. **Feature Isolation (แยกงานเป็นเอกเทศ)**:
   - แต่ละฟีเจอร์หรือการแก้ไขต้องทำบนกิ่งแยก (`feature/*` หรือ `fix/*`) เพื่อให้สามารถทดสอบ ทิ้ง หรือเลือกเฉพาะของที่สมบูรณ์เข้าสู่ระบบได้โดยไม่พันกัน
3. **Evidence-First Gatekeeping (ประจักษ์พยานก่อนคำกล่าวอ้าง)**:
   - โค้ดจะถือว่า "ผ่าน" ก็ต่อเมื่อมีผลการรันชุดทดสอบ (Exit Code 0) ยืนยันจริง ห้ามสรุปว่าโค้ดใช้งานได้ด้วยการคาดเดา
4. **Decoupled Personal State (ไม่ปะปนข้อมูลส่วนบุคคล)**:
   - โฟลเดอร์ `secondbrain/` เป็น Private Repository ของผู้ใช้ ห้ามให้โค้ดใหม่ของ HAWS ไปยุ่งเกี่ยว บันทึกข้อมูลทับ หรือดึงค่าส่วนบุคคลหลุดเข้าไปใน Upstream Git History

---

## 2. วงจรการพัฒนา 6 ขั้นตอน (The 6-Phase DEV Lifecycle)

```
[1. คัดเลือกงานจาก Backlog]
       │ (เลือกจาก 66 Topics หรือ Starred Repos Backlog)
       ▼
[2. แยก Feature Branch]
       │ git switch -c feature/<topic-name>
       ▼
[3. พัฒนาด้วย TDD & Minimal Code]
       │ เขียนเทสต์ -> เขียนโค้ด -> ขัดเกลา (Red-Green-Refactor)
       ▼
[4. ผ่านด่านคัดกรอง (Pre-Merge Gate)]
       │ รันเช็ค 4 ด่าน (Syntax, Test Suite, Clean Files, Docs)
       ▼
[5. รวมเข้า DEV Branch เพื่อทดสอบภาพรวม]
       │ git switch dev/standards-and-docs && git merge feature/<topic-name>
       ▼
[6. นำ "ของดี" ขึ้น Main (Production Promotion)]
         ผ่าน PR บน GitHub หรือ Fast-forward เมื่อเสร็จสมบูรณ์
```

---

### ขั้นที่ 1: การคัดเลือกงาน (Task Intake)
- เลือกหัวข้อที่ต้องการพัฒนาจากเอกสารทางการใน `docs/`:
  - **รีโปติดดาว**: [`docs/STARRED_REPOSITORIES_BACKLOG.md`](file:///E:/Human-AI-Working-Standard/docs/STARRED_REPOSITORIES_BACKLOG.md) (Tier 1-4)
  - **แผนแม่บท 66 ข้อ**: [`docs/MASTER_AGENDA_66_TOPICS.md`](file:///E:/Human-AI-Working-Standard/docs/MASTER_AGENDA_66_TOPICS.md)
  - **แผนงานเดิม 5 โดเมน**: [`docs/ORIGINAL_PLAN_39_DOMAINS.md`](file:///E:/Human-AI-Working-Standard/docs/ORIGINAL_PLAN_39_DOMAINS.md)
- กำหนดขอบเขตงานให้กระชับ ไม่ทำหลายเรื่องพร้อมกันในหนึ่งรอบ

### ขั้นที่ 2: การแตกกิ่งงาน (Branching Strategy)
- สร้างกิ่งย่อยจาก `dev/standards-and-docs`:
  ```bash
  git switch dev/standards-and-docs
  git pull origin dev/standards-and-docs
  git switch -c feature/<feature-name>
  ```
  *(ตัวอย่างชื่อกิ่ง: `feature/diagram-design`, `feature/notebooklm-agent`, `fix/tui-cursor-jump`)*

### ขั้นที่ 3: การพัฒนา (Implementation & TDD)
- **Test-Driven**: สร้างหรือปรับปรุงชุดทดสอบใน `tests/` หรือ `ai-configs/` ก่อน เพื่อดักจับพฤติกรรมที่ต้องการ
- **Ponytail / Minimalism**: พยายามใช้ Standard Library และคำสั่งพื้นฐานก่อนเพิ่ม Library หรือ Dependency ใหม่เข้าสู่ระบบ
- **Preserve Comments**: ห้ามลบคอมเมนต์ Docstrings หรือคำอธิบายโค้ดเดิมโดยไม่มีเหตุผลอันควร

### ขั้นที่ 4: ด่านตรวจคุณภาพ (Quality Gatekeeper)
ก่อนรวมงานกลับเข้าสู่กิ่งหลัก ต้องผ่านการตรวจครบทั้ง 4 มิติ:

1. **Syntax Integrity**:
   ```bash
   bash -n haws.sh
   ```
2. **Automated Tests**:
   ```bash
   bash tests/cli/run.sh
   node --test ai-configs/codex/agents.test.mjs tests/windows_launcher_execution.test.mjs
   ```
3. **No Scratch / Temp Leaks**:
   - ตรวจ `git status` ต้องไม่มีไฟล์ทดลองรัน เช่น `.tmp`, `scratch/`, หรือ log ตกค้าง
   - ตรวจ whitespace และ line endings ด้วย `git diff --check`
4. **Docs & Changelog**:
   - อัปเดตเอกสารที่เกี่ยวข้องใน `docs/` หรือ `README.md`

### ขั้นที่ 5: การรวมเข้า DEV (`dev/standards-and-docs`)
เมื่อกิ่งฟีเจอร์ผ่านด่านตรวจครบ 100%:
```bash
git switch dev/standards-and-docs
git merge feature/<feature-name>
git push origin dev/standards-and-docs
git branch -d feature/<feature-name>
```

### ขั้นที่ 6: การส่งของดีขึ้นสู่ Main (Production Promotion)
เมื่อสะสมการพัฒนาบน `dev/standards-and-docs` จนได้ฟังก์ชันที่เสถียรและต้องการปล่อยให้ผู้ใช้ทั่วไป:

#### วิธีที่ A: ส่งผ่าน Pull Request บน GitHub (แนะนำที่สุด)
1. เปิด PR จาก `dev/standards-and-docs` สู่ `main`
2. ใส่สรุป Changelog แสดงฟังก์ชันใหม่และผลการทดสอบ
3. กด Merge แล้วดึง `main` ลงสู่ Local

#### วิธีที่ B: รวมตรงใน Local (เมื่อทดสอบผ่าน 100% แล้ว)
```bash
git switch main
git merge --ff-only dev/standards-and-docs
git push origin main
git switch dev/standards-and-docs
```

---

## 3. สิ่งที่ห้ามทำเด็ดขาด (Anti-Patterns Checklist)

- ❌ **ห้าม Commit ลง `main` โดยตรง**: ทุกการเปลี่ยนแปลงต้องเริ่มที่กิ่ง Feature หรือ DEV เสมอ
- ❌ **ห้ามผลักดันของที่ "เทสต์ยังแดง" ขึ้น Main**: ถ้ายังไม่ผ่าน ให้ค้างไว้ที่ DEV จนกว่าจะแก้เสร็จ
- ❌ **ห้ามดันไฟล์ขยะ / Secret / ข้อมูลส่วนตัว**: ตรวจสอบ `git status` ทุกครั้งก่อน `git add`
- ❌ **ห้ามเปลี่ยนโค้ดโดยไร้ประจักษ์พยาน**: ทุกครั้งที่อ้างว่า "เสร็จแล้ว" ต้องมีคำสั่งเทสต์และรหัสผลลัพธ์ Exit 0 ยืนยันเสมอ
