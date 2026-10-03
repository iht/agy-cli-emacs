## Summary

<!-- Brief description of the changes proposed in this Pull Request. -->

## Type of Change

- [ ] `fix`: Bug fix
- [ ] `feat`: New feature
- [ ] `docs`: Documentation update
- [ ] `refactor`: Code refactoring
- [ ] `perf`: Performance improvement
- [ ] `test`: Tests addition or modification
- [ ] `chore`: Repository maintenance or CI changes

## Subsystem / Area

- [ ] `area:mcp` (Model Context Protocol bridge, TCP server, RPC)
- [ ] `area:terminal` (Terminal backends: vterm, eat, term)
- [ ] `area:tools` (Editor context tools: xref, tree-sitter, imenu)
- [ ] `area:diagnostics` (Flymake / Flycheck diagnostics)
- [ ] `area:ediff` (Ediff and buffer diffing)
- [ ] `area:transient` (Transient interactive menus)
- [ ] `area:packaging` (ELPA / MELPA packaging and metadata)
- [ ] `area:ci` (Continuous Integration, Makefile, workflows)

## Quality Checklist

- [ ] Commits adhere to Conventional Commits format (`feat(...)`, `fix(...)`, etc.).
- [ ] Source files contain `;;; ... -*- lexical-binding: t; -*-` on line 1.
- [ ] Symbol naming conventions are respected (`antigravity-cli-ide-` for public, `antigravity-cli-ide--` for internal).
- [ ] `make all` passes cleanly (byte-compilation, `checkdoc`, and automated ERT tests).
- [ ] `make lint` passes cleanly (`package-lint`).
- [ ] Relevant ERT unit tests added or updated in `antigravity-cli-ide-tests.el`.
