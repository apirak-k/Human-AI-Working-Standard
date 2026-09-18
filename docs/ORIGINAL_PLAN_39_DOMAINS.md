# HAWS Improvement Master Plan & Review Notebook

> **Status**: 🎉 100% REVIEW COMPLETE (All 22 Topics Succeeded)  
> **Orchestrator**: @organizer  
> **Workflow Protocols**: /grill-with-docs (grilling + domain-modeling) + /planning-with-files

---

## 📥 Raw Topics Input (Source of Truth — Verbatim)
รายการหัวข้อดิบทั้งหมดที่บันทึกตรงจาก User Input 100% โดยไม่มีการดัดแปลงหรือตัดทอน:

1. React Component
2. การจัดหมวดหมู่ Markdown เพื่อลด Context window
3. จัดหมวดหมู่ SKILL ที่ใช้ประจำ
4. รีวิวรีโปที่ผม STAR
5. คู่มือติดตั้ง HAWS ที่พร้อมจบ
6. ติดตั้งหรืออัพเดท 1 ทีเช็คอะไรบ้างรายงานอะไร
7. Check STANDARD design.md
8. Check auto use skill and subagent
9. AI Hallucination ต้องรายงานผลที่เกิดจริงของ Task ล่าสุดเป็น แหล่งที่เชื่อถือได้
10. Organize ต้องทำงานให้ดี 
11. จัดการ SKILL ที่เยอะเกิน
12. เวลาใช้สกิลบอกด้วยว่าใช้อะไร ในทุก AGENT
13. Best Practice
14. Sub Agent
15. Ponytail repo
16. ไฟล์ .md (Projectบอกว่าเราทำอะไร อะไรไม่ใช่งานนี้, Agent ใครทำไรได้ ห้ามทำไร, SOT soucre of truth ความจริงล่าสุดของงาน, Roadmap อยู่ตรงไหนและไปไหนต่อ, UX หน้าตาผลลัพควรเป็นแบบไหน)
17. Graft แผนที่ว่า code ตรงไหนเชื่อมอะไร
18. ไฟล์ .env
19. SKILL wayfinder seo
20. เรื่องถ้าอยากให้ Reload window ก็บอก
21. Normalize 
22. SKILL แก้ภาษาที่ลืมเปลี่ยน หรือ กด caplock
23. สถานะ Token ที่เป็นค่าจริง
24. Context window
25. RAG
26. Dashboard HAWS
27. SWE Fundamental 
28. ตอบแบบ Caveman ในคำถามปลายปิดเช่น ใช่หรือไม่ 
29. MCP
30. Persona (ของ Agent รึป่าว)
31. วิเคราะหรือสรุปเวลาที่ใช้คิด และจำนวนการใช้ SKILL
32. การเทสที่ดี
33. Loop Engineering
34. Token Management
35. Ondemand Loading
36. Agent harness
37. Push github ต้องผ่านผมก่อน
38. ละดับ Caveman
39. Skills/Commands ที่เกี่ยวข้อง: /grill-me, /teamwork-preview, /boost, /brainstorming, /teach, /loop-me, /wayfinder

---

