;;; antigravity-cli-ide-diagnostics.el --- Diagnostic integration for Antigravity CLI IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Yoav Orot (Adapted for Antigravity CLI)
;; Keywords: ai, antigravity, diagnostics, flycheck

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

;; This file provides diagnostic integration for Antigravity CLI IDE.
;; It collects diagnostics from Flycheck/Flymake and converts them to
;; VS Code format for the MCP protocol.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'antigravity-cli-ide-debug)

;; Optional dependencies
(require 'flycheck nil t)
(require 'flymake nil t)

;; Forward declarations
(declare-function antigravity-cli-ide-mcp-session-project-dir "antigravity-cli-ide-mcp" (session))

;; Flycheck declarations
(defvar flycheck-current-errors)
(declare-function flycheck-error-line "flycheck" (err))
(declare-function flycheck-error-column "flycheck" (err))
(declare-function flycheck-error-end-line "flycheck" (err))
(declare-function flycheck-error-end-column "flycheck" (err))
(declare-function flycheck-error-level "flycheck" (err))
(declare-function flycheck-error-checker "flycheck" (err))
(declare-function flycheck-error-message "flycheck" (err))

;;; Configuration

(defcustom antigravity-cli-ide-diagnostics-backend 'auto
  "Backend to use for diagnostics collection.
Can be one of:
- `auto': Automatically detect available backend (flycheck or flymake)
- `flycheck': Use flycheck for diagnostics
- `flymake': Use flymake for diagnostics"
  :type '(choice (const :tag "Automatic detection" auto)
                 (const :tag "Flycheck" flycheck)
                 (const :tag "Flymake" flymake))
  :group 'antigravity-cli-ide)

;;; Diagnostic Collection

(defun antigravity-cli-ide-diagnostics--severity-to-vscode (severity)
  "Convert diagnostic SEVERITY to VS Code format.
Returns: 1 (Error), 2 (Warning), 3 (Information), 4 (Hint)."
  (pcase severity
    ;; Flycheck severities
    ('error 1)
    ('warning 2)
    ('info 3)
    ('hint 4)
    ;; Flymake severities
    ('flymake-error 1)
    (':error 1)
    ('flymake-warning 2)
    (':warning 2)
    ('flymake-note 3)
    (':note 3)
    ;; Default
    (_ 3)))

(defun antigravity-cli-ide-diagnostics--severity-to-string (severity)
  "Convert diagnostic SEVERITY to VS Code string format."
  (pcase severity
    ;; Flycheck severities
    ('error "Error")
    ('warning "Warning")
    ('info "Information")
    ('hint "Hint")
    ;; Flymake severities
    ('flymake-error "Error")
    (':error "Error")
    ('flymake-warning "Warning")
    (':warning "Warning")
    ('flymake-note "Information")
    (':note "Information")
    ;; Default
    (_ "Information")))

(defun antigravity-cli-ide-diagnostics--get-flycheck-diagnostics (buffer)
  "Get Flycheck diagnostics for BUFFER in VS Code format."
  (when (featurep 'flycheck)
    (with-current-buffer buffer
      (when (bound-and-true-p flycheck-mode)
        (mapcar (lambda (err)
                  `((range . ((start . ((line . ,(flycheck-error-line err))
                                        (character . ,(if (flycheck-error-column err)
                                                          (flycheck-error-column err)
                                                        1))))
                              (end . ((line . ,(or (flycheck-error-end-line err)
                                                   (flycheck-error-line err)))
                                      (character . ,(if (or (flycheck-error-end-column err)
                                                            (flycheck-error-column err))
                                                        (or (flycheck-error-end-column err)
                                                            (flycheck-error-column err))
                                                      1))))))
                    (severity . ,(antigravity-cli-ide-diagnostics--severity-to-string
                                  (flycheck-error-level err)))
                    (source . ,(or (flycheck-error-checker err) "flycheck"))
                    (message . ,(flycheck-error-message err))))
                flycheck-current-errors)))))

