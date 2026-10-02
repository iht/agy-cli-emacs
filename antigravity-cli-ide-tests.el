;;; antigravity-cli-ide-tests.el --- Tests for Antigravity CLI IDE  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

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
  (let ((dir "/home/ihr/projects/my-test-project"))
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

(provide 'antigravity-cli-ide-tests)
;;; antigravity-cli-ide-tests.el ends here