## 🎯 Settled Decisions Summary (All Domains Finalized)
- [x] **Documentation & Review Strategy**: **Hybrid (Option C)**
- [x] **Git Remote Safeguard**: Strictly forbidden to auto-push to GitHub without human approval (Raw Item #37).
- [x] **Operational Shorthand Rule**: เมื่อผู้ใช้พิมพ์คำว่า "ต่อเลย" หรือ "ต่อ" จะถือว่าอนุมัติตามคำตอบที่แนะนำ (Recommended Answer) ของรอบนั้นทันที
- [x] **Domain 1 (Behavior & Honesty)**:
  - **1.1 Grounding & Anti-Hallucination**: บังคับแสดงหลักฐานเชิงประจักษ์ (Command/Test Output หรือ File Diff) หากไม่ตรวจต้องติดป้าย [Unverified] และรายงานปัญหาตรงไปตรงมาทันที
  - **1.2 Skill Usage Transparency**: แจ้งเตือนการใช้ Skill ที่บรรทัดแรกเสมอ (Applying /<skill>...) และ Subagent ทุกตัวต้องระบุ Skill ในรายงานส่งกลับมา
  - **1.3 Caveman Mode & Multi-Level Compression**: Default เป็น Caveman; คำถามปลายปิดใช้ Full/Ultra (เช่น *"ใช่"*, *"ผ่าน"*); รายงานสั้นใช้ Lite; งานวิเคราะห์ลึกคงความละเอียดสมบูรณ์
  - **1.4 Environment & Reload Notifications**: แจ้งเตือนภาษาอังกฤษ 100% พร้อมคีย์ลัดเมื่อมีการแก้ไขสภาพแวดล้อมหรือไฟล์คอนฟิก ([ACTION REQUIRED: RELOAD WINDOW]...)
- [x] **Domain 2 (Context & Token Economics)**:
  - **2.1 Markdown Architecture**: แยกไฟล์ย่อยแบบ Modular (~200-300 บรรทัด) ใช้ Summary + Pointer Pattern แบบ Progressive Disclosure
  - **2.2 Real-time Token Budget vs Context**: แยกตัวเลขชัดเจนระหว่าง Skill Budget (เพดาน 20k) กับ Model Context Window (เพดาน 1M); แจ้งเตือนเหลืองที่ 75% และเตือนแดงพร้อมเสนอทำ Handoff ที่ 90%
  - **2.3 On-Demand Loading & Lazy Context**: โหลดคู่มือเฉพาะทางแบบ Just-in-Time เมื่อถึงงาน; สรุปผลลัพธ์ลงดิสก์แล้วไม่ขุด Log เก่าซ้ำ
  - **2.4 Telemetry & Metrics Tracking**: บันทึก Thinking Time และจำนวน Skill ใน Milestone/Subagent reports; @organizer นำสถิติไปจัดกลุ่มและเสนอตัดทอนสกิลที่ไม่ใช้
- [x] **Domain 3 (Project Blueprints & SOT)**:
  - **3.1 Canonical Project Files**: สร้าง 	emplates/SOT.md เป็นศูนย์กลางความจริงล่าสุดของระบบเพื่อการ Cross-tool ราบรื่น, สร้าง 	emplates/AGENTS.md คุมสิทธิ์ Agent, และปรับปรุง 	emplates/PROJECT.md ให้มี Scope + Roadmap
  - **3.2 Architecture Dependency Graph ("Graft")**: เขียนแผนผังทิศทางข้อมูลเป็น Inline Mermaid ใน SOT.md และเชื่อมต่อสกิล graphify / drawio-skill
  - **3.3 Configuration & Secrets Management**: Strict .gitignore สำหรับ .env*, บังคับมี .env.example, และใช้ Startup Schema Validation ดักจับก่อนรัน
  - **3.4 Design Standards & React Components**: Hooks-First Clean Architecture (ตรรกะอยู่ใน Custom Hooks, JSX แสดงผลอย่างเดียว), ยึด Design Tokens ใน design.md, Fluid Responsive, และผ่าน WCAG 2.1 AA
  - **3.5 Repository Normalization**: บังคับ Line Endings LF ผ่าน .gitattributes และจัดระเบียบ Indentation 2 spaces ก่อน Commit
- [x] **Domain 4 (Skills & Automation Loops)**:
  - **4.1 Dynamic Taxonomy & Bloat Management**: แบ่งเป็น Core Active (~15-20 ตัว) กับ Domain Drawers (On-demand); สกิลไม่ใช้ถูกย้ายไป skills/archive/ เพื่อคืน Token
  - **4.2 Organizer Role & System Hygiene**: @organizer สแกนขยะและสถานะระบบเชิงรุกผ่าน ash haws.sh doctor (ตรวจ 6 แกน) และ ash haws.sh status (<0.5 วินาที)
  - **4.3 Subagents, Personas & Harness**: Persona ถูกนิยามเป็น Specialist Engineering Roles ใน gents/*.md; ส่งงานผ่าน <task_assignment> คืนงานผ่าน <task_report> แยก Context สะอาด
  - **4.4 Self-Correcting Loops**: ลูปแก้ตัวเองจำกัดเพดานไม่เกิน 3 รอบ; เกณฑ์การผ่านต้องเขียว 100% (Exit code 0) โดยไม่มีการซ่อน Error
  - **4.5 Candidate Custom Skills**: จัด wayfinder ไว้ใน Planning Drawer; สร้าง In-house Skill keyboard-layout-fixer แก้ภาษาไทย/อังกฤษและ CapsLock กลับหัวอัตโนมัติ
- [x] **Domain 5 (Installation & Ecosystem)**:
  - **5.1 Ready-to-use Installation Guide**: คู่มือ docs/INSTALLATION.md รองรับคำสั่งเดียวจบ git clone ... && bash haws.sh setup ทั้ง Windows และ Unix
  - **5.2 Diagnostic Verification**: ตรวจเช็คครบ 6 แกน (24+ ข้อ) แสดงผลใน Terminal พร้อมตาราง Parity, Token gauge, และรองรับโหมด --json
  - **5.3 SWE Fundamentals & Testing Discipline**: ขับเคลื่อนด้วย TDD (Red-Green-Refactor), ทดสอบ Edge cases & Error modes, ยึดหลัก YAGNI/ECRS และ Pokayoke
  - **5.4 MCP & RAG Integrations**: Guarded MCP (เชื่อมต่อเฉพาะเซิร์ฟเวอร์ที่จำเป็นและปลอดภัย); Lightweight Hybrid RAG (File-based search สำหรับโค้ด, Local Vector Search เสริมสำหรับ Big Docs)
  - **5.5 External Knowledge & Starred Repos**: ให้ @researcher วิเคราะห์ Starred Repos สรุปเป็น Technique Digest 3-5 ข้อ; ตั้ง Ponytail Repo เป็น Task แรกที่จะเริ่มทำทันที
  - **5.6 HAWS Visual Dashboard**: พัฒนาแดชบอร์ด Standalone Web Artifact (React + Tailwind) อ่านค่าจาก haws.sh doctor --json ใน Phase 2

---

## 📋 Master Review Checklist (Mapped from Raw Topics — 100% COMPLETE)

### 🏛️ Domain 1: Agent Protocols, Honesty & Behavior Guardrails (4/4 COMPLETE)
- [x] **1.1 Grounding & AI Hallucination Defense** *(Raw Item #9, #13)*
- [x] **1.2 Skill Usage Transparency** *(Raw Item #8, #12)*
- [x] **1.3 Caveman Mode & Multi-Level Compression** *(Raw Item #28, #38)*
- [x] **1.4 Environment & Window Reload Notifications** *(Raw Item #20)*

### 🧠 Domain 2: Context Window & Token Economics (4/4 COMPLETE)
- [x] **2.1 Markdown Architecture for Context Reduction** *(Raw Item #2, #24)*
- [x] **2.2 Real-time Token Budget vs Context Window** *(Raw Item #23, #34)*
- [x] **2.3 On-Demand Loading & Lazy Context** *(Raw Item #35)*
- [x] **2.4 Telemetry & Metrics Tracking** *(Raw Item #31)*

### 📁 Domain 3: Project Blueprints & Source of Truth (SOT) (5/5 COMPLETE)
- [x] **3.1 Canonical Project Files Architecture** *(Raw Item #16)*
- [x] **3.2 Architecture Dependency Graph ("Graft")** *(Raw Item #17)*
- [x] **3.3 Configuration & Secrets Management** *(Raw Item #18)*
- [x] **3.4 Design Standards & React Components** *(Raw Item #1, #7)*
- [x] **3.5 Repository Normalization** *(Raw Item #21)*

### ⚙️ Domain 4: Skill Inventory, Subagents & Automation Loops (5/5 COMPLETE)
- [x] **4.1 Dynamic Skill Taxonomy & Bloat Management** *(Raw Item #3, #11)*
- [x] **4.2 Organizer Role & System Hygiene** *(Raw Item #10)*
- [x] **4.3 Subagents, Personas & Agent Harness** *(Raw Item #14, #30, #36)*
- [x] **4.4 Self-Correcting Loops & Loop Engineering** *(Raw Item #33, #39)*
- [x] **4.5 Candidate Custom Skills** *(Raw Item #19, #22)*

### 🚀 Domain 5: Installation, Tooling & Long-Term Roadmap (6/6 COMPLETE)
- [x] **5.1 Ready-to-use HAWS Installation Guide** *(Raw Item #5)*
- [x] **5.2 Diagnostic Verification on Install/Update** *(Raw Item #6)*
- [x] **5.3 SWE Fundamentals & Testing Discipline** *(Raw Item #27, #32)*
- [x] **5.4 MCP & RAG Integrations** *(Raw Item #25, #29)*
- [x] **5.5 External Knowledge & Starred Repos** *(Raw Item #4, #15)*
- [x] **5.6 HAWS Visual Dashboard** *(Raw Item #26)*

---

## 🎯 Review Progress
- **Total Topics**: 22 Active Topics (39 Raw Input Items)
- **Completed**: 22/22 (100% COMPLETE)
- **In Progress**: 0
- **Pending**: 0
