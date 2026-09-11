# HAWS Clean-Base Recovery Plan

**Status:** Locked plan  
**Date:** 2026-09-11  
**Recovery parent:** `99c0d9d`  
**Mixed reference commit:** `40f8fad`  
**Old known-good UX reference:** `codex/haws-bootstrap`  
**Old known-good interactive TUI reference:** `40f5f5a`

---

## 1. เป้าหมายที่ล็อกแล้ว

สร้าง HAWS ฐานใหม่โดย:

> **รักษารูปแบบการใช้งานเดิมที่ดี โดยเฉพาะ Windows 1-click `.bat` และ TUI แบบ interactive ที่ใช้งานดี แต่ใช้ flow ใหม่ ระบบใหม่ state ใหม่ และ shared core ใหม่ที่พัฒนามาทีหลัง**

หลักสำคัญ:

- Windows และ macOS/Linux **ไม่จำเป็นต้องมี launcher แบบเดียวกัน**
- แต่ต้องได้ **feature, flow, behavior และผลลัพธ์เดียวกัน**
- Windows ยอมให้ใช้ `.bat` เป็น first-class entrypoint
- macOS/Linux ใช้ shell entrypoint ที่เหมาะกับ OS
- launcher ต้องเป็น **thin launcher** ไม่ duplicate business logic
- core/behavior ที่ใช้จริงต้อง shared กัน
- ห้ามเอา implementation ที่ regress แล้วมาปรับให้ “ดูคล้าย” UX เดิม
- ถ้ามี known-good behavior เดิม ให้ใช้ของเดิมเป็น reference ก่อน

---

## 2. คำว่า “TUI แบบเก่าที่ต้องการ” หมายถึงอะไร

ในแผนนี้ **TUI ไม่ได้หมายถึงแค่คำว่า redraw**

สิ่งที่ต้องรักษาคือ **known-good interactive TUI experience จาก 1-click workflow เก่า**:

- เปิดแล้วได้ interactive terminal menu
- ใช้ `↑` / `↓` เลือก
- ใช้ Enter ยืนยัน
- checklist ใช้ Space ตามจุดที่เหมาะสม
- selection เปลี่ยนใน menu surface เดิม
- ไม่พิมพ์ menu frame ซ้ำกองลง terminal
- ไม่สร้าง flicker/clear ที่รบกวนโดยไม่จำเป็น
- interaction ต้องรู้สึกเหมือนโปรแกรม TUI จริง ไม่ใช่ output หลายเฟรมที่ถูกซ่อนให้ดูเร็ว

### Reference ที่ AI ต้องไปดูก่อนแก้ TUI

1. Branch: `codex/haws-bootstrap`
2. Windows launcher reference:
   - `1-CLICK-SYNC.bat`
   - `SETUP.bat`
3. Interactive arrow-key behavior reference:
   - commit `40f5f5a`
   - `feat(kit): add interactive arrow-key checklist ...`

**สำคัญ:**  
ให้อ้างอิง **interaction behavior / launcher pattern** เท่านั้น  
**ห้าม copy old product flow กลับมา**

Old flow เช่น:

```text
double-click
→ auto setup หรือ auto sync
→ doctor
```

ไม่ใช่ flow ใหม่ที่ต้องการ

---

## 3. Flow ใหม่ที่ต้องรักษา

### First run

```text
Launch HAWS
    ↓
Settings
    ↓
แก้เฉพาะ Draft
    ↓
Preview
    ↓
Save & Apply
    ↓
Home
```

### Installed

```text
Launch HAWS
    ↓
Home
 ├─ Settings
 ├─ Sync
 ├─ Status
 ├─ Doctor
 └─ Exit
```

### Semantics ที่ล็อกแล้ว

- Settings แก้ draft ก่อน
- ไม่มี persistent change ก่อน Apply
- Preview ต้องมีทางเลือกชัดเจน เช่น Apply / Back / Cancel
- Back รักษา draft
- Cancel ทิ้ง draft
- Sync เป็น explicit action
- bare launch ห้าม auto-sync
- Status เป็น local/read-only
- Doctor เป็น local/read-only diagnostic
- Doctor ห้าม recursion
- เปิด Settings เฉย ๆ ไม่ควรทำ network operation ที่ไม่จำเป็น

