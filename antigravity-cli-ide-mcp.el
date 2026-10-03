;;; antigravity-cli-ide-mcp.el --- MCP server for Antigravity CLI IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Israel Herraiz

;; Author: Israel Herraiz <isra@herraiz.org>
;; Assisted-by: Google Antigravity:gemini-3.8-flash
;; Maintainer: Israel Herraiz <isra@herraiz.org>
;; Keywords: tools, processes, convenience, ai, antigravity

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This file implements a pure TCP socket-based MCP server for Antigravity CLI IDE.
;; It uses Emacs' built-in make-network-process to run a local TCP server that the
;; 'nc' (netcat) bridge connects to, handling JSON-RPC line-by-line messages.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'project)
(require 'antigravity-cli-ide-debug)
(require 'antigravity-cli-ide-mcp-handlers)
(require 'antigravity-cli-ide-mcp-server)

;; Configuration variables
(defvar antigravity-cli-ide-mcp-port-range '(10000 . 65535)
  "Port range for TCP server.")

(defvar antigravity-cli-ide-mcp-max-port-attempts 100
  "Maximum number of attempts to find a free port.")

;; Session registry
(defvar antigravity-cli-ide-mcp--sessions (make-hash-table :test 'equal)
  "Hash table mapping project directories to MCP sessions.")

;; Cache variables for buffer-local performance optimization
(defvar-local antigravity-cli-ide-mcp--buffer-project-cache nil)
(defvar-local antigravity-cli-ide-mcp--buffer-session-cache nil)
(defvar-local antigravity-cli-ide-mcp--buffer-cache-valid nil)

;; Define error type
(define-error 'antigravity-cli-ide-mcp-error "MCP Error" 'error)

;;; Session Struct

(cl-defstruct antigravity-cli-ide-mcp-session
  "Structure to hold all state for a single MCP session."
  server           ; Built-in TCP server process
  proc             ; Connected TCP client process (nc)
  port             ; TCP port
  project-dir      ; Project directory
  deferred         ; Hash table of deferred responses
  active-diffs     ; Hash table of active diffs
  original-tab     ; Original tab-bar tab where Antigravity was opened
  cli-pid)         ; PID of the connected CLI process

;;; Session Helpers

(defun antigravity-cli-ide-mcp--get-buffer-project ()
  "Get the project directory for the current buffer."
  (if antigravity-cli-ide-mcp--buffer-cache-valid
      antigravity-cli-ide-mcp--buffer-project-cache
    (let ((project-dir (when-let* ((project (project-current)))
                         (expand-file-name (project-root project)))))
      (setq antigravity-cli-ide-mcp--buffer-project-cache project-dir
            antigravity-cli-ide-mcp--buffer-cache-valid t)
      project-dir)))

(defun antigravity-cli-ide-mcp--get-session-for-project (project-dir)
  "Get the MCP session for PROJECT-DIR."
  (when project-dir
    (gethash project-dir antigravity-cli-ide-mcp--sessions)))

(defun antigravity-cli-ide-mcp--get-current-session ()
  "Get the MCP session for the current buffer's project."
  (when-let* ((project-dir (antigravity-cli-ide-mcp--get-buffer-project)))
    (antigravity-cli-ide-mcp--get-session-for-project project-dir)))

(defun antigravity-cli-ide-mcp--find-session-by-proc (proc)
  "Find session with client process PROC."
  (let ((found-session nil))
    (maphash (lambda (_dir session)
                (when (eq (antigravity-cli-ide-mcp-session-proc session) proc)
                  (setq found-session session)))
              antigravity-cli-ide-mcp--sessions)
    found-session))

(defun antigravity-cli-ide-mcp--active-sessions ()
  "Return active sessions list."
  (let ((res '()))
    (maphash (lambda (_dir session) (push session res))
             antigravity-cli-ide-mcp--sessions)
    res))

;;; Global mcp_config.json Management

(defun antigravity-cli-ide-mcp--get-config-path ()
  "Get global antigravity-cli config file path."
  (expand-file-name "~/.gemini/antigravity-cli/settings.json"))

(defun antigravity-cli-ide-mcp--get-mcp-config-path ()
  "Get global mcp_config.json path."
  (expand-file-name "~/.gemini/antigravity-cli/mcp_config.json"))

(defun antigravity-cli-ide-mcp--update-mcp-config (port _project-dir _session-id)
  "Write PORT connection configuration to global mcp_config.json."
  (let* ((config-path (antigravity-cli-ide-mcp--get-mcp-config-path))
         (config-dir (file-name-directory config-path))
         (config (if (file-exists-p config-path)
                     (condition-case nil
                         (json-read-file config-path)
                       (error nil))
                   nil))
         (servers (or (cdr (assoc 'mcpServers config)) nil))
         ;; Build our nc server config entry
         (emacs-server-config
          `((command . "nc")
            (args . ["127.0.0.1" ,(format "%d" port)]))))
    
    (unless (file-exists-p config-dir)
      (make-directory config-dir t))
    
    ;; Set emacs-tools entry
    (setq servers (cons (cons 'antigravity-emacs-tools emacs-server-config)
                        (cl-remove 'antigravity-emacs-tools servers :key #'car)))
    
    (setq config (cons (cons 'mcpServers servers)
                       (cl-remove 'mcpServers config :key #'car)))
    
    (with-temp-file config-path
      (insert (json-encode config)))
    (antigravity-cli-ide-debug "Configured global mcp_config.json with port %d" port)))

(defun antigravity-cli-ide-mcp--remove-from-mcp-config ()
  "Remove the antigravity-emacs-tools server entry from mcp_config.json."
  (let ((config-path (antigravity-cli-ide-mcp--get-mcp-config-path)))
    (when (file-exists-p config-path)
      (condition-case nil
          (let* ((config (json-read-file config-path))
                 (servers (cdr (assoc 'mcpServers config))))
            (when servers
              (setq servers (cl-remove 'antigravity-emacs-tools servers :key #'car))
              (setq config (cons (cons 'mcpServers servers)
                                 (cl-remove 'mcpServers config :key #'car)))
              (with-temp-file config-path
                (insert (json-encode config)))
              (antigravity-cli-ide-debug "Removed antigravity-emacs-tools from global mcp_config.json")))
        (error nil)))))

;;; Server Communication Protocol

(defun antigravity-cli-ide-mcp--make-response (id result)
  "Build JSON-RPC response for request ID with RESULT."
  `((jsonrpc . "2.0")
    (id . ,id)
    (result . ,result)))

(defun antigravity-cli-ide-mcp--make-error-response (id code message)
  "Build JSON-RPC error response for request ID, CODE, and MESSAGE."
  `((jsonrpc . "2.0")
    (id . ,id)
    (error . ((code . ,code)
              (message . ,message)))))

(defun antigravity-cli-ide-mcp--send-response (proc response)
  "Send RESPONSE JSON line to client PROC."
  (when (and proc (process-live-p proc))
    (let ((json-line (concat (json-encode response) "\n")))
      (antigravity-cli-ide-debug "MCP Sending: %s" (string-trim json-line))
      (process-send-string proc json-line))))

(defun antigravity-cli-ide-mcp--handle-initialize (id)
  "Handle initialize RPC request with ID."
  (let ((resp `((protocolVersion . "2024-11-05")
                (capabilities . ((tools . ((listChanged . :json-false)))))
                (serverInfo . ((name . "antigravity-cli-ide-mcp")
                               (version . "0.1.0"))))))
    (antigravity-cli-ide-mcp--make-response id resp)))

(defun antigravity-cli-ide-mcp--handle-tools-list (id)
  "Handle tools/list RPC request with ID."
  (setq antigravity-cli-ide-mcp-tools (antigravity-cli-ide-mcp--build-tool-list))
  (setq antigravity-cli-ide-mcp-tool-schemas (antigravity-cli-ide-mcp--build-tool-schemas))
  (setq antigravity-cli-ide-mcp-tool-descriptions (antigravity-cli-ide-mcp--build-tool-descriptions))
  
  (let ((tools '()))
    (dolist (entry antigravity-cli-ide-mcp-tools)
      (let* ((name (car entry))
             (schema (alist-get name antigravity-cli-ide-mcp-tool-schemas nil nil #'string=))
             (desc (alist-get name antigravity-cli-ide-mcp-tool-descriptions nil nil #'string=)))
        (push `((name . ,name)
                (description . ,desc)
                (inputSchema . ,(if (eq schema :json-empty)
                                    (make-hash-table :test 'equal)
                                  schema)))
              tools)))
    (antigravity-cli-ide-mcp--make-response id `((tools . ,(vconcat (nreverse tools)))))))

(defun antigravity-cli-ide-mcp--handle-tools-call (id params proc)
  "Handle tools/call RPC request ID with PARAMS from client PROC."
  (let* ((tool-name (alist-get 'name params))
         (arguments (alist-get 'arguments params))
         (handler (alist-get tool-name antigravity-cli-ide-mcp-tools nil nil #'string=))
         (session (antigravity-cli-ide-mcp--find-session-by-proc proc)))
    (if handler
        (condition-case err
            (let ((result (if (member tool-name '("getDiagnostics"))
                              (funcall handler arguments session)
                            (funcall handler arguments))))
              (if (and (listp result) (alist-get 'deferred result))
                  (let* ((unique-key (alist-get 'unique-key result))
                         (storage-key (if unique-key (format "%s-%s" tool-name unique-key) tool-name)))
                    (when session
                      (puthash storage-key id (antigravity-cli-ide-mcp-session-deferred session)))
                    nil) ; Respond later
                (antigravity-cli-ide-mcp--make-response id `((content . ,result)))))
          (antigravity-cli-ide-mcp-error
           (antigravity-cli-ide-mcp--make-error-response id -32603 (cadr err)))
          (error
           (antigravity-cli-ide-mcp--make-error-response id -32603 (error-message-string err))))
      (antigravity-cli-ide-mcp--make-error-response id -32601 (format "Unknown tool: %s" tool-name)))))

(defun antigravity-cli-ide-mcp--dispatch-message (proc msg)
  "Process a parsed JSON-RPC message MSG from client PROC."
  (let ((id (alist-get 'id msg))
        (method (alist-get 'method msg))
        (params (alist-get 'params msg)))
    (antigravity-cli-ide-debug "MCP Received: method=%s, id=%S" method id)
    (let ((resp
           (cond
            ((string= method "initialize")
             (antigravity-cli-ide-mcp--handle-initialize id))
            ((string= method "tools/list")
             (antigravity-cli-ide-mcp--handle-tools-list id))
            ((string= method "tools/call")
             (antigravity-cli-ide-mcp--handle-tools-call id params proc))
            ((string= method "notifications/initialized")
             nil)
            (id
             (antigravity-cli-ide-mcp--make-error-response id -32601 (format "Method not found: %s" method)))
            (t nil))))
      (when resp
        (antigravity-cli-ide-mcp--send-response proc resp)))))

;;; Deferred completion function called from ediff handlers

(defun antigravity-cli-ide-mcp-complete-deferred (session tool-name result &optional unique-key)
  "Complete a deferred TOOL-NAME response with RESULT for SESSION.
Optional UNIQUE-KEY provides additional specificity."
  (let* ((lookup-key (if unique-key (format "%s-%s" tool-name unique-key) tool-name))
         (session-deferred (antigravity-cli-ide-mcp-session-deferred session))
         (id (gethash lookup-key session-deferred)))
    (when id
      (remhash lookup-key session-deferred)
      (let ((proc (antigravity-cli-ide-mcp-session-proc session)))
        (when proc
          (let ((resp (antigravity-cli-ide-mcp--make-response id `((content . ,result)))))
            (antigravity-cli-ide-mcp--send-response proc resp)))))))

;;; TCP Server lifecycle and filtering

(defun antigravity-cli-ide-mcp--server-filter (proc string)
  "Network filter for PROC handling newline-delimited STRING."
  (let* ((old-buf (or (process-get proc 'buffer) ""))
         (new-buf (concat old-buf string))
         (lines (split-string new-buf "\n")))
    (process-put proc 'buffer (car (last lines)))
    (dolist (line (butlast lines))
      (unless (string-empty-p (string-trim line))
        (condition-case nil
            (let ((msg (json-parse-string line :object-type 'alist)))
              (antigravity-cli-ide-mcp--dispatch-message proc msg))
          (error
           (antigravity-cli-ide-debug "JSON Parse Error on line: %s" line)))))))

(defun antigravity-cli-ide-mcp--server-sentinel (proc event)
  "Sentinel to manage client TCP connection PROC on EVENT."
  (antigravity-cli-ide-debug "Client event: %s" (string-trim event))
  (cond
   ((string-match-p "open" event)
    ;; Client connected
    (let ((session (cl-find-if (lambda (s) (eq (antigravity-cli-ide-mcp-session-server s)
                                                (process-get proc 'server-proc)))
                               (antigravity-cli-ide-mcp--active-sessions))))
      (when session
        (setf (antigravity-cli-ide-mcp-session-proc session) proc)
        (antigravity-cli-ide-debug "Client connected and bound to session for %s"
                               (antigravity-cli-ide-mcp-session-project-dir session)))))
   ((string-match-p "connection broken\\|exited\\|closed" event)
    ;; Client disconnected
    (let ((session (antigravity-cli-ide-mcp--find-session-by-proc proc)))
      (when session
        (setf (antigravity-cli-ide-mcp-session-proc session) nil)
        (antigravity-cli-ide-debug "Client disconnected from session"))))))

(defun antigravity-cli-ide-mcp--find-free-port ()
  "Find a random free port in the range."
  (let ((min-port (car antigravity-cli-ide-mcp-port-range))
        (max-port (cdr antigravity-cli-ide-mcp-port-range))
        (attempts 0)
        (found nil))
    (while (and (< attempts antigravity-cli-ide-mcp-max-port-attempts) (not found))
      (let* ((port (+ min-port (random (- max-port min-port))))
             (server (condition-case nil
                         (make-network-process
                          :name (format "agy-mcp-%d" port)
                          :server t
                          :host "127.0.0.1"
                          :service port
                          :family 'ipv4
                          :filter #'antigravity-cli-ide-mcp--server-filter
                          :sentinel #'antigravity-cli-ide-mcp--server-sentinel)
                       (error nil))))
        (if server
            (setq found (cons server port))
          (cl-incf attempts))))
    (or found (error "Could not find a free TCP port"))))

;;; Session Life Cycle APIs

(defun antigravity-cli-ide-mcp-start-session (project-dir session-id)
  "Start a new network server session for PROJECT-DIR and SESSION-ID."
  (antigravity-cli-ide-debug "Starting MCP session for %s" project-dir)
  (let* ((server-info (antigravity-cli-ide-mcp--find-free-port))
         (server-proc (car server-info))
         (port (cdr server-info))
         (session (make-antigravity-cli-ide-mcp-session
                   :server server-proc
                   :proc nil
                   :port port
                   :project-dir project-dir
                   :deferred (make-hash-table :test 'equal)
                   :active-diffs (make-hash-table :test 'equal))))
    
    ;; Set process local metadata
    (process-put server-proc 'server-proc server-proc)
    (puthash project-dir session antigravity-cli-ide-mcp--sessions)
    
    ;; Configure lockfile in mcp_config.json
    (antigravity-cli-ide-mcp--update-mcp-config port project-dir session-id)
    port))

(defun antigravity-cli-ide-mcp-stop-session (project-dir)
  "Stop the TCP MCP session for PROJECT-DIR and cleanup configuration."
  (antigravity-cli-ide-debug "Stopping MCP session for %s" project-dir)
  (when-let* ((session (gethash project-dir antigravity-cli-ide-mcp--sessions)))
    ;; Close client process
    (when-let* ((client (antigravity-cli-ide-mcp-session-proc session)))
      (when (process-live-p client)
        (delete-process client)))
    ;; Close server process
    (when-let* ((server (antigravity-cli-ide-mcp-session-server session)))
      (when (process-live-p server)
        (delete-process server)))
    
    (remhash project-dir antigravity-cli-ide-mcp--sessions)
    (antigravity-cli-ide-mcp--remove-from-mcp-config)))

(defun antigravity-cli-ide-mcp--cleanup ()
  "Clean up all sessions on exit."
  (maphash (lambda (project-dir _session)
             (antigravity-cli-ide-mcp-stop-session project-dir))
           antigravity-cli-ide-mcp--sessions))

(add-hook 'kill-emacs-hook #'antigravity-cli-ide-mcp--cleanup)

(defun antigravity-cli-ide-mcp--setup-buffer-cache-hooks ()
  "Clear caches when buffer hooks run."
  (setq-local antigravity-cli-ide-mcp--buffer-cache-valid nil))

(provide 'antigravity-cli-ide-mcp)
;;; antigravity-cli-ide-mcp.el ends here
