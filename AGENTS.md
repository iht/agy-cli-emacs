# AGENTS.md — Developer & AI Agent Guide for `antigravity-cli-ide`

This document serves as the comprehensive architectural and development reference for human developers and autonomous AI agents working in this repository.

---

## 1. Project Mission & Overview

`antigravity-cli-ide` provides a native, highly optimized GNU Emacs integration with the Google Antigravity CLI (`agy`) executable via the Model Context Protocol (MCP).

Unlike simple terminal wrappers or heavyweight bridge solutions, this package creates a bidirectional bridge connecting Antigravity directly to Emacs editor capabilities (LSP, tree-sitter AST, compiler diagnostics, buffer navigation, and custom Elisp evaluation) while maintaining a strict zero-heavyweight-dependency philosophy.

### Core Architectural Pillars
- **Zero Heavy External Dependencies**: No Node.js, Python sidecar, `websocket.el`, or `web-server.el` required.
- **Pure Netcat-to-TCP Bridge**: Leverages Emacs' built-in C-level TCP socket server (`make-network-process`) paired with the standard Unix/Linux `nc` (netcat) utility.
- **Strict Local Security Boundary**: The TCP server binds exclusively to the loopback interface (`127.0.0.1`), ensuring no network exposure of editor tools or project files.
- **Dynamic Configuration Lifecycle**: Automates MCP registration and cleanup against `~/.gemini/antigravity-cli/mcp_config.json`.
- **Multi-Session Isolation**: Supports concurrent Antigravity sessions across different projects without state contamination.

---

## 2. Architecture & Data Flow

### The Netcat-to-TCP MCP Pipeline

Antigravity CLI communicates with external tools using standard JSON-RPC over stdio. Rather than running an intermediary process or heavy websocket server, Emacs uses `nc` as a stdio-to-TCP translator:

```
┌─────────────────────────────────────────────────────────┐
│                  Antigravity CLI (agy)                  │
└───────────────────────────▲─────────────────────────────┘
                            │ stdio (JSON-RPC)
┌───────────────────────────▼─────────────────────────────┐
│                   nc (netcat) process                   │
│         (Launched automatically as an MCP server)       │
└───────────────────────────▲─────────────────────────────┘
                            │ Loopback TCP (127.0.0.1:<port>)
┌───────────────────────────▼─────────────────────────────┐
│             Emacs Built-in TCP Socket Server            │
│         (Created natively via make-network-process)     │
├─────────────────────────────────────────────────────────┤
│                   JSON-RPC Line Parser                  │
├─────────────────────────────────────────────────────────┤
│          MCP Handlers & Emacs Tool Integration          │
│   (xref, tree-sitter, diagnostics, Ediff, buffer state) │
└─────────────────────────────────────────────────────────┘
```

### Session Lifecycle
1. **Port Allocation & Server Start**: When a session begins (`antigravity-cli-ide`), Emacs finds a free port in `antigravity-cli-ide-mcp-port-range` (default 10000–65535) and starts a native TCP server bound to `127.0.0.1`.
2. **Dynamic Config Injection**: Emacs safely reads `~/.gemini/antigravity-cli/mcp_config.json` (creating backup state) and injects the server entry:
   ```json
   "mcpServers": {
     "antigravity-emacs-tools": {
       "command": "nc",
       "args": ["127.0.0.1", "<PORT>"]
     }
   }
   ```
3. **Terminal Launch**: The `agy` process starts inside a dedicated terminal buffer (`vterm` or `eat`) in a dedicated side-window.
4. **Connection Establishment**: `agy` reads `mcp_config.json`, executes `nc`, and establishes the bidirectional TCP stream.
5. **Clean Restoration & Teardown**: When the terminal buffer is killed or session stopped, Emacs stops the TCP server, purges the `antigravity-emacs-tools` entry, and cleanly restores `mcp_config.json`.

---

## 3. Repository Modules & Responsibilities

