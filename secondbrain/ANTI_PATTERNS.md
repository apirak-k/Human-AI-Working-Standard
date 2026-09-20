# HAWS Default Anti-Patterns & Safeguards

This is a neutral starter document for the local Second Brain. It contains
general safeguards only; a DEV overlay may add personal or project-specific
lessons without changing the public HAWS core.

## Baseline Safeguards

- Do not perform destructive operations without explicit authorization.
- Do not claim a fix or passing state without fresh verification evidence.
- Do not commit secrets, credentials, or machine-private data to a public repository.
- Preserve unrelated user changes and stop when the requested scope is complete.
