# Project Technology Stack

This document records the official technology stack, runtime constraints, and system dependencies for the `antigravity-cli-ide` package.

## 1. Runtime Environment & Dependencies
- **Editor**: GNU Emacs version `28.1` or higher.
- **Lexical Scope**: Lexical binding (`lexical-binding: t`) is strictly required in all modules.
- **External Packages**:
  - `transient` version `0.9.0` or higher for interactive command panel.
- **System Utilities**:
  - `nc` (Netcat) utility present on the system path for piping the stdio JSON-RPC stream.

## 2. Communications & Networking
- **Bridge Type**: Zero-dependency TCP connection over the loopback interface (`127.0.0.1`).
- **Emacs Listener**: Native C-level TCP socket server created using Emacs' `make-network-process`.
- **JSON-RPC Engine**: Dynamic stream parsing utilizing standard Emacs JSON deserialization hooks.

## 3. Editor Context Providers
- **Workspace Navigation**: `project.el` for detecting root boundaries and tracking files.
- **Code Diagnostics**:
  - `flymake` for native Emacs buffer syntax/type warnings.
  - `flycheck` as an alternative modern buffer diagnostics package.
- **Code Browsing**:
  - `xref` for project-wide identifier references and definitions.
  - `imenu` for semantic symbol listing.
  - Tree-sitter AST queries where applicable.

## 4. Terminal Backends
- `vterm` (via `vterm-mode` / standard libvterm wrapper) for native terminal emulation.
- `eat` (via `eat-mode` / Emacs And Terminal) for pure-Elisp terminal emulation.
- Standard fallback terminals (`term.el` / `shell.el`) where optimized emulation is unavailable.
