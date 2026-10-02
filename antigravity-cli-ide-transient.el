;;; antigravity-cli-ide-transient.el --- Transient menus for Antigravity CLI IDE  -*- lexical-binding: t; -*-

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

;; This file provides transient menus for Antigravity CLI IDE, offering
;; a convenient interface for all Antigravity operations.

;;; Code:

(require 'transient)
(require 'antigravity-cli-ide-debug)

;; Declare functions from other files to avoid circular dependencies
(declare-function antigravity-cli-ide "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-resume "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-continue "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-stop "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-list-sessions "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-switch-to-buffer "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-insert-at-mentioned "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-send-prompt "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-send-escape "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-insert-newline "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-toggle "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-toggle-recent "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-check-status "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide--ensure-cli "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide-mcp--active-sessions "antigravity-cli-ide-mcp" ())
(declare-function antigravity-cli-ide-mcp-session-project-dir "antigravity-cli-ide-mcp" (session))
(declare-function antigravity-cli-ide-mcp-session-port "antigravity-cli-ide-mcp" (session))
(declare-function antigravity-cli-ide-mcp-session-proc "antigravity-cli-ide-mcp" (session))
(declare-function antigravity-cli-ide-mcp--get-current-session "antigravity-cli-ide-mcp" ())
(declare-function antigravity-cli-ide--get-working-directory "antigravity-cli-ide" ())
(declare-function antigravity-cli-ide--format-context-reference "antigravity-cli-ide" (&optional target-buffer))

;; Declare variables
(defvar antigravity-cli-ide-cli-path)
(defvar antigravity-cli-ide-debug)
(defvar antigravity-cli-ide-window-side)
(defvar antigravity-cli-ide-window-width)
(defvar antigravity-cli-ide-window-height)
(defvar antigravity-cli-ide-focus-on-open)
(defvar antigravity-cli-ide-focus-antigravity-after-ediff)
(defvar antigravity-cli-ide-show-antigravity-window-in-ediff)
(defvar antigravity-cli-ide-use-ide-diff)
(defvar antigravity-cli-ide-switch-tab-on-ediff)
(defvar antigravity-cli-ide-use-side-window)
(defvar antigravity-cli-ide-cli-debug)
(defvar antigravity-cli-ide-cli-extra-flags)
(defvar antigravity-cli-ide-auto-prefix-prompt)
(defvar antigravity-cli-ide-auto-fill-context)

;;; Helper Functions

(defun antigravity-cli-ide--has-active-session-p ()
  "Check if there's an active Antigravity CLI session for the current buffer."
  (when (antigravity-cli-ide-mcp--get-current-session) t))

(defun antigravity-cli-ide--start-description ()
  "Dynamic description for start command based on session status."
  (if (antigravity-cli-ide--has-active-session-p)
      (propertize "Start new Antigravity session (session already running)"
                  'face 'transient-inactive-value)
    "Start new Antigravity session"))

(defun antigravity-cli-ide--start-if-no-session ()
  "Start Antigravity CLI only if no session is active for current buffer."
  (interactive)
  (if (antigravity-cli-ide--has-active-session-p)
      (let ((working-dir (antigravity-cli-ide--get-working-directory)))
        (antigravity-cli-ide-log "Antigravity session already running in %s"
                             (abbreviate-file-name working-dir)))
    (antigravity-cli-ide)))

(defun antigravity-cli-ide--continue-description ()
  "Dynamic description for continue command based on session status."
  (if (antigravity-cli-ide--has-active-session-p)
      (propertize "Continue most recent conversation (session already running)"
                  'face 'transient-inactive-value)
    "Continue most recent conversation"))

(defun antigravity-cli-ide--continue-if-no-session ()
  "Continue Antigravity CLI only if no session is active for current buffer."
  (interactive)
  (if (antigravity-cli-ide--has-active-session-p)
      (let ((working-dir (antigravity-cli-ide--get-working-directory)))
        (antigravity-cli-ide-log "Antigravity session already running in %s"
                             (abbreviate-file-name working-dir)))
    (antigravity-cli-ide-continue)))

(defun antigravity-cli-ide--resume-description ()
  "Dynamic description for resume command based on session status."
  (if (antigravity-cli-ide--has-active-session-p)
      (propertize "Resume session (session already running)"
                  'face 'transient-inactive-value)
    "Resume session (from previous conversation)"))

(defun antigravity-cli-ide--resume-if-no-session ()
  "Resume Antigravity CLI only if no session is active for current buffer."
  (interactive)
  (if (antigravity-cli-ide--has-active-session-p)
      (let ((working-dir (antigravity-cli-ide--get-working-directory)))
        (antigravity-cli-ide-log "Antigravity session already running in %s"
                             (abbreviate-file-name working-dir)))
    (antigravity-cli-ide-resume)))

(defun antigravity-cli-ide--session-status ()
  "Return a string describing the current session status."
  (if-let* ((session (antigravity-cli-ide-mcp--get-current-session)))
      (let* ((project-dir (antigravity-cli-ide-mcp-session-project-dir session))
             (project-name (file-name-nondirectory (directory-file-name project-dir)))
             (connected (if (antigravity-cli-ide-mcp-session-proc session) "connected" "disconnected")))
        (propertize (format "Active session in [%s] - %s" project-name connected)
                    'face 'success))
    (propertize "No active session" 'face 'transient-inactive-value)))

(defun antigravity-cli-ide--insert-description ()
  "Dynamic description for insert context command."
  (if-let* ((ref (and (fboundp 'antigravity-cli-ide--format-context-reference)
                      (antigravity-cli-ide--format-context-reference))))
      (format "Insert context (%s)" ref)
    "Insert context (@file)"))

(defun antigravity-cli-ide-toggle-window ()
  "Toggle visibility of Antigravity CLI window."
  (interactive)
  (antigravity-cli-ide-toggle))

(defun antigravity-cli-ide-show-version-info ()
  "Show detailed version information for Antigravity CLI."
  (interactive)
  (if (antigravity-cli-ide--ensure-cli)
      (let* ((cli (or (executable-find antigravity-cli-ide-cli-path)
                      antigravity-cli-ide-cli-path))
             (version-output
              (with-temp-buffer
                (call-process cli nil t nil "--version")
                (string-trim (buffer-string)))))
        (with-output-to-temp-buffer "*Antigravity CLI Info*"
          (princ "Antigravity CLI Information\n")
          (princ "===========================\n\n")
          (princ (format "Version: %s\n" version-output))
          (princ (format "Executable path: %s\n" (executable-find antigravity-cli-ide-cli-path)))))
    (user-error "Antigravity CLI not available")))

(defun antigravity-cli-ide-show-mcp-sessions ()
  "Show information about active MCP sessions."
  (interactive)
  (let ((sessions (antigravity-cli-ide-mcp--active-sessions)))
    (if sessions
        (with-output-to-temp-buffer "*Antigravity MCP Sessions*"
          (princ "Active MCP Sessions\n")
          (princ "==================\n\n")
          (dolist (session sessions)
            (princ (format "Project: %s\n" (antigravity-cli-ide-mcp-session-project-dir session)))
            (princ (format "  Port: %d\n" (antigravity-cli-ide-mcp-session-port session)))
            (princ (format "  Connected: %s\n"
                           (if (antigravity-cli-ide-mcp-session-proc session) "Yes" "No")))
            (princ "\n")))
      (antigravity-cli-ide-log "No active MCP sessions"))))

(defun antigravity-cli-ide-show-active-ports ()
  "Show active ports used by MCP servers."
  (interactive)
  (let ((sessions (antigravity-cli-ide-mcp--active-sessions)))
    (if sessions
        (with-output-to-temp-buffer "*Antigravity Active Ports*"
          (princ "Active MCP Server Ports\n")
          (princ "======================\n\n")
          (dolist (session sessions)
            (princ (format "Port %d: %s\n"
                           (antigravity-cli-ide-mcp-session-port session)
                           (abbreviate-file-name (antigravity-cli-ide-mcp-session-project-dir session))))))
      (antigravity-cli-ide-log "No active MCP servers"))))

(defun antigravity-cli-ide-toggle-debug-mode ()
  "Toggle Antigravity debug mode."
  (interactive)
  (setq antigravity-cli-ide-debug (not antigravity-cli-ide-debug))
  (antigravity-cli-ide-log "Debug mode %s" (if antigravity-cli-ide-debug "enabled" "disabled")))

;;; Transient Infix Classes

(transient-define-suffix antigravity-cli-ide--set-window-side (side)
  "Set window side."
  :description "Set window side"
  (interactive (list (intern (completing-read "Window side: "
                                              '("left" "right" "top" "bottom")
                                              nil t nil nil
                                              (symbol-name antigravity-cli-ide-window-side)))))
  (setq antigravity-cli-ide-window-side side)
  (antigravity-cli-ide-log "Window side set to %s" side))

(transient-define-suffix antigravity-cli-ide--set-window-width (width)
  "Set window width."
  :description "Set window width"
  (interactive (list (read-number "Window width: " antigravity-cli-ide-window-width)))
  (setq antigravity-cli-ide-window-width width)
  (antigravity-cli-ide-log "Window width set to %d" width))

(transient-define-suffix antigravity-cli-ide--set-window-height (height)
  "Set window height."
  :description "Set window height"
  (interactive (list (read-number "Window height: " antigravity-cli-ide-window-height)))
  (setq antigravity-cli-ide-window-height height)
  (antigravity-cli-ide-log "Window height set to %d" height))

(transient-define-suffix antigravity-cli-ide--set-cli-path (path)
  "Set CLI path."
  :description "Set CLI path"
  (interactive (list (read-file-name "Antigravity CLI path: " nil antigravity-cli-ide-cli-path t)))
  (setq antigravity-cli-ide-cli-path path)
  (antigravity-cli-ide-log "CLI path set to %s" path))

(transient-define-suffix antigravity-cli-ide--set-cli-extra-flags (flags)
  "Set additional CLI flags."
  :description "Set additional CLI flags"
  (interactive (list (read-string "Additional CLI flags: " antigravity-cli-ide-cli-extra-flags)))
  (setq antigravity-cli-ide-cli-extra-flags flags)
  (antigravity-cli-ide-log "CLI extra flags set to %s" flags))

;;; Transient Suffix Functions

(transient-define-suffix antigravity-cli-ide--toggle-focus-on-open ()
  "Toggle focus on open setting."
  (interactive)
  (setq antigravity-cli-ide-focus-on-open (not antigravity-cli-ide-focus-on-open))
  (antigravity-cli-ide-log "Focus on open %s" (if antigravity-cli-ide-focus-on-open "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-focus-after-ediff ()
  "Toggle focus after ediff setting."
  (interactive)
  (setq antigravity-cli-ide-focus-antigravity-after-ediff (not antigravity-cli-ide-focus-antigravity-after-ediff))
  (antigravity-cli-ide-log "Focus after ediff %s" (if antigravity-cli-ide-focus-antigravity-after-ediff "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-show-antigravity-in-ediff ()
  "Toggle showing Antigravity window during ediff."
  (interactive)
  (setq antigravity-cli-ide-show-antigravity-window-in-ediff (not antigravity-cli-ide-show-antigravity-window-in-ediff))
  (antigravity-cli-ide-log "Show Antigravity window in ediff %s" (if antigravity-cli-ide-show-antigravity-window-in-ediff "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-use-side-window ()
  "Toggle use side window setting."
  (interactive)
  (setq antigravity-cli-ide-use-side-window (not antigravity-cli-ide-use-side-window))
  (antigravity-cli-ide-log "Use side window %s" (if antigravity-cli-ide-use-side-window "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-use-ide-diff ()
  "Toggle IDE diff viewer setting."
  (interactive)
  (setq antigravity-cli-ide-use-ide-diff (not antigravity-cli-ide-use-ide-diff))
  (antigravity-cli-ide-log "IDE diff viewer %s" (if antigravity-cli-ide-use-ide-diff "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-switch-tab-on-ediff ()
  "Toggle tab switching on ediff setting."
  (interactive)
  (setq antigravity-cli-ide-switch-tab-on-ediff (not antigravity-cli-ide-switch-tab-on-ediff))
  (antigravity-cli-ide-log "Switch tab on ediff %s" (if antigravity-cli-ide-switch-tab-on-ediff "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-cli-debug ()
  "Toggle CLI debug mode."
  (interactive)
  (setq antigravity-cli-ide-cli-debug (not antigravity-cli-ide-cli-debug))
  (antigravity-cli-ide-log "CLI debug mode %s" (if antigravity-cli-ide-cli-debug "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-auto-prefix-prompt ()
  "Toggle auto prefix prompt setting."
  (interactive)
  (setq antigravity-cli-ide-auto-prefix-prompt (not antigravity-cli-ide-auto-prefix-prompt))
  (antigravity-cli-ide-log "Auto prefix prompt %s" (if antigravity-cli-ide-auto-prefix-prompt "enabled" "disabled")))

(transient-define-suffix antigravity-cli-ide--toggle-auto-fill-context ()
  "Toggle auto fill context on focus."
  (interactive)
  (setq antigravity-cli-ide-auto-fill-context
        (if (eq antigravity-cli-ide-auto-fill-context 'on-switch) nil 'on-switch))
  (antigravity-cli-ide-log "Auto fill context on focus %s"
                       (if antigravity-cli-ide-auto-fill-context "enabled" "disabled")))

(defun antigravity-cli-ide--save-config ()
  "Save current configuration to custom file."
  (interactive)
  (customize-save-variable 'antigravity-cli-ide-window-side antigravity-cli-ide-window-side)
  (customize-save-variable 'antigravity-cli-ide-window-width antigravity-cli-ide-window-width)
  (customize-save-variable 'antigravity-cli-ide-window-height antigravity-cli-ide-window-height)
  (customize-save-variable 'antigravity-cli-ide-focus-on-open antigravity-cli-ide-focus-on-open)
  (customize-save-variable 'antigravity-cli-ide-focus-antigravity-after-ediff antigravity-cli-ide-focus-antigravity-after-ediff)
  (customize-save-variable 'antigravity-cli-ide-show-antigravity-window-in-ediff antigravity-cli-ide-show-antigravity-window-in-ediff)
  (customize-save-variable 'antigravity-cli-ide-use-ide-diff antigravity-cli-ide-use-ide-diff)
  (customize-save-variable 'antigravity-cli-ide-switch-tab-on-ediff antigravity-cli-ide-switch-tab-on-ediff)
  (customize-save-variable 'antigravity-cli-ide-use-side-window antigravity-cli-ide-use-side-window)
  (customize-save-variable 'antigravity-cli-ide-cli-path antigravity-cli-ide-cli-path)
  (customize-save-variable 'antigravity-cli-ide-cli-extra-flags antigravity-cli-ide-cli-extra-flags)
  (customize-save-variable 'antigravity-cli-ide-auto-prefix-prompt antigravity-cli-ide-auto-prefix-prompt)
  (customize-save-variable 'antigravity-cli-ide-auto-fill-context antigravity-cli-ide-auto-fill-context)
  (antigravity-cli-ide-log "Configuration saved to custom file"))

;;; Transient Menus

;;;###autoload
(transient-define-prefix antigravity-cli-ide-menu ()
  "Antigravity CLI IDE main menu."
  [:description antigravity-cli-ide--session-status]
  ["Antigravity CLI IDE"
   ["Session Management"
    ("s" antigravity-cli-ide--start-if-no-session :description antigravity-cli-ide--start-description)
    ("c" antigravity-cli-ide--continue-if-no-session :description antigravity-cli-ide--continue-description)
    ("r" antigravity-cli-ide--resume-if-no-session :description antigravity-cli-ide--resume-description)
    ("q" "Stop current session" antigravity-cli-ide-stop)
    ("l" "List all sessions" antigravity-cli-ide-list-sessions)]
   ["Navigation"
    ("b" "Switch to buffer" antigravity-cli-ide-switch-to-buffer)
    ("w" "Toggle window visibility" antigravity-cli-ide-toggle-window)
    ("W" "Toggle recent window" antigravity-cli-ide-toggle-recent)]
   ["Interaction"
    ("i" antigravity-cli-ide-insert-at-mentioned :description antigravity-cli-ide--insert-description)
    ("p" "Send prompt from minibuffer" antigravity-cli-ide-send-prompt)
    ("e" "Send escape key" antigravity-cli-ide-send-escape)
    ("n" "Insert newline" antigravity-cli-ide-insert-newline)]
   ["Submenus"
    ("C" "Configuration" antigravity-cli-ide-config-menu)
    ("d" "Debugging" antigravity-cli-ide-debug-menu)]])

(transient-define-prefix antigravity-cli-ide-config-menu ()
  "Antigravity configuration menu."
  ["Antigravity Configuration"
   ["Window Settings"
    ("s" "Set window side" antigravity-cli-ide--set-window-side)
    ("w" "Set window width" antigravity-cli-ide--set-window-width)
    ("h" "Set window height" antigravity-cli-ide--set-window-height)
    ("f" "Toggle focus on open" antigravity-cli-ide--toggle-focus-on-open
     :description (lambda () (format "Focus on open (%s)"
                                     (if antigravity-cli-ide-focus-on-open "ON" "OFF"))))
    ("e" "Toggle focus after ediff" antigravity-cli-ide--toggle-focus-after-ediff
     :description (lambda () (format "Focus after ediff (%s)"
                                     (if antigravity-cli-ide-focus-antigravity-after-ediff "ON" "OFF"))))
    ("E" "Toggle show window in ediff" antigravity-cli-ide--toggle-show-antigravity-in-ediff
     :description (lambda () (format "Show window in ediff (%s)"
                                     (if antigravity-cli-ide-show-antigravity-window-in-ediff "ON" "OFF"))))
    ("i" "Toggle IDE diff viewer" antigravity-cli-ide--toggle-use-ide-diff
     :description (lambda () (format "IDE diff viewer (%s)"
                                     (if antigravity-cli-ide-use-ide-diff "ON" "OFF"))))
    ("t" "Toggle tab switching on ediff" antigravity-cli-ide--toggle-switch-tab-on-ediff
     :description (lambda () (format "Tab switch on ediff (%s)"
                                     (if antigravity-cli-ide-switch-tab-on-ediff "ON" "OFF"))))
    ("u" "Toggle side window" antigravity-cli-ide--toggle-use-side-window
     :description (lambda () (format "Use side window (%s)"
                                     (if antigravity-cli-ide-use-side-window "ON" "OFF"))))]
   ["Context Settings"
    ("a" "Toggle auto-prefix prompt" antigravity-cli-ide--toggle-auto-prefix-prompt
     :description (lambda () (format "Auto prefix prompt (%s)"
                                     (if antigravity-cli-ide-auto-prefix-prompt "ON" "OFF"))))
    ("A" "Toggle auto-fill context on focus" antigravity-cli-ide--toggle-auto-fill-context
     :description (lambda () (format "Auto-fill on focus (%s)"
                                     (if antigravity-cli-ide-auto-fill-context "ON" "OFF"))))]
   ["CLI Settings"
    ("p" "Set CLI path" antigravity-cli-ide--set-cli-path)
    ("x" "Set extra CLI flags" antigravity-cli-ide--set-cli-extra-flags)]]
  ["Save"
   ("S" "Save configuration" antigravity-cli-ide--save-config)])

(transient-define-prefix antigravity-cli-ide-debug-menu ()
  "Antigravity debug menu."
  ["Antigravity Debug"
   ["Status"
    ("S" "Check CLI status" antigravity-cli-ide-check-status)
    ("v" "Show info & changelog" antigravity-cli-ide-show-version-info)]
   ["Debug Settings"
    ("d" "Toggle debug mode" antigravity-cli-ide-toggle-debug-mode
     :description (lambda () (format "Debug mode (%s)"
                                     (if antigravity-cli-ide-debug "ON" "OFF"))))
    ("D" "Toggle CLI debug mode" antigravity-cli-ide--toggle-cli-debug
     :description (lambda () (format "CLI debug mode (%s)"
                                     (if antigravity-cli-ide-cli-debug "ON" "OFF"))))]
   ["Debug Logs"
    ("l" "Show debug log" antigravity-cli-ide-show-debug)
    ("c" "Clear debug log" antigravity-cli-ide-clear-debug)]
   ["MCP Server"
    ("m" "Show MCP sessions" antigravity-cli-ide-show-mcp-sessions)
    ("p" "Show active ports" antigravity-cli-ide-show-active-ports)]])

(provide 'antigravity-cli-ide-transient)
;;; antigravity-cli-ide-transient.el ends here
