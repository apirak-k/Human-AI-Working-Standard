# Project Specific Specification — [Project Name]

## 1. Project Overview & Scope
- **Purpose**: Brief description of what this project solves and why it exists.
- **Primary Users**: Who uses this software (e.g., end-users, internal admins, developers).
- **Key Deliverables**: Primary software artifacts produced by this repository.

## 2. Tech Stack & Environment
- **Language & Runtime**: [e.g., TypeScript Node 20+, Python 3.11, Go 1.22]
- **Primary Framework**: [e.g., Next.js 15, FastAPI, Express]
- **Database & ORM**: [e.g., PostgreSQL + Prisma, BigQuery, SQLite]
- **Package Manager**: [e.g., pnpm, bun, poetry, cargo]
- **Hosting / Cloud**: [e.g., Google Cloud Run, Vercel, AWS]

## 3. Confirmed Conventions
- **Naming Conventions**: [e.g., camelCase for functions, PascalCase for components, snake_case for DB columns]
- **Folder Structure Patterns**: [e.g., feature-sliced design, clean architecture layers]
- **Branching & PR Strategy**: [e.g., trunk-based development, feature/* branches]
- **Commit Message Format**: [e.g., Conventional Commits: feat(...), fix(...)]

## 4. Domain Vocabulary & Ubiquitous Language

| Term | Definition | Context / Usage |
| :--- | :--- | :--- |
| [Term 1] | [Definition] | [Domain context] |
| [Term 2] | [Definition] | [Domain context] |

## 5. Constraints & Third-Party Dependencies
- **External APIs**: [List third-party integrations and rate limits]
- **Known Limitations**: [Technical debt, platform constraints, unsupported features]
- **Environment Variables**: [Document required env keys without secrets]

## 6. Safety & Security Guardrails
- **Excluded Files**: Sensitive files that must never be committed (.env*, private keys).
- **Destructive Operations**: Production commands or migrations requiring manual user confirmation.