| File | Responsibility |
|---|---|
| [`antigravity-cli-ide.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide.el) | **Main entry point**: Session orchestration, CLI executable resolution, terminal buffer lifecycles, dedicated side-window layout, and companion buffer tracking. |
| [`antigravity-cli-ide-mcp.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-mcp.el) | **Core MCP TCP engine**: Socket lifecycle management, port selection, JSON-RPC streaming/parsing, session registry, and dynamic `mcp_config.json` updates. |
| [`antigravity-cli-ide-mcp-handlers.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-mcp-handlers.el) | **MCP Tool Implementations**: Protocol handlers for `openFile`, `getDiagnostics`, `openDiff` (interactive Ediff), `getCurrentBufferContext`, and Elisp evaluation. |
| [`antigravity-cli-ide-emacs-tools.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-emacs-tools.el) | **Editor Context Tools**: Exposes project boundaries, identifier references (`xref`), symbol tables (`imenu`), and Tree-sitter AST queries to the assistant. |
| [`antigravity-cli-ide-diagnostics.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-diagnostics.el) | **Compiler Diagnostics**: Unifies `flymake` and `flycheck` diagnostic data, transforming them into standard LSP/VS Code diagnostic structures. |
| [`antigravity-cli-ide-transient.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-transient.el) | **Interactive UI**: The `transient` menu system (`C-c g` / `antigravity-cli-ide-menu`), configuration submenu, and diagnostics panel. |
| [`antigravity-cli-ide-debug.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-debug.el) | **Observability**: Structured logging to the `*antigravity-cli-ide-debug*` buffer. |
| [`antigravity-cli-ide-mcp-server.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-mcp-server.el) | Optional HTTP/Streamable HTTP MCP tools server module. |
| [`antigravity-cli-ide-mcp-http-server.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-mcp-http-server.el) | HTTP transport primitives for the optional HTTP MCP server. |
| [`antigravity-cli-ide-tests.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-tests.el) | **Automated Tests**: ERT test suite validating command generation, session lifecycle, config serialization, buffer naming, and diagnostics mapping. |
| [`Makefile`](file:///home/ihr/projects/agy-cli-ide/Makefile) | Build automation for byte-compilation, batch ERT test runs, and checkdoc verification. |
| [`.github/workflows/ci.yml`](file:///home/ihr/projects/agy-cli-ide/.github/workflows/ci.yml) | Continuous Integration running `make compile` and `make test` across Emacs 28.2, 29.4, 30.1, and snapshot. |

---

## 4. Technology Stack & Runtime Requirements

- **GNU Emacs**: Version `28.1` or higher.
- **Lexical Binding**: Strict requirement for `lexical-binding: t` on line 1 of every `.el` module.
- **Required Packages**:
  - `transient` (`>= 0.9.0`) for the interactive control panel.
  - Built-in Emacs libraries: `cl-lib`, `project`, `json`, `xref`, `flymake`.
- **Supported Terminal Backends**:
  - `vterm` (recommended for native libvterm performance).
  - `eat` (Emacs And Terminal, pure Elisp fallback).
  - `term` / `shell` (standard fallback).
- **System Utilities**:
  - `nc` (Netcat) available on system `$PATH`.
  - `agy` (Antigravity CLI executable) on `$PATH` or in `~/.local/bin/agy`.

---

## 5. Emacs Lisp Coding Conventions

All code contributions must adhere to the following conventions:

### Namespace Rules
- **Public Symbols**: Every public function, variable, face, and customization group must use the `antigravity-cli-ide-` prefix.
- **Internal / Private Symbols**: Internal helpers, implementation macros, and state variables must use the double-hyphen `antigravity-cli-ide--` prefix.

### Header & File Structure
Every Elisp file must follow GNU Emacs package standards:
```elisp
;;; antigravity-cli-ide-example.el --- Feature description  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: ...
;; Keywords: ai, antigravity, ...

;;; Commentary:
;; Detailed description of module role and usage.

;;; Code:

(require '...)

...

(provide 'antigravity-cli-ide-example)
;;; antigravity-cli-ide-example.el ends here
```
- Interactive entry points must include autoload cookies (`;;;###autoload`).
- Avoid obsolete macros where possible (e.g. prefer `when-let*` / `if-let*` over `when-let` / `if-let`).

### Transient UI Guidelines
- Group commands into logical, distinct blocks (e.g. Session Management vs Configuration vs Debugging).
- Keep menus compact so they fit entirely on screen without scrolling.
- Menus should be dynamically state-aware, adapting commands and statuses according to active sessions.

### Layout & Window Management
- Sessions run in dedicated side windows (`antigravity-cli-ide-window-side`, default `'right`) with configurable widths to keep primary code buffers undisturbed.
- Isolated buffer naming: Sessions are named uniquely per project root: `*antigravity-cli[<project-folder-name>]*`.
- Companion buffer tracking: Active editor buffers are tracked so the user can easily inject `@file` or `@file:start-end` context references into the terminal prompt.

### Robustness & Resource Restoration
- Always guard temporary mutations (like socket connections and `mcp_config.json` modifications) with `unwind-protect`.
- If Netcat fails or a socket terminates abruptly, fail gracefully: log details to `*antigravity-cli-ide-debug*` and post a user-friendly message to the echo area without breaking user editing workflows.

---

## 6. Testing & Batch-Mode Environment Nuances

### Test Framework
All tests are implemented using Emacs' built-in ERT (`ert.el`) in [`antigravity-cli-ide-tests.el`](file:///home/ihr/projects/agy-cli-ide/antigravity-cli-ide-tests.el).

### Batch Mode Caveats (Headless CI / Make)
Running Emacs batch testing (`emacs -batch -L . -l ert ...`) has specific environmental constraints that tests must account for:
- **Terminal Backends**: Neither `vterm` nor `eat` are present in headless standard batch environments; tests mock `(provide 'vterm)` and `(provide 'eat)` safely.
- **Transient Library Versions**: In headless batch mode, Emacs might load built-in older `transient` implementations that lack newer internal functions or faces. In `antigravity-cli-ide-tests.el`:
  - `transient--set-layout` is safely stubbed if unbound.
  - `transient-inactive-value` face is conditionally defined if missing.
- **Sandboxed Session Testing**: Session lifecycle tests must use isolated temporary paths (e.g., `/tmp/test-project-session-dir`) and clean up all created files in an `unwind-protect` block.

---

## 7. Development & Build Commands

All development tasks are automated via the repository [`Makefile`](file:///home/ihr/projects/agy-cli-ide/Makefile):

| Command | Action |
|---|---|
| `make test` | Run the complete ERT automated test suite in batch mode |
| `make compile` | Byte-compile all Emacs Lisp source files |
| `make all` | Run byte-compilation followed by the test suite (default target) |
| `make checkdoc` | Run `checkdoc` style and documentation inspection across source files |
| `make clean` | Remove all generated `.elc` compiled bytecode artifacts |
| `make help` | Display list of available Makefile targets |

---

## 8. Commit & Workflow Standards

- **Test-Driven Development (TDD)**: When implementing bug fixes or new features, write reproducible ERT test cases first, verify failure, implement minimal code to pass, and refactor.
- **Commit Message Format**: Follow Conventional Commits:
  - `feat(<scope>): description`
  - `fix(<scope>): description`
  - `test(<scope>): description`
  - `docs(<scope>): description`
  - `refactor(<scope>): description`
  - `chore(<scope>): description`
- **Quality Gates**:
  - `make all` must pass cleanly before any merge or release.
  - Ensure zero regressions in byte-compilation or ERT tests across supported Emacs versions (28.2+).
