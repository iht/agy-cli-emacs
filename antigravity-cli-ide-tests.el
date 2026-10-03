;;; antigravity-cli-ide-tests.el --- Tests for Antigravity CLI IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Yoav Orot
;; Copyright (C) 2026 Israel Herraiz

;; Author: Israel Herraiz <isra@herraiz.org>
;; Assisted-by: Google Antigravity:gemini-3.8-flash
;; Maintainer: Israel Herraiz <isra@herraiz.org>
;; Keywords: tools, processes, convenience, ai, antigravity

;; Test suite for antigravity-cli-ide.el using ERT
;;
;; Run tests with:
;;   `emacs -batch -L . -l ert -l antigravity-cli-ide-tests.el -f ert-run-tests-batch-and-exit'

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'project)

;;; Mock implementations for testing environment stability

(unless (featurep 'vterm)
  (provide 'vterm))

(unless (featurep 'eat)
  (provide 'eat))

;; Ensure transient library and internal stubs are available in batch testing mode
(require 'transient nil t)

(unless (fboundp 'transient--set-layout)
  (defun transient--set-layout (prefix layout)
    "Mock stub for `transient--set-layout' in test environments."
    (put prefix 'transient--layout layout)))

(unless (facep 'transient-inactive-value)
  (defface transient-inactive-value
    '((t :inherit shadow))
    "Fallback face for `transient-inactive-value' in test environments."
    :group 'antigravity-cli-ide))

(require 'antigravity-cli-ide)
(require 'antigravity-cli-ide-transient)
(require 'antigravity-cli-ide-mcp)
(require 'antigravity-cli-ide-diagnostics)

;;; Test Cases

(ert-deftest test-antigravity-cli-ide-variables-defined ()
  "Verify that the customization options are properly defined with expected defaults."
  (should (boundp 'antigravity-cli-ide-cli-path))
  (should (string= antigravity-cli-ide-cli-path "agy"))
  
  (should (boundp 'antigravity-cli-ide-window-side))
  (should (eq antigravity-cli-ide-window-side 'right))
  
  (should (boundp 'antigravity-cli-ide-use-ide-diff))
  (should (eq antigravity-cli-ide-use-ide-diff t)))

(ert-deftest test-antigravity-cli-ide-command-builder ()
  "Verify that the command-line argument builder outputs correct strings."
  (let ((antigravity-cli-ide-cli-path "agy")
        (antigravity-cli-ide-cli-extra-flags ""))
    ;; Basic command
    (should (string= (antigravity-cli-ide--build-antigravity-command) "agy"))
    
    ;; With continue flag
    (should (string= (antigravity-cli-ide--build-antigravity-command t) "agy -c"))
    
    ;; With resume flag
    (should (string= (antigravity-cli-ide--build-antigravity-command nil t) "agy -c"))
    
    ;; With extra flags
    (let ((antigravity-cli-ide-cli-extra-flags "--sandbox"))
      (should (string= (antigravity-cli-ide--build-antigravity-command) "agy --sandbox"))
      (should (string= (antigravity-cli-ide--build-antigravity-command t) "agy -c --sandbox")))))

(ert-deftest test-antigravity-cli-ide-buffer-naming ()
  "Verify that buffers are dynamically named based on working directories."
  (let ((dir "/path/to/my-test-project"))
    (should (string= (antigravity-cli-ide--default-buffer-name dir)
                     "*antigravity-cli[my-test-project]*"))))

(ert-deftest test-antigravity-cli-ide-diagnostics-severity ()
  "Verify that flycheck/flymake severity levels map correctly to VS Code format."
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'error) 1))
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'warning) 2))
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'info) 3))
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'hint) 4))
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'flymake-error) 1))
  (should (eq (antigravity-cli-ide-diagnostics--severity-to-vscode 'flymake-warning) 2)))

(ert-deftest test-antigravity-cli-ide-session-lifecycle ()
  "Verify that MCP session registries start and stop correctly."
  (let ((project-dir "/tmp/test-project-session-dir")
        (session-id "agy-test-session-123"))
    (unwind-protect
        (let ((port (antigravity-cli-ide-mcp-start-session project-dir session-id)))
          ;; Session should be created on a valid port
          (should (integerp port))
          (should (> port 0))
          
          ;; Session context should be registered
          (let ((session (antigravity-cli-ide-mcp--get-session-for-project project-dir)))
            (should session)
            (should (eq (antigravity-cli-ide-mcp-session-port session) port))
            (should (string= (antigravity-cli-ide-mcp-session-project-dir session) project-dir)))
          
          ;; Dynamic config file should have the entry
          (let ((config-path (antigravity-cli-ide-mcp--get-mcp-config-path)))
            (should (file-exists-p config-path))
            (let* ((config (json-read-file config-path))
                   (servers (cdr (assoc 'mcpServers config)))
                   (emacs-entry (cdr (assoc 'antigravity-emacs-tools servers))))
              (should emacs-entry)
              (should (string= (cdr (assoc 'command emacs-entry)) "nc"))
              (should (equal (cdr (assoc 'args emacs-entry)) (vector "127.0.0.1" (format "%d" port)))))))
      
      ;; Cleanup and ensure removal from registries and files
      (antigravity-cli-ide-mcp-stop-session project-dir)
      (should-not (antigravity-cli-ide-mcp--get-session-for-project project-dir))
      
      (let ((config-path (antigravity-cli-ide-mcp--get-mcp-config-path)))
        (when (file-exists-p config-path)
          (let* ((config (json-read-file config-path))
                 (servers (cdr (assoc 'mcpServers config))))
            (should-not (assoc 'antigravity-emacs-tools servers))))))))

(ert-deftest test-antigravity-cli-ide-find-cli ()
  "Verify that antigravity-cli-ide--find-cli resolves CLI even if not in standard exec-path."
  (let ((antigravity-cli-ide-cli-path "agy")
        (antigravity-cli-ide--cli-available nil))
    (let ((found (antigravity-cli-ide--find-cli)))
      (when (file-executable-p (expand-file-name "~/.local/bin/agy"))
        (should found)
        (should (file-executable-p found))
        (should (antigravity-cli-ide--ensure-cli))))))

(ert-deftest test-antigravity-cli-ide-transient-symbols-bound ()
  "Verify that transient dependencies and interactive menus are safely bound in batch mode."
  (should (featurep 'transient))
  (should (fboundp 'transient--set-layout))
  (should (fboundp 'antigravity-cli-ide-menu))
  (should (fboundp 'antigravity-cli-ide-config-menu))
  (should (fboundp 'antigravity-cli-ide-debug-menu)))

(ert-deftest test-antigravity-cli-ide-target-buffer-and-format ()
  "Verify target buffer resolution and context formatting with and without region."
  (let* ((proj-dir (antigravity-cli-ide--get-working-directory))
         (temp-file (expand-file-name "test-context-file.txt" proj-dir))
         (buf (find-file-noselect temp-file)))
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\n")
          (goto-char (point-min))
          (antigravity-cli-ide--track-active-buffer)
          
          ;; Target buffer resolves to the current buffer
          (should (eq (antigravity-cli-ide--get-target-buffer) buf))
          
          ;; Without region, should format as @test-context-file.txt
          (should (string= (antigravity-cli-ide--format-context-reference)
                           "@test-context-file.txt"))
          
          ;; With active region from line 2 to line 4
          (goto-line 2)
          (set-mark (point))
          (goto-line 4)
          (end-of-line)
          (activate-mark)
          
          (should (use-region-p))
          (should (string= (antigravity-cli-ide--format-context-reference)
                           "@test-context-file.txt:2-4"))
          (deactivate-mark))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (set-buffer-modified-p nil))
        (kill-buffer buf))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest test-antigravity-cli-ide-target-buffer-from-session ()
  "Verify target buffer resolution when currently inside a session buffer."
  (let* ((proj-dir (antigravity-cli-ide--get-working-directory))
         (temp-file (expand-file-name "test-file-companion.txt" proj-dir))
         (file-buf (find-file-noselect temp-file))
         (session-buf (get-buffer-create "*antigravity-cli[test-proj]*")))
    (unwind-protect
        (progn
          ;; Visit file buffer and track it
          (with-current-buffer file-buf
            (antigravity-cli-ide--track-active-buffer))
          
          ;; Inside session buffer, target buffer should resolve to tracked file buffer
          (with-current-buffer session-buf
            (should (antigravity-cli-ide--session-buffer-p session-buf))
            (should (eq (antigravity-cli-ide--get-target-buffer) file-buf))
            (should (string= (antigravity-cli-ide--format-context-reference)
                             "@test-file-companion.txt"))))
      (when (buffer-live-p file-buf)
        (with-current-buffer file-buf (set-buffer-modified-p nil))
        (kill-buffer file-buf))
      (when (buffer-live-p session-buf)
        (kill-buffer session-buf))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(ert-deftest test-antigravity-cli-ide-mcp-current-context-tool ()
  "Verify getCurrentBufferContext MCP tool registration and response structure."
  ;; Tool should be registered in tool list and schemas
  (let ((tool-names (mapcar #'car (antigravity-cli-ide-mcp--build-tool-list)))
        (schemas (antigravity-cli-ide-mcp--build-tool-schemas)))
    (should (member "getCurrentBufferContext" tool-names))
    (should (assoc "getCurrentBufferContext" schemas)))
  
  ;; Test tool execution with active file
  (let* ((proj-dir (antigravity-cli-ide--get-working-directory))
         (temp-file (expand-file-name "test-mcp-context.txt" proj-dir))
         (buf (find-file-noselect temp-file)))
    (unwind-protect
        (with-current-buffer buf
          (erase-buffer)
          (insert "Line A\nLine B\nLine C\n")
          (goto-line 2)
          (antigravity-cli-ide--track-active-buffer)
          
          (let* ((resp (antigravity-cli-ide-mcp-handle-get-current-context nil))
                 (item (car resp))
                 (text (cdr (assoc 'text item)))
                 (parsed (json-read-from-string text)))
            (should (string= (cdr (assoc 'type item)) "text"))
            (should (string= (cdr (assoc 'relativePath parsed)) "test-mcp-context.txt"))
            (should (eq (cdr (assoc 'cursorLine parsed)) 2))))
      (when (buffer-live-p buf)
        (with-current-buffer buf (set-buffer-modified-p nil))
        (kill-buffer buf))
      (when (file-exists-p temp-file)
        (delete-file temp-file)))))

(provide 'antigravity-cli-ide-tests)
;;; antigravity-cli-ide-tests.el ends here
