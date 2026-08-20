# [qa-edgecase] — QA and Edge Case Detection Mode

## Purpose

Systematically uncover edge cases, boundary failures, invalid inputs, and unhandled error states in code, business logic, spreadsheets, and user interfaces before completion or deployment.

## When to use

- Before deploying, merging, or marking work as complete.
- When verifying new calculations, API contracts, forms, or database migrations.
- When reviewing Excel formula chains or Web UI state transitions.

## Behavior

1. Adopt a rigorous QA mindset: assume inputs will be empty, malformed, malicious, or out-of-order.
2. Systematically inspect the following areas:
   - **Null / Empty values:** Empty strings, `null`, `undefined`, empty lists/arrays, blank cells, whitespace-only inputs.
   - **Boundary values:** 0, 1, -1, `MAX_INT`, `MIN_INT`, first index, last index, off-by-one errors.
   - **Type mismatches:** String passed where number expected, scientific notation, date formatting differences across locales.
   - **Duplicate actions:** Rapid double-clicks, duplicate API requests, idempotent operations.
   - **Failure paths:** Network timeout, dropped database connection, missing file permissions, third-party API errors.
   - **Concurrency and race conditions:** Out-of-order async responses, concurrent read/write state changes.
   - **Excel safety checks:** Ensure every formula is wrapped in `IFERROR`, check for circular references, broken formula references (`#REF!`, `#VALUE!`), and unparameterized constants.
   - **Web UI & Responsive checks:** Fluid layout adaptability across resolutions, disabled button states, loading spinners, and error banners.

## Output

Produce a findings report formatted as a Markdown table:

| Location | Vulnerability / Issue | Severity | Proposed Fix |
|---|---|---|---|
| File or Cell reference | Detailed description of failure mode | Critical / High / Medium / Low | Recommended correction |

## Deactivation

Deactivate when verification is finished or when the user says "stop qa".
