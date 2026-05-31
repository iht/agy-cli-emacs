# Product & Development Guidelines

These guidelines define the implementation and design patterns for the `antigravity-cli-ide` package. All code modifications and new features must adhere to these standards.

## 1. Emacs Lisp Coding Conventions
- **Naming Prefix**: All public functions, variables, faces, and groups must start with the strict namespace prefix `antigravity-cli-ide-`.
- **Private Namespace**: All internal or private functions, macros, and variables must be prefixed with double hyphens `antigravity-cli-ide--`.
- **Header Formats**: File headers must strictly conform to GNU Emacs Lisp package standards, including standard sections: `;;; Commentary:`, `;;; Code:`, `lexical-binding: t` directive, and proper autoload cookies (`;;;###autoload`).
- **Dependencies**: Bypassing third-party socket/websocket packages. Keep all TCP server implementations close to the native C-level `make-network-process` API.

## 2. Transient UI & Menu Design
- **Grouped Layouts**: Commands within the Transient panel must be structured into logical blocks (e.g., Session management vs Settings configurations vs Debug/Diagnostics panel).
- **State-Aware Actions**: Menus should dynamically show current configurations or active status and highlight allowed actions based on whether a session is currently active.
- **Compact UX**: The interface must fit on a single screen without scrolling to guarantee all options are visible at a single glance.

## 3. Robustness & Network Error Handling
- **Graceful Failures**: If the Netcat pipeline or socket connection drops, the package must catch errors silently, print detailed log diagnostics to the `*antigravity-cli-ide-debug*` buffer, and notify the user via a friendly message in the Emacs Echo Area.
- **Config Restoration**: When a session closes or crashes, the package must cleanly close the socket listener and restore the global `~/.gemini/antigravity-cli/mcp_config.json` configuration file to its original pre-session state.

## 4. Window & Buffer Layouts
- **Dedicated Side Windows**: Launching an Antigravity CLI session should display the terminal buffer in a dedicated side-window (placed at configurable left, right, or bottom) to preserve the main editing workspace layout.
- **Adaptive Split Control**: Allow fallbacks for adaptive splitting when screen dimensions are too narrow.
- **Multi-Session Isolation**: Maintain isolated, project-specific buffers (e.g. `*antigravity-cli-ide-session:<project-name>*`) so multiple sessions can run in parallel without overwriting active states.
