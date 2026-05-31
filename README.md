# Antigravity CLI IDE for Emacs

Antigravity CLI IDE for Emacs provides native integration with the `antigravity-cli` (`agy`) executable through the Model Context Protocol (MCP). Unlike simple terminal wrappers, this package creates a bidirectional bridge between Antigravity and Emacs, enabling the assistant to understand and leverage Emacs' powerful features—from LSP and project management to custom Elisp functions.

It is a functional clone in capability of `claude-code-ide.el` but optimized to use a **pure TCP socket server** and a **netcat (`nc`) pipeline**, eliminating the need for complex external bridge processes, Node.js, Python, or heavy third-party Emacs packages (no `websocket.el` or `web-server.el` required).

---

## 🚀 How the Netcat-to-TCP Architecture Works

Since `agy` supports the Model Context Protocol (MCP) using a standard stdio command configured in `mcp_config.json`, we leverage the built-in Unix/Linux utility **`nc` (netcat)** to pipe RPC streams natively to Emacs:

```
[ Antigravity CLI (agy) ]
        ▲
        │ stdio JSON-RPC
        ▼
[ nc (netcat) process ]  <--- Launched automatically by agy
        ▲
        │ Local TCP stream (127.0.0.1:port)
        ▼
[ Emacs Built-in TCP Server ] (make-network-process)
        ▲
        │ Native Elisp handler
        ▼
[ Emacs Buffers, AST & Tools ]
```

1. **Emacs Plain TCP Server**: When an Antigravity session starts, Emacs binds to a random free TCP port (e.g., `12345`) using its highly optimized C-level `make-network-process` API.
2. **Global MCP Auto-Config**: Emacs dynamically writes the server details to your global `~/.gemini/antigravity-cli/mcp_config.json` before startup:
   ```json
   "mcpServers": {
     "antigravity-emacs-tools": {
       "command": "nc",
       "args": ["127.0.0.1", "12345"]
     }
   }
   ```
3. **Interactive Terminal Session**: Emacs launches the `agy` process in a dedicated `vterm` or `eat` buffer. As `agy` starts up, it reads `mcp_config.json`, starts `nc` as its MCP connector, and establishes an instant, zero-dependency, bidirectional TCP channel to Emacs.
4. **Session Cleanup**: When you quit or kill the terminal buffer, Emacs automatically shuts down the TCP socket and restores the `mcp_config.json` to its original state.

---

## 📂 Package Modules

The package consists of the following modules in this directory:

* **`antigravity-cli-ide.el`**: Main entry point managing processes, term-buffer lifecycles, and window configurations.
* **`antigravity-cli-ide-mcp.el`**: The TCP socket server, JSON-RPC line parser, and `mcp_config.json` dynamic writer/cleanup.
* **`antigravity-cli-ide-transient.el`**: A gorgeous, interactive Transient menu for all start, stop, navigation, and debugging commands.
* **`antigravity-cli-ide-emacs-tools.el`**: Built-in Emacs tools exposed to the LLM (xref for LSP/references, imenu navigation, tree-sitter AST explorer, and project metadata).
* **`antigravity-cli-ide-mcp-handlers.el`**: MCP protocol-compliant tool executors including `openFile`, `getDiagnostics`, `openDiff` (using Emacs Ediff), and custom Elisp evaluation.
* **`antigravity-cli-ide-diagnostics.el`**: Flymake and Flycheck integration. Packages buffer errors/warnings dynamically to send to the model.
* **`antigravity-cli-ide-debug.el`**: Structured logger and buffer (`*antigravity-cli-ide-debug*`) for developer instrumentation.

---

## ⚙️ Installation & Configuration

Add this configuration to your `init.el` or `config.el` to load and configure the package:

```elisp
(add-to-list 'load-path "/path/to/agy-cli-ide")

(use-package antigravity-cli-ide
  :bind ("C-c g" . antigravity-cli-ide-menu)
  :config
  ;; Custom settings:
  (setq antigravity-cli-ide-window-side 'right
        antigravity-cli-ide-window-width 100
        antigravity-cli-ide-terminal-backend 'vterm) ; Supports 'vterm or 'eat
  
  ;; Enable built-in tools
  (antigravity-cli-ide-emacs-tools-setup))
```

---

## 🌟 Usage & Keybindings

### Interactive Transient Menu
Run `M-x antigravity-cli-ide-menu` or press your keybinding (`C-c g`) to open the interactive transient menu:
- **s**: Start a new Antigravity session
- **c**: Continue the most recent session
- **r**: Resume previous conversation
- **q**: Stop/kill the active session
- **b**: Switch focus to the Antigravity buffer
- **w**: Toggle side window visibility
- **C**: Access comprehensive window and CLI settings
- **d**: Open the diagnostics, sessions, and debug logging panel

### Key Bindings inside the Antigravity Terminal Buffer:
* `S-RET` (Shift+Return) - Insert a newline in the prompt (simulates a multiline prompt).
* `C-g` / `C-<escape>` - Cancel or escape active prompts.