---

## 4. ของใหม่อะไรที่เก็บ

ไม่ต้อง rebuild ระบบทั้งหมดใหม่

`99c0d9d` คือฐานของ new flow/system อยู่แล้ว ดังนั้น state, ownership และ flow หลักที่มีในฐาน **ให้ preserve** เว้นแต่มี defect ที่เกี่ยวข้องกับ task โดยตรง

จากงานหลัง `99c0d9d` ให้คัดเฉพาะของดี เช่น:

- UX correction ที่ตรงกับ flow ใหม่
- visible loading / progress feedback
- คำอธิบายสั้น ๆ และ counts ที่ช่วยให้เข้าใจ menu
- Skills UX:
  - Single Skills
  - Multi-Skill Packs
  - pack picker
  - pack-local checklist
  - counts จาก draft ปัจจุบัน
- Preview actions ที่ชัดเจน
- Apply → Home ที่ถูกต้อง
- ไม่แสดง Home ซ้ำ
- responsiveness / lazy loading / caching ที่เป็น improvement จริง
- pre-commit loop fix
- `run_doctor` recursion fix
- regression tests ที่ปกป้อง behavior ข้างต้น

### สิ่งที่มีใน new base อยู่แล้วและต้อง preserve

- install/settings state
- draft-before-Apply
- ownership-aware behavior
- AI Environment selection
- Skills state
- Repository configuration
- Sync / Status / Doctor product semantics
- Second Brain / Auto Update configuration ที่เป็นส่วนของ new flow

รายการเหล่านี้ **ไม่ใช่งานใหม่แยกสิบก้อน**  
ให้ถือว่าเป็นส่วนของ new system ที่มีอยู่แล้วในฐาน และห้าม AI redesign โดยไม่มีเหตุจำเป็น

---

## 5. สิ่งที่ไม่เอาจากทางที่เดินผิด

อย่า carry forward งานที่เกิดจาก assumption ว่า:

> “ทุก OS ต้องมี launcher/entry implementation เดียวกัน”

ไม่เอาเป็นฐาน:

- การบังคับ Windows ให้ผู้ใช้เปิด Git Bash เอง
- workaround เพื่อทำ Windows ให้เหมือน Unix
- console-entry experiment ที่เกิดจาก assumption ดังกล่าว
- `command_integration` / DOSKey / AutoRun approach ถ้ามีไว้เพื่อฝืนความเหมือน
- tests/docs ที่บังคับว่าห้ามมี platform-specific launcher
- old 1-click auto-sync flow
- business logic ที่ duplicate อยู่ใน `.bat`
- OS experiment จาก `40f8fad` เพียงเพราะอยู่ใน commit เดียวกับ UX/loop fix

กฎคือ:

> **เก็บ behavior ที่ดี ไม่ใช่เก็บ commit ทั้งก้อน**

---

# 6. แผนทำงานทีละขั้น

## STEP 1 — สร้าง Clean Core + TUI Base

### Starting point

`99c0d9d`

### ใส่กลับเฉพาะ

```text
99c0d9d
+ approved UX corrections
+ loading / short explanations
+ Skills UX corrections
+ known-good TUI interaction behavior
+ loop fixes
- OS/console-entry wrong-turn work
```

### ยังไม่ทำ

- Windows `.bat` ใหม่
- PATH / command convenience
- DOSKey / AutoRun
- docs rewrite ใหญ่
- OS redesign อื่น

### Acceptance

ต้องยืนยันว่า:

- commit ได้โดยไม่ loop/hang
- First run → Settings
- Installed → Home
- Settings ใช้ draft
- Preview / Apply / Back / Cancel ถูกต้อง
- Apply เข้า Home ถูกต้อง
- TUI interactive แบบ known-good reference
- menu ไม่กอง duplicate frames
- loading feedback ชัด
- Skills hierarchy ถูก
- Status / Doctor local/read-only
- ไม่มี OS experiment เก่าหลุดเข้ามา
- relevant tests ผ่าน

