# HAWS Skills Taxonomy & Selection Guide (129 Active Skills)

เอกสารจัดหมวดหมู่ทักษะ (Skills) จำนวน 129 รายการของ HAWS แยกตามวัตถุประสงค์และการใช้งานจริง เพื่อสนับสนุนหลักการ **Progressive Disclosure** (เรียกใช้ทักษะเฉพาะเท่าที่จำเป็นตามลำดับขั้นของงาน)

---

## 1. Intent & Strategy (การค้นหาความต้องการ & วางกลยุทธ์)
ทักษะกลุ่มนี้ใช้ในขั้นตอนเริ่มต้น เพื่อทำความเข้าใจโจทย์ สัมภาษณ์ หรือตกผลึกแนวคิดก่อนลงมือทำ

- `interview-me`: สัมภาษณ์ถามทีละข้อความเพื่อสกัดความต้องการที่แท้จริง
- `brainstorming`: สำรวจความต้องการ ค้นหาไอเดียก่อนสร้างฟีเจอร์หรือแก้ไขพฤติกรรม
- `idea-refine`: ขัดเกลาความคิดลอยๆ ให้กลายเป็น Concept ที่ชัดเจนและนำไปปฏิบัติได้จริง
- `grilling`: ตั้งคำถามจี้กดดันเพื่อ Stress-test ความคิดและสมมติฐาน
- `doubt-driven-development`: ใช้ Adversarial Review ท้าทายและรีวิวทุกสมมติฐานสำคัญก่อนอนุมัติ

---

## 2. Planning & Specification (การออกแบบข้อกำหนด & วางแผนงาน)
ทักษะกลุ่มนี้ใช้แปลงโจทย์เป็นสเปก Architecture หรือลำดับขั้นตอนงานก่อนเขียนโค้ด

- `spec-driven-development`: สร้าง Requirement & Spec (PRD) ก่อนลงมือเขียนโค้ด
- `domain-modeling`: สกัดคำศัพท์ทางธุรกิจและสร้าง Domain Model/ADR สำหรับโครงการ
- `api-and-interface-design`: ออกแบบ API, Contract และ Module Boundaries ที่เสถียร
- `codebase-design`: ออกแบบ Deep Modules และจัดวาง Seams เพื่อความง่ายในการดูแลและทดสอบ
- `planning-and-task-breakdown`: ย่อยสเปกขนาดใหญ่ให้ออกมาเป็น List ของ Tasks
- `planning-with-files`: ระบบวางแผนงานแบบถาวร บันทึก `task_plan.md` สำหรับงานย่อยหลายขั้นตอน
- `writing-plans`: เขียนแผนขั้นตอนการทำงานอย่างเป็นระบบก่อนลงมือเขียนโค้ด

---

## 3. Architecture & Diagrams (การทำแผนผัง & Visual Architecture)
ทักษะกลุ่มนี้ใช้สร้างแผนภาพโครงสร้างระบบ เวิร์กโฟลว์ หรือแผนผังโต้ตอบ

- `archify`: สร้างสถาปัตยกรรมระบบ/Data Flow/Sequence Diagram เป็น HTML/SVG Interactivity
- `drawio-skill`: สร้างและแก้ไขไฟล์แผนผัง `.drawio` สำหรับ Architecture, ERD, UML หรือ Network

---

## 4. Engineering & Implementation Execution (การพัฒนา & ปรับปรุงคุณภาพโค้ด)
ทักษะหลักในการเขียนโค้ด ทดสอบ แก้ไขบั๊ก และปรับปรุงเชิงโครงสร้าง

### 4.1 TDD & Implementation Strategy
- `tdd` / `test-driven-development`: เขียนทดสอบแบบ Red-Green-Refactor ก่อนลงมือเขียน Logic
- `incremental-implementation`: ส่งมอบโค้ดทีละส่วนเล็กๆ ที่ตรวจวัดผลได้จริง
- `subagent-driven-development`: บริหารการพัฒนาโดยใช้ Subagents ทำงานย่อยแยกกันแบบคู่ขนาน
- `executing-plans`: ลงมือปฏิบัติตามแผนที่วางไว้ทีละ Task ในเซสชันปัจจุบัน