(defun antigravity-cli-ide-diagnostics--get-flymake-diagnostics (buffer)
  "Get Flymake diagnostics for BUFFER in VS Code format."
  (when (featurep 'flymake)
    (with-current-buffer buffer
      (when (bound-and-true-p flymake-mode)
        (mapcar (lambda (diag)
                  (save-excursion
                    (let* ((beg (flymake-diagnostic-beg diag))
                           (end (flymake-diagnostic-end diag))
                           (beg-line (progn (goto-char beg)
                                            (line-number-at-pos)))
                           (beg-col (current-column))
                           (end-line (progn (goto-char end)
                                            (line-number-at-pos)))
                           (end-col (current-column)))
                      `((range . ((start . ((line . ,beg-line)
                                            (character . ,beg-col)))
                                  (end . ((line . ,end-line)
                                          (character . ,end-col)))))
                        (severity . ,(antigravity-cli-ide-diagnostics--severity-to-string
                                      (flymake-diagnostic-type diag)))
                        (source . ,(symbol-name (or (flymake-diagnostic-backend diag)
                                                    'flymake)))
                        (message . ,(flymake-diagnostic-text diag))))))
                (flymake-diagnostics))))))

(defun antigravity-cli-ide-diagnostics-get-all (buffer)
  "Get diagnostics for BUFFER using configured backend.
Returns diagnostics in VS Code format."
  (let ((backend antigravity-cli-ide-diagnostics-backend))
    ;; Handle auto detection
    (when (eq backend 'auto)
      (setq backend
            (cond
             ((and (featurep 'flycheck)
                   (with-current-buffer buffer
                     (bound-and-true-p flycheck-mode)))
              'flycheck)
             ((and (featurep 'flymake)
                   (with-current-buffer buffer
                     (bound-and-true-p flymake-mode)))
              'flymake)
             (t nil))))
    ;; Get diagnostics based on backend
    (or (vconcat
         (pcase backend
           ('flycheck (antigravity-cli-ide-diagnostics--get-flycheck-diagnostics buffer))
           ('flymake (antigravity-cli-ide-diagnostics--get-flymake-diagnostics buffer))
           (_ nil)))
        [])))

;;; MCP Handler

(defun antigravity-cli-ide-uri-to-file-path (uri)
  "Convert a file URI to a file path."
  (if (string-prefix-p "file://" uri)
      (url-unhex-string (substring uri 7))
    uri))

(defun antigravity-cli-ide-file-path-to-uri (file-path)
  "Convert a FILE-PATH to a file URI."
  (concat "file://" (url-hexify-string file-path)))

(defun antigravity-cli-ide-diagnostics-handler (params &optional session)
  "Handle getDiagnostics tool request with PARAMS.
Optional SESSION contains the MCP session context."
  (let* ((uri (alist-get 'uri params))
         (diagnostics-by-file '())
         (project-dir (when session
                        (antigravity-cli-ide-mcp-session-project-dir session))))
    (antigravity-cli-ide-debug "Diagnostics handler called with URI: %s, project-dir: %s" uri project-dir)
    (if (and uri (not (string-empty-p uri)))
        ;; Get diagnostics for specific file
        (let* ((file-path (antigravity-cli-ide-uri-to-file-path uri))
               (buffer (get-file-buffer (expand-file-name file-path))))
          (when buffer
            (let ((diags (antigravity-cli-ide-diagnostics-get-all buffer)))
              (when (> (length diags) 0)
                (push `((uri . ,uri)
                        (diagnostics . ,diags))
                      diagnostics-by-file)))))
      ;; Get diagnostics for all files in the session's project
      (let ((buffer-count 0)
            (checked-count 0))
        (dolist (buffer (buffer-list))
          (when-let ((file (buffer-file-name buffer)))
            (setq buffer-count (1+ buffer-count))
            ;; Filter by project directory if session is available
            (when (or (not project-dir)
                      (string-prefix-p (expand-file-name project-dir)
                                       (expand-file-name file)))
              (setq checked-count (1+ checked-count))
              (antigravity-cli-ide-debug "Checking buffer: %s" file)
              (let ((diags (antigravity-cli-ide-diagnostics-get-all buffer)))
                (antigravity-cli-ide-debug "Found %d diagnostics for %s" (length diags) file)
                (when (> (length diags) 0)
                  (push `((uri . ,(antigravity-cli-ide-file-path-to-uri file))
                          (diagnostics . ,diags))
                        diagnostics-by-file))))))
        (antigravity-cli-ide-debug "Checked %d/%d buffers with files" checked-count buffer-count)))
    ;; Return JSON-encoded string in content array format
    (let ((json-str (if diagnostics-by-file
                        (json-encode (vconcat (nreverse diagnostics-by-file)))
                      "[]")))
      (list `((type . "text")
              (text . ,json-str))))))

(provide 'antigravity-cli-ide-diagnostics)

;;; antigravity-cli-ide-diagnostics.el ends here