### STOP CONDITION

เมื่อ Step 1 ผ่าน **ให้หยุด**

ห้ามทำ `.bat` ต่ออัตโนมัติ

จากนั้นผู้ใช้ต้องทดลองและ approve Clean Base ก่อน

---

## STEP 2 — User Acceptance ของ Clean Base

ผู้ใช้ทดลอง:

- TUI feel
- arrow navigation
- Settings
- Skills
- loading messages
- Preview
- Apply
- Home
- Status
- Doctor
- Sync flow

ถ้าพบ defect:

> แก้ defect ของ Step 1 เท่านั้น

ห้ามเริ่ม OS layer เพื่อกลบ defect ใน core/TUI

เมื่อผู้ใช้ approve → สร้าง Clean Base checkpoint

---

## STEP 3 — Windows `.bat` First-Class Entry

เริ่มจาก **approved Clean Base เท่านั้น**

### Goal

สร้าง Windows entry experience แบบเดิมที่สะดวก:

```text
double-click haws.bat
        ↓
หา runtime ที่จำเป็นเอง
        ↓
เข้า shared HAWS
        ↓
NEW flow / NEW TUI
```

### `.bat` ทำได้

- `cd` ไป repository root
- หา Bash/runtime ที่จำเป็น
- forward arguments
- เรียก shared HAWS entry/core
- propagate exit code
- แสดง dependency error ที่เข้าใจง่าย

### `.bat` ห้ามทำ

- duplicate Settings logic
- duplicate Sync logic
- duplicate Doctor logic
- duplicate state model
- วาด TUI ระบบใหม่ของตัวเอง
- auto-sync เพียงเพราะ double-click

### Command parity ที่ต้องได้

```text
Windows                 macOS/Linux
haws.bat                ./haws.sh
haws.bat settings       ./haws.sh settings
haws.bat sync           ./haws.sh sync
haws.bat status         ./haws.sh status
haws.bat doctor         ./haws.sh doctor
```

Bare launch ต้องเหมือนกันในเชิง product flow:

```text
First run  → Settings
Installed  → Home
```

เมื่อผ่าน → หยุดและให้ผู้ใช้ตรวจ

---

## STEP 4 — Cross-Platform Parity

ตรวจ Windows / macOS / Linux ว่า:

| Behavior | Windows | macOS/Linux |
|---|---|---|
| First run | same | same |
| Home | same | same |
| TUI behavior | same experience | same experience |
| Settings | same | same |
| Preview/Apply | same | same |
| Sync | same | same |
| Status | same | same |
| Doctor | same | same |
| Errors | equivalent | equivalent |

OS-specific implementation ต่างกันได้  
product behavior ต่างกันไม่ได้

---

## STEP 5 — Docs + Final Validation + Merge Decision

หลัง implementation เสถียรแล้วเท่านั้น:

- README แยกวิธีเริ่มใช้งานตาม OS
- อธิบายว่า launcher ต่าง แต่ HAWS behavior/core เดียวกัน
- ลบคำแนะนำเก่าที่บังคับ Windows เปิด Git Bash เอง
- run full regression
- human acceptance
- ตัดสินใจ merge เข้า `main`

---

# 7. Git / Branch / History Strategy

## ห้ามทำ

- ห้าม reset/rewrite branch เก่า
- ห้าม force-push history เก่า
- ห้ามลบ `codex/haws-cli-task1`
- ห้ามลบ `codex/haws-bootstrap`
- ห้าม cherry-pick `40f8fad` ทั้งก้อน

กิ่งเก่าเก็บไว้เป็น **reference/history**

## Recovery branch

สร้างจาก `99c0d9d`:

```bash
git status
git switch -c recovery/clean-base 99c0d9d
```

ถ้า `git status` ไม่ clean ให้หยุดก่อน

ถ้า branch มีอยู่แล้ว:

```bash
git switch recovery/clean-base
```

## วิธีนำงานกลับ

ใช้ **scoped patch/diff** จากแต่ละ Step แทนการเอา mixed commit ทั้งก้อน