### 4.2 Simplicity & Audit (Ponytail & Simplification)
- `ponytail`: ปรัชญา Lazy Coding เลือกวิธีที่เรียบง่ายที่สุด ใช้ Stdlib ก่อน Custom Code
- `ponytail-audit`: สแกนทั้ง Repository เพื่อค้นหาโค้ดที่ซับซ้อนเกินจำเป็นและเสนอส่วนที่ตัดออกได้
- `ponytail-review`: รีวิวเฉพาะ Diff เพื่อหา Over-engineering และลด Bloat
- `ponytail-debt`: สรุป `ponytail:` comments บันทึกไว้เป็นหนี้ทางเทคนิค
- `ponytail-gain`: แสดงคะแนนและสถิติประหยัดจาก Ponytail
- `ponytail-help`: คู่มืออ้างอิงรวมคำสั่ง Ponytail
- `code-simplification`: Refactor โค้ดให้อ่านง่ายและลดความซับซ้อนโดยไม่เปลี่ยนพฤติกรรม

### 4.3 Debugging & Maintenance
- `debugging-and-error-recovery`: การค้นหาต้นตอบั๊ก (Root-Cause) อย่างเป็นระบบตามหลักวิทยาศาสตร์
- `diagnosing-bugs`: Loop วินิจฉัยสำหรับบั๊กยากๆ และ Performance Regressions
- `diagnosing-superpowers`: ตรวจสอบย้อนหลังว่าทำไมเซสชัน Superpowers ถึงเกิดข้อผิดพลาด
- `systematic-debugging`: กระบวนการสืบสวนบั๊กก่อนที่จะเสนอทางแก้ไข
- `resolving-merge-conflicts`: เคลียร์ Merge/Rebase Conflicts ใน Git
- `keyboard-layout-fixer`: ตรวจจับและแก้ปัญหารายการข้อความที่พิมพ์ผิดภาษา/Caps Lock ค้าง

### 4.4 Quality, Security & Optimization
- `source-driven-development`: อ้างอิงคำสั่งและวิธีเขียนจากเอกสารทางการ (Official Docs)
- `constraint-driven-development`: กำหนดและรักษากรอกมาตรฐานคุณภาพ (Coverage, Perf, Accessibility)
- `security-and-hardening`: ตรวจสอบและอัปเดตความปลอดภัยป้องกัน OWASP Top 10 / Privacy
- `performance-optimization`: ปรับแต่งความเร็ว ค้นหา Bottlenecks และ N+1 Queries
- `observability-and-instrumentation`: ฝัง Logging, Tracing, Metrics เพื่อดูการทำงานใน Production

---

## 5. UI/UX & Visual Design (งานดีไซน์หน้าจอ & ประสบการณ์ผู้ใช้)
ทักษะการออกแบบและสร้างหน้าจอ UI/UX

### 5.1 System & Intelligence
- `ui-ux-pro-max`: คลังความรู้ UI/UX (Palettes, Typography, UX Guidelines, Stacks)
- `design-system`: ออกแบบ Token Architecture (Primitive -> Semantic -> Component) และ CSS Variables
- `design-taste-frontend`: ออกแบบ Frontend ระดับพรีเมียม ป้องกัน UI แพทเทิร์นโหล
- `stitch-design-taste`: ออกแบบ UI System สำหรับ Google Stitch เน้นความสอดคล้องเชิงความหมาย
- `high-end-visual-design`: มาตรฐานดีไซน์สไตล์ Agency ชั้นนำ (Fonts, Spacing, Shadows, Motion)

