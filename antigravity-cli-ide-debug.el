;;; antigravity-cli-ide-debug.el --- Debug logging for Antigravity CLI IDE  -*- lexical-binding: t; -*-

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

;; This file provides debug logging functionality for Antigravity CLI IDE.
;; It supports structured logging of JSON-RPC communication and general
;; debug information with session context.

;;; Code:

(require 'json)
(require 'project)

;;; Customization

(defgroup antigravity-cli-ide nil
  "Antigravity CLI integration for Emacs."
  :group 'tools
  :prefix "antigravity-cli-ide-")

(defcustom antigravity-cli-ide-debug nil
  "When non-nil, enable debug logging for Antigravity CLI IDE."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-log-with-context t
  "When non-nil, include session context in log messages."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-debug-buffer "*antigravity-cli-ide-debug*"
  "Buffer name for debug output."
  :type 'string
  :group 'antigravity-cli-ide)

;;; Debug Functions

(defun antigravity-cli-ide--get-session-context ()
  "Get current session context for logging."
  (if antigravity-cli-ide-log-with-context
      (format "[%s]" (or (ignore-errors
                           (file-name-nondirectory
                            (directory-file-name
                             (project-root (project-current)))))
                         "no-project"))
    ""))

(defmacro antigravity-cli-ide-debug (format-string &rest args)
  "Log debug message with FORMAT-STRING and ARGS if debug is enabled.
This is a macro to avoid evaluating ARGS when debugging is disabled."
  `(when antigravity-cli-ide-debug
     (let ((message (format ,format-string ,@args))
           (timestamp (format-time-string "%Y-%m-%d %H:%M:%S"))
           (context (antigravity-cli-ide--get-session-context)))
       (with-current-buffer (get-buffer-create antigravity-cli-ide-debug-buffer)
         (goto-char (point-max))
         (insert (format "%s %s%s\n" timestamp context message))))))

(defun antigravity-cli-ide-log (format-string &rest args)
  "Log message with FORMAT-STRING and ARGS."
  (let ((message (apply #'format format-string args)))
    (message "%s %s" (antigravity-cli-ide--get-session-context) message)))

;;;###autoload
(defun antigravity-cli-ide-show-debug ()
  "Show the debug buffer."
  (interactive)
  (display-buffer (get-buffer-create antigravity-cli-ide-debug-buffer)))

;;;###autoload
(defun antigravity-cli-ide-clear-debug ()
  "Clear the debug buffer."
  (interactive)
  (with-current-buffer (get-buffer-create antigravity-cli-ide-debug-buffer)
    (erase-buffer)
    (message "Debug buffer cleared")))

(provide 'antigravity-cli-ide-debug)

;;; antigravity-cli-ide-debug.el ends here