Workflow:

```text
old branches/history      → เก็บครบ
99c0d9d                    → recovery parent
recovery/clean-base        → งานใหม่
patch เฉพาะ Step           → inspect
test                        → user approve
commit                      → checkpoint
```

เป้าหมาย history:

```text
99c0d9d
   ↓
[Step 1 recovery commits]
   ↓
CLEAN BASE
   ↓
Windows .bat
   ↓
Cross-platform parity
   ↓
Docs/final
```

---

# 8. วิธีใช้ AI โดยไม่ให้ Context บวม

หนึ่ง session / หนึ่ง task ที่มีขอบเขตชัด

ทุก task ต้องให้ข้อมูลแค่:

```text
BASE COMMIT:
<commit>

CURRENT STEP:
<step>

GOAL:
<one goal>

MUST KEEP:
<approved behavior>

MUST NOT CHANGE:
<approved layers>

REFERENCES:
<specific branch/commit/file>

ACCEPTANCE:
<tests/behavior>

STOP WHEN:
<clear stop condition>
```

## Global AI Rule

> **If completing the current task appears to require redesigning a previously approved layer, STOP and report the conflict. Do not redesign that layer automatically.**

และ:

> **Do not replace a known-good UX mechanism with a new mechanism merely to approximate the same visual result. Inspect the known-good reference first.**

---

# 9. ChatGPT / Antigravity / Codex

Codex ไม่จำเป็นสำหรับ recovery นี้

### ChatGPT

เหมาะกับ:

- อ่าน ZIP snapshot
- เทียบ history/reference
- สร้าง scoped patch
- ตรวจ diff
- รัน tests ที่ทำได้ใน workspace
- คืน patch + apply instructions

### Antigravity

ใช้ได้ แต่ควรใช้เมื่อ Step ถูกล็อกแล้ว

ให้สั่ง **แคบมาก** เช่น:

```text
ทำ Step 1 เท่านั้น
Base = <commit>
ใช้ plan นี้เป็น contract
ห้ามทำ Step 2
ห้าม redesign approved flow/TUI/state
ถ้าต้องออกนอก scope ให้ STOP
รันเฉพาะ acceptance tests ที่ระบุ
```

ไม่ควรสั่ง:

> “แก้ HAWS ให้ cross-platform และ UX ดีทั้งหมด”

ใน prompt เดียว

---

# 10. References

### New-flow recovery parent

- `99c0d9d`
- `wip(cli): checkpoint approved UX implementation and handoff`

### Mixed later work

- `40f8fad`
- มีทั้ง UX correction, loop fix และ OS/console-entry experiment ปนอยู่
- ใช้เป็น **source/reference** ไม่ใช่ commit ที่ต้อง cherry-pick ทั้งก้อน

### Old known-good Windows/TUI reference

- Branch: `codex/haws-bootstrap`
- Files:
  - `1-CLICK-SYNC.bat`
  - `SETUP.bat`
- Interactive TUI behavior:
  - commit `40f5f5a`

---

# 11. ขั้นถัดไปทันที

1. เก็บแผนนี้เป็น contract
2. ใน repo จริง ตรวจ:
   ```bash
   git status
   ```
3. ถ้า clean:
   ```bash
   git switch -c recovery/clean-base 99c0d9d
   ```
4. หยุดตรงนั้น
5. สร้าง **Step 1 scoped patch ใหม่** จาก ZIP/reference
6. `git apply --check`
7. inspect diff + tests
8. ผู้ใช้ทดลอง TUI/flow
9. เมื่อ approve แล้วจึง commit Clean Base
10. ค่อยเปิด Step 3 เรื่อง Windows `.bat`

---

## One-line summary

> **เอา new HAWS system/flow เป็นฐาน, กู้ของดีที่ทำต่อมาและ loop fix, รักษา known-good old 1-click TUI experience, ตัด OS wrong-turn work ออก, แล้วค่อยเพิ่ม Windows `.bat` ใหม่เป็น thin native entry หลัง Clean Base ผ่านการยืนยันแล้ว**