### 5.2 Frontend Engineering & UI Styles
- `frontend-design`: ทิศทาง Visual Design ชัดเจน ทรงพลัง ไม่ใช่ UI สำเร็จรูป
- `frontend-ui-engineering`: เขียน Component/Layout ตามมาตรฐาน WCAG Accessibility
- `ui-styling`: สร้าง UI ด้วย Tailwind CSS, Radix UI และ components ต่างๆ
- `gpt-taste`: UI & GSAP Motion Engineer ขั้นสูง สำหรับ Scroll Trigger และ Typography กว้าง
- `minimalist-ui`: อินเทอร์เฟซสไตล์ Editorial โทนสีเรียบ สว่างสบายตา ไม่มีเงาหนัก
- `industrial-brutalist-ui`: ดีไซน์สไตล์ Brutalist / Swiss Typography / Terminal Aesthetics
- `web-artifacts-builder`: สร้าง Web Artifacts ขนาดใหญ่ที่ใช้หลาย Components (React + Tailwind)
- `generative_ui`: แสดงผล Interactive HTML Widgets ภายใน Chat หรือ Artifacts

### 5.3 Visual Generation & Assets
- `canvas-design`: ออกแบบ Visual Art, Poster, Graphic รูปแบบ `.png` หรือ `.pdf`
- `algorithmic-art`: สร้างงานศิลปะด้วยโค้ด p5.js และ Generative Visuals
- `banner-design`: ออกแบบ Banner สำหรับ Ads, Social Media, Hero Banner
- `brand`: บริหาร Brand Voice, Tone และ Visual Identity Frameworks
- `brandkit`: สร้าง Brand-Guidelines Boards และ Logo System สำหรับแบรนด์หรู
- `brand-guidelines`: ปรับแต่งธีมและสีให้ตรงตามคู่มือ Anthropic Brand
- `design`: ทักษะครอบจักรวาลด้านงานภาพ (Logo, CIP, Mockups, Presentation, Social Photos)
- `image-to-code`: แปลงภาพ mockup ให้เป็นโค้ดเว็บไซต์จริงอย่างแม่นยำ
- `imagegen-frontend-web`: สร้างภาพดีไซน์อ้างอิงแยกตาม Section สำหรับ Web
- `imagegen-frontend-mobile`: สร้าง Concept หน้าจอแอปมือถือ iOS/Android
- `slack-gif-creator`: สร้าง GIF Animation สำหรับใช้งานใน Slack

---

## 6. Review, Audit & Governance (การรีวิวโค้ด & ควบคุมความปลอดภัย)
ทักษะการตรวจสอบและทบทวนความถูกต้องของงาน

- `code-review`: รีวิวโค้ดแยก 2 แกน (Standards & Spec) โดยใช้ Subagents แบบขนาน
- `code-review-and-quality`: ประเมินคุณภาพโค้ดหลายมิติก่อน Merge เข้า Main Branch
- `requesting-code-review`: รวบรวมงานเพื่อขอ Code Review อย่างเป็นระบบ
- `receiving-code-review`: ตรวจสอบและวิเคราะห์ Feedback จากการ Review ด้วยหลักการทางเทคนิค
- `discernment-nudge`: เพิ่มคำถามสะกิดให้ User ฉุกคิด ตรวจสอบสมมติฐานหลังให้คำตอบสำคัญ
- `git-guardrails-claude-code`: ตั้งค่า Hooks บล็อกคำสั่ง Git ที่อันตราย (`push`, `reset --hard`)

---

## 7. Delivery, Git & Operations (การส่งมอบ & CI/CD)
ทักษะเกี่ยวกับการจัดการ Version Control และ CI/CD

- `git-workflow-and-versioning`: จัดการ Commit Structure, Branching, PRs และ SemVer
- `using-git-worktrees`: สร้าง Git Worktree เพื่อแยก Workspace สำหรับทำงานคู่ขนาน
- `ci-cd-and-automation`: ตั้งค่า CI/CD Pipeline และ Automation Quality Gates
- `shipping-and-launch`: เตรียมความพร้อมก่อน Deploy หน้า Pre-launch Checklist และ Rollback Strategy
- `finishing-a-development-branch`: สรุปและ Integrate งานเมื่อพัฒนาและผ่านการทดสอบครบถ้วน

---

## 8. Document & Knowledge Management (การจัดการเอกสาร & องค์ความรู้)
ทักษะจัดการเอกสารรูปแบบต่างๆ

