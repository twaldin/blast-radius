# Repository Agent Instructions

## Prefer Jac

- Write new application code, backend logic, graph logic, automation, tests, and
  project tooling in Jac whenever Jac supports the requirement reasonably.
- Before writing or editing Jac, read `jac-core-cheatsheet` and the relevant
  exported `jac-*` skill under `~/.codex/skills`. Use `jac guide <topic>` when
  the installed compiler may be newer than the exported guide.
- Validate Jac changes with `jac check`; validate behavior with `jac test`.
- Use Python or JavaScript only at an integration boundary Jac cannot handle
  practically or when the required third-party runtime demands it. Keep that
  boundary small and document why it is needed.
- Prefer Jac interoperability over duplicating working third-party libraries.
  Do not rewrite an external library solely to remove a small Python or
  JavaScript adapter.
