;;; antigravity-cli-ide-mcp-server.el --- MCP tools registry for Antigravity CLI IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Israel Herraiz

;; Author: Israel Herraiz <isra@herraiz.org>
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

;; This module provides tool registration definitions and session context
;; tracking for MCP tools exposed to Antigravity CLI.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'antigravity-cli-ide-debug)

;;; Customization

(defgroup antigravity-cli-ide-mcp-server nil
  "MCP tools settings for Antigravity CLI IDE."
  :group 'antigravity-cli-ide
  :prefix "antigravity-cli-ide-mcp-server-")

(defcustom antigravity-cli-ide-enable-mcp-server nil
  "Enable MCP tools registration for exposing Emacs functions to Antigravity."
  :type 'boolean
  :group 'antigravity-cli-ide-mcp-server)

(defcustom antigravity-cli-ide-mcp-server-tools nil
  "Alist of Emacs functions to expose via MCP tools.
Each entry is (FUNCTION . PLIST) where PLIST contains:
  :description - Human-readable description of the function
  :parameters - List of parameter specifications, each with:
    :name - Parameter name
    :type - Parameter type (string, number, boolean)
    :required - Whether parameter is required
    :description - Parameter description"
  :type '(alist :key-type symbol
                :value-type (plist :key-type keyword
                                   :value-type sexp))
  :group 'antigravity-cli-ide-mcp-server)

;;; State Management

(defvar antigravity-cli-ide-mcp-server--session-count 0
  "Number of active Antigravity sessions.")

(defvar antigravity-cli-ide-mcp-server--sessions (make-hash-table :test 'equal)
  "Hash table mapping session IDs to session contexts.
Each entry contains a plist with session information:
  :project-dir - The project directory for the session
  :buffer - The Antigravity buffer
  :start-time - When the session was started")

(defvar antigravity-cli-ide-mcp-server--current-session-id nil
  "The session ID for the current MCP tool request.
This is dynamically bound during tool execution.")

;;; Tool Definition Functions

(defun antigravity-cli-ide-make-tool (&rest slots)
  "Make an Antigravity CLI IDE tool for MCP use from SLOTS.

The following keyword arguments are available:

:name - The name of the tool, recommended to be in snake_case.

:function - The function itself (lambda or symbol) that runs the tool.

:description - A description of what the tool does and what it returns.

:args - A list of plists specifying arguments, or nil if none.
Each plist in :args should have:
  - :name - Argument name (string)
  - :type - Argument type (symbol: string, number, integer, boolean, etc.)
  - :description - Argument description (string)
  - :optional - Whether the argument is optional (boolean)
  - :enum - Vector of allowed values
  - :items - Plist describing array items
  - :properties - Plist of property specifications

:category - Category string for the tool (optional).

The tool is automatically added to `antigravity-cli-ide-mcp-server-tools'.
Returns the tool specification for convenience."
  (let ((function (plist-get slots :function))
        (name (plist-get slots :name))
        (description (plist-get slots :description))
        (args (plist-get slots :args))
        (category (plist-get slots :category)))
    ;; Validate required parameters
    (unless function
      (error "Tool :function is required"))
    (unless name
      (error "Tool :name is required"))
    (unless description
      (error "Tool :description is required"))

    ;; Build the tool specification
    (let ((spec (list :function function
                      :name name
                      :description description)))
      (when args
        (setq spec (plist-put spec :args args)))
      (when category
        (setq spec (plist-put spec :category category)))
      ;; Add to the tools list
      (add-to-list 'antigravity-cli-ide-mcp-server-tools spec)
      ;; Return the spec for convenience
      spec)))

;;; Format Detection and Conversion

(defun antigravity-cli-ide--tool-format-p (tool-spec)
  "Determine format of TOOL-SPEC.
Returns \\='old for (symbol . plist) format, \\='new for plist format."
  (cond
   ;; Old format: (function-symbol :description "..." :parameters ...)
   ((and (consp tool-spec)
         (symbolp (car tool-spec))
         (not (keywordp (car tool-spec))))
    'old)
   ;; New format: (:function fn :name "..." :description "..." :args ...)
   ((and (listp tool-spec)
         (keywordp (car tool-spec)))
    'new)
   (t
    (error "Unknown tool format: %S" tool-spec))))

(defun antigravity-cli-ide--normalize-tool-spec (tool-spec)
  "Convert TOOL-SPEC to normalized format for processing.
Handles both old format: (func :description ... :parameters ...)
and new format: (:function func :name ... :args ...).
Returns a consistent plist format with :args."
  (let ((format (antigravity-cli-ide--tool-format-p tool-spec)))
    (cond
     ((eq format 'old)
      ;; Convert old format to new normalized format with :args
      (let* ((func (car tool-spec))
             (plist (cdr tool-spec))
             (description (plist-get plist :description))
             (parameters (plist-get plist :parameters)))
        ;; Emit deprecation warning
        (message "Warning: Tool \\='%s\\=' is using deprecated format.  Please use `antigravity-cli-ide-make-tool' instead."
                 (symbol-name func))
        (list :function func
              :name (symbol-name func)
              :description description
              :args (antigravity-cli-ide--parameters-to-args parameters))))
     ((eq format 'new)
      ;; New format - already in the right format, just return it
      tool-spec)
     (t
      (error "Cannot normalize tool spec: %S" tool-spec)))))