### 8.1 Document Formats (Word, PDF, Excel, Slides)
- `docx`: อ่าน สร้าง แก้ไขไฟล์เอกสาร Microsoft Word (`.docx`, `.dotx`)
- `pdf`: อ่าน สกัด รวม แยก แปลง หรือสร้างเอกสาร PDF
- `pptx`: อ่าน สร้าง แก้ไขสไลด์นำเสนอ Microsoft PowerPoint (`.pptx`, `.potx`)
- `xlsx`: อ่าน แก้ไข คำนวณ จัดรูป หรือสร้างไฟล์ Excel / CSV
- `slides`: สร้าง Slide HTML พร้อม Chart.js และ Design Tokens
- `theme-factory`: ปรับแต่งสไตล์และโทนสีของเอกสาร / สไลด์ / HTML

### 8.2 Content Co-authoring & Research
- `doc-coauthoring`: เวิร์กโฟลว์ร่วมกันเขียนเอกสาร Spec หรือ Proposal กับ User
- `documentation-and-adrs`: บันทึกการตัดสินใจทางสถาปัตยกรรม (ADR) และคำอธิบายระบบ
- `internal-comms`: เขียนสื่อสารภายในองค์กร (Status Report, FAQ, Incident Report)
- `research`: สืบค้นข้อมูลจากแหล่งอ้างอิงปฐมภูมิ และบันทึกผลเป็น Markdown
- `graphify`: แปลง Codebase/Docs ให้กลายเป็น Knowledge Graph สรุปความสัมพันธ์
- `humanizer`: ปรับแต่งข้อความภาษาอังกฤษสไตล์ AI ให้ดูเป็นธรรมชาติ สมจริง

---

## 9. Meta, Customization & Skill Maintenance (ทักษะบริหารจัดการระบบ)
ทักษะสำหรับการพัฒนาและจัดการปรับแต่งตัว AI เอง

- `skill-creator`: สร้าง ปรับแต่ง และทดสอบประสิทธิภาพของ Skill ใหม่
- `writing-skills`: คู่มือการสร้างและแก้ไขทักษะอย่างเป็นระบบ
- `using-agent-skills`: Meta-skill สำหรับค้นหาและเลือกใช้ Agent Skill ให้เหมาะกับงาน
- `using-superpowers`: หลักปฏิบัติเบื้องต้นในการค้นหาและใช้ Skill
- `writing-for-agents`: เทคนิคการเขียนคำสั่งเอกสารเพื่อให้ AI Agent เข้าใจและทำงานตามได้ดี
- `context-engineering`: ปรับแต่งการตั้งค่า Context เพื่อเพิ่มประสิทธิภาพสูงสุดในการทำงาน
- `dispatching-parallel-agents`: บริหารและส่งงานให้ Subagent หลายตัวทำงานคู่ขนาน
- `scaffold-exercises`: สร้างโครงสร้างแบบฝึกหัด โจทย์ และเฉลย
- `wizard`: สร้าง Bash Interactive Wizard เพื่อแนะนำผู้ใช้ทำขั้นตอนเฉพาะทาง
- `setup-pre-commit`: ตั้งค่า Husky pre-commit hooks และ lint-staged
- `migrate-to-shoehorn`: ย้ายไฟล์ Test จาก Type Assertion `as` ไปใช้ Shoehorn
- `academy-guide`: แนะนำคอร์สเรียน Claude Academy สำหรับคำถามเกี่ยวกับการใช้งาน Claude
- `claude-api`: เอกสารอ้างอิง API ของ Anthropic SDK / Claude models
- `agy-customizations`: คู่มือระบบ Antigravity Customization (Skills, Rules, Plugins, MCP)
- `antigravity-guide`: คู่มือรวมการใช้งาน Google Antigravity CLI/IDE/Customizations
- `migrate-workflows`: แปลง Workflows รุ่นเก่าให้เป็น SKILL.md
- `webapp-testing`: เครื่องมือ Playwright สำหรับทดสอบ Web Application ในสภาพแวดล้อมจริง
- `browser-testing-with-devtools`: ทดสอบและตรวจสอบ Web App ด้วย Chrome DevTools MCP
- `mcp-builder`: คู่มือการสร้าง MCP (Model Context Protocol) Server
