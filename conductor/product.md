# Initial Concept
Provide native, highly optimized Emacs integration with the Antigravity CLI (`agy`) through a bidirectional Model Context Protocol (MCP) TCP socket-to-netcat bridge without heavy external dependencies.

# Product Vision & Goals
The goal of `antigravity-cli-ide` is to bridge the powerful, extensible ecosystem of GNU Emacs with the advanced intelligence of the Antigravity CLI. By bypassing traditional wrapper scripts or heavyweight dependencies, the package leverages low-level networking and existing system utilities (like Netcat) to offer a lightning-fast, zero-overhead pair programming experience.

# Target Audience
1. **Power-Users & Elisp Developers**: Users who customize their Emacs configurations deeply and want to integrate custom tools or hooks with Antigravity.
2. **General Emacs Users**: Those seeking a clean, out-of-the-box, zero-dependency LLM coding assistant within their editor.
3. **Enterprise & Large Codebase Developers**: Users working on complex codebases where deep contextual knowledge (via LSP, Tree-sitter AST, and local compiler diagnostics) is vital.

# Core Capabilities
1. **Robust Netcat-TCP Connection**: Fast, lightweight, bidirectional socket communication bound securely to `127.0.0.1`.
2. **Rich Workspace Context Integration**: Seamless transmission of active project information including:
   - LSP/xref cross-references for navigation and search.
   - Tree-sitter AST explorer.
   - Real-time compiler diagnostics (via Flymake/Flycheck).
   - Interactive buffer management and file editing.
3. **Flexible Terminal & Layout Management**: First-class support for both `vterm` and `eat` backends, supporting multiple concurrent sessions and adaptive window layouts.

# Security Model
- **Local-Only Boundary**: The network listener is strictly bound to `127.0.0.1` (localhost), ensuring no external exposure of the IDE tools or file contents.