(defun antigravity-cli-ide--parameters-to-args (parameters)
  "Convert PARAMETERS (old format) to :args (new format).
PARAMETERS is a list of plists with :name, :type, :description, :required.
Returns a list of plists with :name, :type, :description, :optional."
  (mapcar (lambda (param)
            (let ((name (plist-get param :name))
                  (type (plist-get param :type))
                  (description (plist-get param :description))
                  (required (plist-get param :required)))
              ;; Build arg spec
              (let ((arg (list :name name
                                :type (if (stringp type)
                                          (intern type)
                                        type))))
                (when description
                  (setq arg (plist-put arg :description description)))
                (unless required
                  (setq arg (plist-put arg :optional t)))
                ;; Handle additional properties
                (when-let* ((enum (plist-get param :enum)))
                  (setq arg (plist-put arg :enum enum)))
                (when-let* ((items (plist-get param :items)))
                  (setq arg (plist-put arg :items items)))
                (when-let* ((properties (plist-get param :properties)))
                  (setq arg (plist-put arg :properties properties)))
                arg)))
          parameters))

;;; Public Functions

(defun antigravity-cli-ide-mcp-server-session-started (&optional session-id project-dir buffer)
  "Notify that a session has started.
If SESSION-ID, PROJECT-DIR and BUFFER are provided, register the session.
Increments the session counter."
  (cl-incf antigravity-cli-ide-mcp-server--session-count)
  (antigravity-cli-ide-debug "MCP session started. Count: %d"
                         antigravity-cli-ide-mcp-server--session-count)
  (when (and session-id project-dir buffer)
    (antigravity-cli-ide-mcp-server-register-session session-id project-dir buffer)))

(defun antigravity-cli-ide-mcp-server-session-ended (&optional session-id)
  "Notify that a session has ended.
If SESSION-ID is provided, unregister that specific session.
Decrements the session counter."
  (when session-id
    (antigravity-cli-ide-mcp-server-unregister-session session-id))
  (when (> antigravity-cli-ide-mcp-server--session-count 0)
    (cl-decf antigravity-cli-ide-mcp-server--session-count)
    (antigravity-cli-ide-debug "MCP session ended. Count: %d"
                           antigravity-cli-ide-mcp-server--session-count)))

(defun antigravity-cli-ide-mcp-server-get-tool-names (&optional prefix)
  "Get a list of all registered MCP tool names.
If PREFIX is provided, prepend it to each tool name.
This is useful for generating allowedTools lists."
  (mapcar (lambda (tool-spec)
            (let* ((normalized (antigravity-cli-ide--normalize-tool-spec tool-spec))
                   (tool-name (or (plist-get normalized :name)
                                  (symbol-name (plist-get normalized :function)))))
              (if prefix
                  (concat prefix tool-name)
                tool-name)))
          antigravity-cli-ide-mcp-server-tools))

;;; Session Management Functions

(defun antigravity-cli-ide-mcp-server-register-session (session-id project-dir buffer)
  "Register a new session with SESSION-ID, PROJECT-DIR, and BUFFER."
  (puthash session-id
           (list :project-dir project-dir
                 :buffer buffer
                 :last-active-buffer nil
                 :start-time (current-time))
           antigravity-cli-ide-mcp-server--sessions)
  (antigravity-cli-ide-debug "Registered MCP session %s for project %s" session-id project-dir))

(defun antigravity-cli-ide-mcp-server-unregister-session (session-id)
  "Unregister the session with SESSION-ID."
  (when (gethash session-id antigravity-cli-ide-mcp-server--sessions)
    (remhash session-id antigravity-cli-ide-mcp-server--sessions)
    (antigravity-cli-ide-debug "Unregistered MCP session %s" session-id)))

(defun antigravity-cli-ide-mcp-server-get-session-context (&optional session-id)
  "Get the context for SESSION-ID or the current session.
Returns a plist with :project-dir and :buffer, or nil if not found."
  (let ((id (or session-id antigravity-cli-ide-mcp-server--current-session-id)))
    (when id
      (gethash id antigravity-cli-ide-mcp-server--sessions))))

(defun antigravity-cli-ide-mcp-server-update-last-active-buffer (session-id buffer)
  "Update the last active buffer for SESSION-ID to BUFFER.
This should be called when the user switches to a different buffer
in the project to ensure MCP tools execute in the correct context."
  (when-let* ((session (gethash session-id antigravity-cli-ide-mcp-server--sessions)))
    (plist-put session :last-active-buffer buffer)
    (antigravity-cli-ide-debug "Updated last active buffer for session %s to %s"
                           session-id (buffer-name buffer))))

(defmacro antigravity-cli-ide-mcp-server-with-session-context (session-id &rest body)
  "Execute BODY with the context of SESSION-ID.
Sets `default-directory' to the session's project directory
and makes the session's buffer current if it exists.
Prefers the last active buffer over the registered buffer."
  (declare (indent 1))
  `(let* ((context (antigravity-cli-ide-mcp-server-get-session-context ,session-id))
          (project-dir (plist-get context :project-dir))
          (last-active-buffer (plist-get context :last-active-buffer))
          (registered-buffer (plist-get context :buffer))
          ;; Prefer last active buffer, fall back to registered buffer
          (buffer (or (and last-active-buffer
                           (buffer-live-p last-active-buffer)
                           last-active-buffer)
                      (and registered-buffer
                           (buffer-live-p registered-buffer)
                           registered-buffer))))
     (if (not context)
          (error "No session context found for session %s" ,session-id)
       (let ((default-directory (or project-dir default-directory)))
         (if buffer
             (with-current-buffer buffer
               ,@body)
           ,@body)))))

(provide 'antigravity-cli-ide-mcp-server)
;;; antigravity-cli-ide-mcp-server.el ends here
