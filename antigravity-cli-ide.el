;;; antigravity-cli-ide.el --- Antigravity CLI integration for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Yoav Orot (Adapted for Antigravity CLI)
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (transient "0.9.0"))
;; Keywords: ai, antigravity, code, assistant, mcp
;; URL: https://github.com/manzaltu/claude-code-ide.el

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

;; Antigravity CLI IDE integration for Emacs provides seamless integration
;; with the Antigravity CLI (`agy` executable) through the Model Context Protocol (MCP).
;; It supports file operations, diagnostics, and editor state management.
;;
;; This package starts a TCP socket server in Emacs, and dynamically configures
;; `~/.gemini/antigravity-cli/mcp_config.json` so that the CLI connects back to Emacs
;; using standard `nc` (netcat).
;;
;; Features:
;; - Pure TCP socket server requiring no third-party libraries (no websocket.el or web-server.el needed)
;; - Automatic dynamic management of global `mcp_config.json`
;; - Support for vterm and eat terminal backends
;; - Window-management, side-windows, and session restore
;; - Multi-session support per project
;;
;; Usage:
;; M-x antigravity-cli-ide - Start Antigravity CLI for current project
;; M-x antigravity-cli-ide-continue - Continue most recent conversation
;; M-x antigravity-cli-ide-stop - Stop session
;; M-x antigravity-cli-ide-menu - Interactive transient control panel

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'antigravity-cli-ide-debug)
(require 'antigravity-cli-ide-mcp)
(require 'antigravity-cli-ide-transient)
(require 'antigravity-cli-ide-emacs-tools)

;; External variables and functions declarations
(defvar eat-terminal)
(defvar eat--synchronize-scroll-function)
(defvar vterm-shell)
(defvar vterm-environment)
(defvar eat-term-name)
(defvar vterm--process)

(declare-function vterm "vterm" (&optional arg))
(declare-function vterm-send-string "vterm" (string))
(declare-function vterm-send-escape "vterm" ())
(declare-function vterm-send-return "vterm" ())
(declare-function vterm--window-adjust-process-window-size "vterm" (&optional frame))

(declare-function eat-mode "eat" ())
(declare-function eat-exec "eat" (buffer name command startfile &rest switches))
(declare-function eat-term-send-string "eat" (terminal string))
(declare-function eat-term-display-cursor "eat" (terminal))
(declare-function eat--adjust-process-window-size "eat" (process windows))

;;; Customization

(defcustom antigravity-cli-ide-cli-path "agy"
  "Path to the Antigravity CLI executable."
  :type 'string
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-buffer-name-function #'antigravity-cli-ide--default-buffer-name
  "Function to generate buffer names for Antigravity sessions."
  :type 'function
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-cli-debug nil
  "When non-nil, launch Antigravity CLI in debug mode."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-cli-extra-flags ""
  "Additional flags to pass to the Antigravity CLI."
  :type 'string
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-window-side 'right
  "Side of the frame where the Antigravity window should appear."
  :type '(choice (const left) (const right) (const top) (const bottom))
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-window-width 100
  "Body width of the Antigravity side window."
  :type 'integer
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-window-height 20
  "Height of the Antigravity side window when opened top/bottom."
  :type 'integer
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-focus-on-open t
  "Whether to focus the Antigravity window when it opens."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-focus-antigravity-after-ediff t
  "Whether to focus the Antigravity window after opening ediff."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-show-antigravity-window-in-ediff t
  "Whether to show the Antigravity side window when viewing diffs."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-enable-execute-code t
  "Whether to allow evaluating Elisp in Emacs via executeCode tool."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-use-ide-diff t
  "Whether to use IDE diff viewer (ediff) for file differences."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-switch-tab-on-ediff t
  "Whether to switch back to Antigravity's original tab when opening ediff."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-use-side-window t
  "Whether to display Antigravity in a side window."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-terminal-backend 'vterm
  "Terminal backend to use: `vterm' or `eat'."
  :type '(choice (const vterm) (const eat))
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-prevent-reflow-glitch t
  "Workaround for terminal scrolling issues."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-eat-preserve-position t
  "Maintain scroll position in eat terminal when switching windows."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-terminal-initialization-delay 0.1
  "Delay in seconds for terminal layout stabilization."
  :type 'number
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-vterm-anti-flicker t
  "Enable batch updates rendering optimization for vterm."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-vterm-render-delay 0.005
  "Rendering optimization delay for batched terminal updates."
  :type 'number
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-auto-prefix-prompt t
  "When non-nil, `antigravity-cli-ide-send-prompt' pre-fills the prompt with the active file."
  :type 'boolean
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-auto-fill-context nil
  "Whether to automatically insert the companion file context upon focusing Antigravity.
When nil, context is only inserted via commands (`antigravity-cli-ide-insert-at-mentioned'
or `antigravity-cli-ide-send-prompt').
When 'on-switch, switching focus to the Antigravity window automatically types
the @file reference into the terminal if a new turn has started."
  :type '(choice (const :tag "Disabled (command only)" nil)
                 (const :tag "Auto-fill on focus" on-switch))
  :group 'antigravity-cli-ide)

(defcustom antigravity-cli-ide-include-line-numbers-with-region t
  "When non-nil and a region is active, format context with line numbers: @file:START-END."
  :type 'boolean
  :group 'antigravity-cli-ide)

;;; State Variables

(defvar antigravity-cli-ide--cli-available nil)
(defvar antigravity-cli-ide--processes (make-hash-table :test 'equal))
(defvar antigravity-cli-ide--session-ids (make-hash-table :test 'equal))
(defvar antigravity-cli-ide--last-accessed-buffer nil)
(defvar antigravity-cli-ide--last-active-file-buffer nil
  "Last focused buffer that was visiting a file and not an Antigravity terminal.")
(defvar-local antigravity-cli-ide--context-inserted-for-turn nil
  "Whether file context was already inserted into the terminal for the current prompt turn.")

;;; Vterm rendering optimizations

(defvar-local antigravity-cli-ide--vterm-render-queue nil)
(defvar-local antigravity-cli-ide--vterm-render-timer nil)

(defun antigravity-cli-ide--count-escape-sequence (sequence input)
  (let ((count 0) (start 0))
    (while (setq start (string-search sequence input start))
      (cl-incf count)
      (cl-incf start (length sequence)))
    count))

(defun antigravity-cli-ide--vterm-smart-renderer (orig-fun process input)
  (if (or (not antigravity-cli-ide-vterm-anti-flicker)
          (not (antigravity-cli-ide--session-buffer-p (process-buffer process))))
      (funcall orig-fun process input)
    (with-current-buffer (process-buffer process)
      (if (and (not antigravity-cli-ide--vterm-render-queue)
               (not (string-search "\033" input)))
          (funcall orig-fun process input)
        (let* ((complex-redraw
                (string-match-p "\033\\[[0-9]*A.*\033\\[K.*\033\\[[0-9]*A.*\033\\[K" input))
               (clear-count (antigravity-cli-ide--count-escape-sequence "\033[K" input))
               (esc-count (cl-count ?\033 input))
               (len (length input))
               (density (if (> len 0) (/ (float esc-count) len) 0)))
          (if (or complex-redraw
                  (and (> density 0.3) (>= clear-count 2))
                  antigravity-cli-ide--vterm-render-queue)
              (progn
                (push input antigravity-cli-ide--vterm-render-queue)
                (when antigravity-cli-ide--vterm-render-timer
                  (cancel-timer antigravity-cli-ide--vterm-render-timer))
                (setq antigravity-cli-ide--vterm-render-timer
                      (run-at-time antigravity-cli-ide-vterm-render-delay nil
                                   (lambda (buf)
                                     (when (buffer-live-p buf)
                                       (with-current-buffer buf
                                         (when antigravity-cli-ide--vterm-render-queue
                                           (let* ((inhibit-redisplay t)
                                                  (queue antigravity-cli-ide--vterm-render-queue)
                                                  (data (apply #'concat (nreverse queue))))
                                             (setq antigravity-cli-ide--vterm-render-queue nil
                                                   antigravity-cli-ide--vterm-render-timer nil)
                                             (funcall orig-fun (get-buffer-process buf) data))))))
                                   (current-buffer))))
            (funcall orig-fun process input)))))))

(defvar-local antigravity-cli-ide--saved-cursor-type nil)

(defun antigravity-cli-ide--vterm-copy-mode-hook ()
  (if (bound-and-true-p vterm-copy-mode)
      (progn
        (setq antigravity-cli-ide--saved-cursor-type cursor-type)
        (when (null cursor-type) (setq cursor-type t)))
    (setq cursor-type antigravity-cli-ide--saved-cursor-type)))

(defun antigravity-cli-ide--configure-vterm-buffer ()
  (setq-local vterm-scroll-to-bottom-on-output nil)
  (when (boundp 'vterm--redraw-immididately)
    (setq-local vterm--redraw-immididately nil))
  (setq-local cursor-in-non-selected-windows nil)
  (setq-local blink-cursor-mode nil)
  (setq-local cursor-type nil)
  (setq-local global-hl-line-mode nil)
  (when (featurep 'hl-line) (hl-line-mode -1))
  (face-remap-add-relative 'nobreak-space :inherit 'default)
  (add-hook 'vterm-copy-mode-hook #'antigravity-cli-ide--vterm-copy-mode-hook nil t)
  (when-let ((proc (get-buffer-process (current-buffer))))
    (set-process-query-on-exit-flag proc nil)
    (when (fboundp 'process-put)
      (process-put proc 'read-output-max 4096)))
  (when antigravity-cli-ide-vterm-anti-flicker
    (advice-add 'vterm--filter :around #'antigravity-cli-ide--vterm-smart-renderer)))

;;; Terminal abstraction helpers

(defun antigravity-cli-ide--terminal-ensure-backend ()
  (cond
   ((eq antigravity-cli-ide-terminal-backend 'vterm)
    (unless (featurep 'vterm) (require 'vterm nil t))
    (unless (featurep 'vterm) (user-error "Please install the vterm package")))
   ((eq antigravity-cli-ide-terminal-backend 'eat)
    (unless (featurep 'eat) (require 'eat nil t))
    (unless (featurep 'eat) (user-error "Please install the eat package")))))

(defun antigravity-cli-ide--terminal-send-string (string)
  (cond
   ((eq antigravity-cli-ide-terminal-backend 'vterm) (vterm-send-string string))
   ((eq antigravity-cli-ide-terminal-backend 'eat)
    (when eat-terminal (eat-term-send-string eat-terminal string)))))

(defun antigravity-cli-ide--terminal-send-escape ()
  (cond
   ((eq antigravity-cli-ide-terminal-backend 'vterm) (vterm-send-escape))
   ((eq antigravity-cli-ide-terminal-backend 'eat)
    (when eat-terminal (eat-term-send-string eat-terminal "\e")))))

(defun antigravity-cli-ide--terminal-send-return ()
  (cond
   ((eq antigravity-cli-ide-terminal-backend 'vterm) (vterm-send-return))
   ((eq antigravity-cli-ide-terminal-backend 'eat)
    (when eat-terminal (eat-term-send-string eat-terminal "\r")))))

(defun antigravity-cli-ide--sync-terminal-dimensions (buffer window)
  (when (and buffer window (buffer-live-p buffer) (window-live-p window))
    (with-current-buffer buffer
      (when-let ((proc (get-buffer-process buffer)))
        (set-process-window-size proc (window-body-height window) (window-body-width window))))))

(defun antigravity-cli-ide-send-return ()
  "Send return key to terminal and reset context insertion turn state."
  (interactive)
  (setq antigravity-cli-ide--context-inserted-for-turn nil)
  (antigravity-cli-ide--terminal-send-return))

(defun antigravity-cli-ide--setup-terminal-keybindings ()
  (local-set-key (kbd "RET") #'antigravity-cli-ide-send-return)
  (local-set-key (kbd "<return>") #'antigravity-cli-ide-send-return)
  (local-set-key (kbd "S-<return>") #'antigravity-cli-ide-insert-newline)
  (local-set-key (kbd "C-<escape>") #'antigravity-cli-ide-send-escape))

;;; Reflow glitch workaround

(defun antigravity-cli-ide--terminal-resize-handler ()
  (pcase antigravity-cli-ide-terminal-backend
    ('vterm #'vterm--window-adjust-process-window-size)
    ('eat #'eat--adjust-process-window-size)))

(defun antigravity-cli-ide--terminal-scroll-mode-active-p ()
  (pcase antigravity-cli-ide-terminal-backend
    ('vterm (bound-and-true-p vterm-copy-mode))
    ('eat (not (bound-and-true-p eat--semi-char-mode)))))

(defun antigravity-cli-ide--session-buffer-p (buffer)
  (when-let ((name (if (stringp buffer) buffer (buffer-name buffer))))
    (string-prefix-p "*antigravity-cli[" name)))

(defun antigravity-cli-ide--terminal-reflow-filter (original-fn &rest args)
  (let ((res (apply original-fn args))
        (stable t))
    (dolist (win (window-list))
      (when-let* ((buf (window-buffer win))
                  ((antigravity-cli-ide--session-buffer-p buf)))
        (let ((w (window-width win))
              (cache (window-parameter win 'antigravity-cli-ide-cached-width)))
          (unless (eql w cache)
            (setq stable nil)
            (set-window-parameter win 'antigravity-cli-ide-cached-width w)))))
    (cond
     ((not (antigravity-cli-ide--session-buffer-p (current-buffer))) res)
     ((antigravity-cli-ide--terminal-scroll-mode-active-p) nil)
     (stable res)
     (t nil))))

;;; Context & Buffer Tracking

(defun antigravity-cli-ide--track-active-buffer (&optional _window)
  "Track the most recent file-visiting editor buffer."
  (let ((buf (current-buffer)))
    (unless (antigravity-cli-ide--session-buffer-p buf)
      (when (and (buffer-live-p buf) (buffer-file-name buf))
        (setq antigravity-cli-ide--last-active-file-buffer buf)))))

(defun antigravity-cli-ide--get-target-buffer ()
  "Return the buffer to use as the file context for Antigravity.
If the current buffer is visiting a file and is not an Antigravity terminal,
return it.  Otherwise, look for the most recently used window in the frame
displaying a file buffer, or fall back to `antigravity-cli-ide--last-active-file-buffer'."
  (let ((cur (current-buffer)))
    (cond
     ((and (buffer-live-p cur)
           (buffer-file-name cur)
           (not (antigravity-cli-ide--session-buffer-p cur)))
      cur)
     ;; Look for any visible window in the current frame displaying a file buffer
     ((let ((win (cl-find-if (lambda (w)
                               (let ((b (window-buffer w)))
                                 (and (buffer-live-p b)
                                      (buffer-file-name b)
                                      (not (antigravity-cli-ide--session-buffer-p b)))))
                             (window-list))))
        (when win (window-buffer win))))
     ;; Fall back to tracked buffer if still live and visiting a file
     ((and (buffer-live-p antigravity-cli-ide--last-active-file-buffer)
           (buffer-file-name antigravity-cli-ide--last-active-file-buffer))
      antigravity-cli-ide--last-active-file-buffer)
     (t nil))))

(defun antigravity-cli-ide--get-active-context-info ()
  "Get detailed context information about the active editor buffer.
Returns a plist with :buffer, :buffer-name, :file-path, :relative-path,
:line, :column, :region-active, :region-start, :region-end, and :selected-text."
  (when-let* ((target-buf (antigravity-cli-ide--get-target-buffer)))
    (with-current-buffer target-buf
      (let* ((file-path (buffer-file-name target-buf))
             (proj-dir (antigravity-cli-ide--get-working-directory))
             (rel-path (if (and file-path proj-dir (file-in-directory-p file-path proj-dir))
                           (file-relative-name file-path proj-dir)
                         file-path))
             (has-region (use-region-p))
             (beg (when has-region (region-beginning)))
             (end (when has-region (region-end)))
             (start-line (when has-region (line-number-at-pos beg)))
             (end-line (when has-region (line-number-at-pos end)))
             (selected-text (when has-region (buffer-substring-no-properties beg end))))
        (list :buffer target-buf
              :buffer-name (buffer-name target-buf)
              :file-path file-path
              :relative-path rel-path
              :line (line-number-at-pos (point))
              :column (current-column)
              :region-active has-region
              :region-start start-line
              :region-end end-line
              :selected-text selected-text)))))

(defun antigravity-cli-ide--format-context-reference (&optional target-buffer)
  "Format the `@file' or `@file:start-end' reference for TARGET-BUFFER or active context."
  (let ((info (if target-buffer
                  (with-current-buffer target-buffer
                    (let* ((file-path (buffer-file-name target-buffer))
                           (proj-dir (antigravity-cli-ide--get-working-directory))
                           (rel-path (if (and file-path proj-dir (file-in-directory-p file-path proj-dir))
                                         (file-relative-name file-path proj-dir)
                                       file-path))
                           (has-region (use-region-p)))
                      (list :relative-path rel-path
                            :region-active has-region
                            :region-start (when has-region (line-number-at-pos (region-beginning)))
                            :region-end (when has-region (line-number-at-pos (region-end))))))
                (antigravity-cli-ide--get-active-context-info))))
    (when-let* ((rel-path (plist-get info :relative-path)))
      (if (and antigravity-cli-ide-include-line-numbers-with-region
               (plist-get info :region-active)
               (plist-get info :region-start)
               (plist-get info :region-end))
          (format "@%s:%d-%d"
                  rel-path
                  (plist-get info :region-start)
                  (plist-get info :region-end))
        (format "@%s" rel-path)))))

(defun antigravity-cli-ide--handle-window-selection-change (frame-or-window)
  "Handle window selection changes to track active buffers and handle auto-context."
  (let* ((win (if (windowp frame-or-window) frame-or-window (selected-window)))
         (buf (window-buffer win)))
    (if (antigravity-cli-ide--session-buffer-p buf)
        ;; Switched into an Antigravity session buffer
        (when (and (eq antigravity-cli-ide-auto-fill-context 'on-switch)
                   (not (buffer-local-value 'antigravity-cli-ide--context-inserted-for-turn buf)))
          (when-let* ((ref (antigravity-cli-ide--format-context-reference)))
            (with-current-buffer buf
              (antigravity-cli-ide--terminal-send-string (concat ref " "))
              (setq antigravity-cli-ide--context-inserted-for-turn t)
              (antigravity-cli-ide-debug "Auto-filled context on focus: %s" ref))))
      ;; Switched into a regular buffer
      (antigravity-cli-ide--track-active-buffer))))

(add-hook 'window-selection-change-functions #'antigravity-cli-ide--handle-window-selection-change)
(add-hook 'buffer-list-update-hook #'antigravity-cli-ide--track-active-buffer)

;;; Helper Functions

(defun antigravity-cli-ide--default-buffer-name (directory)
  (format "*antigravity-cli[%s]*" (file-name-nondirectory (directory-file-name directory))))

(defun antigravity-cli-ide--get-working-directory ()
  (if-let ((project (project-current)))
      (expand-file-name (project-root project))
    (expand-file-name default-directory)))

(defun antigravity-cli-ide--get-buffer-name (&optional directory)
  (funcall antigravity-cli-ide-buffer-name-function
           (or directory (antigravity-cli-ide--get-working-directory))))

(defun antigravity-cli-ide--get-process (&optional directory)
  (gethash (or directory (antigravity-cli-ide--get-working-directory))
           antigravity-cli-ide--processes))

(defun antigravity-cli-ide--set-process (process &optional directory)
  (when (and antigravity-cli-ide-prevent-reflow-glitch
             (= (hash-table-count antigravity-cli-ide--processes) 0))
    (advice-add (antigravity-cli-ide--terminal-resize-handler)
                :around #'antigravity-cli-ide--terminal-reflow-filter))
  (puthash (or directory (antigravity-cli-ide--get-working-directory))
           process
           antigravity-cli-ide--processes))

(defun antigravity-cli-ide--cleanup-dead-processes ()
  (maphash (lambda (dir proc)
             (unless (process-live-p proc)
               (remhash dir antigravity-cli-ide--processes)))
           antigravity-cli-ide--processes))

(defun antigravity-cli-ide--cleanup-all-sessions ()
  (maphash (lambda (dir proc)
             (when (process-live-p proc)
               (antigravity-cli-ide--cleanup-on-exit dir)))
           antigravity-cli-ide--processes))

(add-hook 'kill-emacs-hook #'antigravity-cli-ide--cleanup-all-sessions)

(defun antigravity-cli-ide--display-buffer-in-side-window (buffer)
  (let ((window
         (if antigravity-cli-ide-use-side-window
             (let* ((side antigravity-cli-ide-window-side)
                    (slot 0)
                    (window-parameters '((no-delete-other-windows . t)))
                    (display-buffer-alist
                     `((,(regexp-quote (buffer-name buffer))
                        (display-buffer-in-side-window)
                        (side . ,side)
                        (slot . ,slot)
                        ,@(when (memq side '(left right))
                            `((window-width
                               . ,(lambda (win)
                                    (let ((delta (- antigravity-cli-ide-window-width
                                                    (window-body-width win))))
                                      (unless (zerop delta)
                                        (window-resize win delta t)))))))
                        ,@(when (memq side '(top bottom))
                            `((window-height . ,antigravity-cli-ide-window-height)))
                        (window-parameters . ,window-parameters)))))
               (display-buffer buffer))
           (display-buffer buffer))))
    (setq antigravity-cli-ide--last-accessed-buffer buffer)
    (when (and window antigravity-cli-ide-focus-on-open)
      (select-window window))
    (when (and window
               antigravity-cli-ide-use-side-window
               (memq antigravity-cli-ide-window-side '(top bottom)))
      (set-window-text-height window antigravity-cli-ide-window-height)
      (set-window-dedicated-p window t))
    (when window (antigravity-cli-ide--sync-terminal-dimensions buffer window))
    window))

(defvar antigravity-cli-ide--cleanup-in-progress nil)

(defun antigravity-cli-ide--cleanup-on-exit (directory)
  (unless antigravity-cli-ide--cleanup-in-progress
    (setq antigravity-cli-ide--cleanup-in-progress t)
    (unwind-protect
        (progn
          (remhash directory antigravity-cli-ide--processes)
          (when (and antigravity-cli-ide-prevent-reflow-glitch
                     (= (hash-table-count antigravity-cli-ide--processes) 0))
            (advice-remove (antigravity-cli-ide--terminal-resize-handler)
                           #'antigravity-cli-ide--terminal-reflow-filter))
          (when (and (eq antigravity-cli-ide-terminal-backend 'vterm)
                     antigravity-cli-ide-vterm-anti-flicker
                     (= (hash-table-count antigravity-cli-ide--processes) 0))
            (advice-remove 'vterm--filter #'antigravity-cli-ide--vterm-smart-renderer))
          
          (antigravity-cli-ide-mcp-stop-session directory)
          
          (let ((session-id (gethash directory antigravity-cli-ide--session-ids)))
            (antigravity-cli-ide-mcp-server-session-ended session-id)
            (when session-id (remhash directory antigravity-cli-ide--session-ids)))
          
          (let ((buffer-name (antigravity-cli-ide--get-buffer-name directory)))
            (when-let ((buffer (get-buffer buffer-name)))
              (when (buffer-live-p buffer)
                (let ((kill-buffer-hook nil)
                      (kill-buffer-query-functions nil))
                  (kill-buffer buffer)))))
          (antigravity-cli-ide-debug "Cleaned up Antigravity session for %s" directory))
      (setq antigravity-cli-ide--cleanup-in-progress nil))))

;;; CLI Detection

(defun antigravity-cli-ide--find-cli ()
  "Locate the Antigravity CLI executable.
If `antigravity-cli-ide-cli-path' is an absolute path, return it if executable.
Otherwise, search `exec-path', then fallback to common installation directories
such as ~/.local/bin and ~/.gemini/antigravity-cli/bin.
If found in a fallback directory, add that directory to `exec-path' and `PATH'."
  (cond
   ((and (file-name-absolute-p antigravity-cli-ide-cli-path)
         (file-executable-p antigravity-cli-ide-cli-path))
    antigravity-cli-ide-cli-path)
   ((executable-find antigravity-cli-ide-cli-path))
   (t
    (let* ((dirs (list (expand-file-name "~/.local/bin")
                       (expand-file-name "~/.gemini/antigravity-cli/bin")
                       (expand-file-name "~/bin")))
           (found (cl-loop for dir in dirs
                           for candidate = (expand-file-name antigravity-cli-ide-cli-path dir)
                           when (file-executable-p candidate)
                           return candidate)))
      (when found
        (let ((bin-dir (directory-file-name (file-name-directory found))))
          (add-to-list 'exec-path bin-dir)
          (setenv "PATH" (concat bin-dir ":" (getenv "PATH")))))
      found))))

(defun antigravity-cli-ide--detect-cli ()
  "Detect if Antigravity CLI is available."
  (let* ((cli (antigravity-cli-ide--find-cli))
         (available (and cli
                         (condition-case nil
                             (eq (call-process cli nil nil nil "--version") 0)
                           (error nil)))))
    (setq antigravity-cli-ide--cli-available (if available t nil))))

(defun antigravity-cli-ide--ensure-cli ()
  "Ensure Antigravity CLI is available, detect if needed."
  (unless antigravity-cli-ide--cli-available (antigravity-cli-ide--detect-cli))
  antigravity-cli-ide--cli-available)

;;; Commands

(defun antigravity-cli-ide--toggle-existing-window (existing-buffer working-dir)
  (let ((window (get-buffer-window existing-buffer)))
    (if window
        (progn
          (setq antigravity-cli-ide--last-accessed-buffer existing-buffer)
          (delete-window window))
      (progn
        (antigravity-cli-ide--display-buffer-in-side-window existing-buffer)
        (when-let ((session (antigravity-cli-ide-mcp--get-session-for-project working-dir)))
          (when (fboundp 'tab-bar--current-tab)
            (setf (antigravity-cli-ide-mcp-session-original-tab session) (tab-bar--current-tab))))))))

(defun antigravity-cli-ide--build-antigravity-command (&optional continue resume _session-id)
  (let ((cmd antigravity-cli-ide-cli-path))
    (cond
     (continue (setq cmd (concat cmd " -c")))
     (resume (setq cmd (concat cmd " -c"))))
    (when (and antigravity-cli-ide-cli-extra-flags
               (not (string-empty-p antigravity-cli-ide-cli-extra-flags)))
      (setq cmd (concat cmd " " antigravity-cli-ide-cli-extra-flags)))
    cmd))

(defun antigravity-cli-ide--parse-command-string (command-string)
  (let ((parts (split-string-shell-command command-string)))
    (cons (car parts) (cdr parts))))

(defun antigravity-cli-ide--create-terminal-session (buffer-name working-dir _port continue resume session-id)
  (antigravity-cli-ide--terminal-ensure-backend)
  (let* ((cmd-str (antigravity-cli-ide--build-antigravity-command continue resume session-id))
         (default-directory working-dir)
         (env-vars (list "TERM_PROGRAM=emacs" "FORCE_CODE_TERMINAL=true")))
    
    (cond
     ((eq antigravity-cli-ide-terminal-backend 'vterm)
      (let* ((vterm-buffer-name buffer-name)
             (vterm-shell cmd-str)
             (vterm-environment (append env-vars vterm-environment)))
        (let ((buffer (save-window-excursion (vterm vterm-buffer-name))))
          (unless buffer (error "Failed to create vterm buffer"))
          (with-current-buffer buffer (antigravity-cli-ide--configure-vterm-buffer))
          (let ((process (get-buffer-process buffer)))
            (unless process (error "Failed to get vterm process"))
            (cons buffer process)))))
     
     ((eq antigravity-cli-ide-terminal-backend 'eat)
      (let* ((buffer (get-buffer-create buffer-name))
             (cmd-parts (antigravity-cli-ide--parse-command-string cmd-str))
             (program (car cmd-parts))
             (args (cdr cmd-parts)))
        (with-current-buffer buffer
          (unless (eq major-mode 'eat-mode) (eat-mode))
          (when antigravity-cli-ide-eat-preserve-position
            (setq-local eat--synchronize-scroll-function #'antigravity-cli-ide--terminal-position-keeper))
          (setq-local process-environment (append env-vars process-environment))
          (eat-exec buffer buffer-name program nil args)
          (let ((process (get-buffer-process buffer)))
            (unless process (error "Failed to create eat process"))
            (cons buffer process))))))))

(defun antigravity-cli-ide--terminal-position-keeper (window-list)
  (dolist (win window-list)
    (if (eq win 'buffer)
        (goto-char (eat-term-display-cursor eat-terminal))
      (unless buffer-read-only
        (let ((tp (eat-term-display-cursor eat-terminal)))
          (set-window-point win tp)
          (cond
           ((>= tp (- (point-max) 2))
            (with-selected-window win (goto-char tp) (recenter -1)))
           ((not (pos-visible-in-window-p tp win))
            (with-selected-window win (goto-char tp) (recenter)))))))))

(defun antigravity-cli-ide--start-session (&optional continue resume)
  (unless (antigravity-cli-ide--ensure-cli)
    (user-error "Antigravity CLI ('agy' executable) not found in PATH"))
  
  (antigravity-cli-ide--cleanup-dead-processes)
  
  (let* ((working-dir (antigravity-cli-ide--get-working-directory))
         (buffer-name (antigravity-cli-ide--get-buffer-name))
         (existing-buffer (get-buffer buffer-name))
         (existing-process (antigravity-cli-ide--get-process working-dir)))
    
    (if (and existing-buffer (buffer-live-p existing-buffer) existing-process)
        (antigravity-cli-ide--toggle-existing-window existing-buffer working-dir)
      
      (antigravity-cli-ide--terminal-ensure-backend)
      
      (let* ((session-id (format "agy-%s-%s"
                                 (file-name-nondirectory (directory-file-name working-dir))
                                 (format-time-string "%Y%m%d-%H%M%S")))
             (port nil))
        
        (condition-case err
            (progn
              ;; Start MCP session server
              (setq port (antigravity-cli-ide-mcp-start-session working-dir session-id))
              
              ;; Setup emacs tools for it
              (antigravity-cli-ide-emacs-tools-setup)
              
              ;; Create terminal process
              (let* ((buf-and-proc (antigravity-cli-ide--create-terminal-session
                                    buffer-name working-dir port continue resume session-id))
                     (buffer (car buf-and-proc))
                     (process (cdr buf-and-proc)))
                
                (antigravity-cli-ide-mcp-server-session-started session-id working-dir buffer)
                (antigravity-cli-ide--set-process process working-dir)
                (puthash working-dir session-id antigravity-cli-ide--session-ids)
                
                (set-process-sentinel process
                                      (lambda (_proc event)
                                        (when (or (string-match "finished" event)
                                                  (string-match "exited" event)
                                                  (string-match "killed" event)
                                                  (string-match "terminated" event))
                                          (antigravity-cli-ide--cleanup-on-exit working-dir))))
                
                (with-current-buffer buffer
                  (add-hook 'kill-buffer-hook (lambda () (antigravity-cli-ide--cleanup-on-exit working-dir)) nil t)
                  (antigravity-cli-ide--setup-terminal-keybindings)
                  (cond
                   ((eq antigravity-cli-ide-terminal-backend 'vterm)
                    (add-hook 'vterm-exit-functions (lambda (&rest _) (when (buffer-live-p buffer) (kill-buffer buffer))) nil t))
                   ((eq antigravity-cli-ide-terminal-backend 'eat)
                    (setq-local eat-kill-buffer-on-exit t))))
                
                (sleep-for antigravity-cli-ide-terminal-initialization-delay)
                (antigravity-cli-ide--display-buffer-in-side-window buffer)
                (antigravity-cli-ide-log "Antigravity CLI started in %s with MCP on TCP port %d"
                                     (file-name-nondirectory (directory-file-name working-dir))
                                     port)))
          (error
           (when port (antigravity-cli-ide-mcp-stop-session working-dir))
           (signal (car err) (cdr err))))))))

;;;###autoload
(defun antigravity-cli-ide ()
  "Run Antigravity CLI in a terminal for the current project."
  (interactive)
  (antigravity-cli-ide--start-session))

;;;###autoload
(defun antigravity-cli-ide-resume ()
  "Resume Antigravity CLI session."
  (interactive)
  (antigravity-cli-ide--start-session nil t))

;;;###autoload
(defun antigravity-cli-ide-continue ()
  "Continue the most recent Antigravity CLI session."
  (interactive)
  (antigravity-cli-ide--start-session t))

;;;###autoload
(defun antigravity-cli-ide-check-status ()
  "Check status of Antigravity CLI."
  (interactive)
  (antigravity-cli-ide--detect-cli)
  (if antigravity-cli-ide--cli-available
      (antigravity-cli-ide-log "Antigravity CLI is available and operational")
    (antigravity-cli-ide-log "Antigravity CLI is not found or not operational")))

;;;###autoload
(defun antigravity-cli-ide-stop ()
  "Stop the Antigravity CLI session."
  (interactive)
  (let* ((working-dir (antigravity-cli-ide--get-working-directory))
         (buffer-name (antigravity-cli-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (progn
          (kill-buffer buffer)
          (antigravity-cli-ide-log "Stopping Antigravity session in %s..." working-dir))
      (antigravity-cli-ide-log "No active session in this directory"))))

;;;###autoload
(defun antigravity-cli-ide-switch-to-buffer ()
  "Switch to the Antigravity CLI buffer."
  (interactive)
  (let ((buffer-name (antigravity-cli-ide--get-buffer-name)))
    (if-let ((buffer (get-buffer buffer-name)))
        (if-let ((window (get-buffer-window buffer)))
            (select-window window)
          (antigravity-cli-ide--display-buffer-in-side-window buffer))
      (user-error "No Antigravity CLI session running. Use M-x antigravity-cli-ide to start"))))

;;;###autoload
(defun antigravity-cli-ide-list-sessions ()
  "List active Antigravity CLI sessions."
  (interactive)
  (antigravity-cli-ide--cleanup-dead-processes)
  (let ((sessions '()))
    (maphash (lambda (directory _)
               (push (cons (abbreviate-file-name directory) directory) sessions))
             antigravity-cli-ide--processes)
    (if sessions
        (let ((choice (completing-read "Switch to Antigravity session: " sessions nil t)))
          (when choice
            (let* ((directory (alist-get choice sessions nil nil #'string=))
                   (buffer-name (funcall antigravity-cli-ide-buffer-name-function directory)))
              (if-let ((buffer (get-buffer buffer-name)))
                  (antigravity-cli-ide--display-buffer-in-side-window buffer)
                (user-error "Buffer for session %s no longer exists" choice)))))
      (antigravity-cli-ide-log "No active Antigravity sessions"))))

;;;###autoload
(defun antigravity-cli-ide-insert-at-mentioned ()
  "Insert the current buffer's file or region as context into the Antigravity prompt.
Sends `@file' (or `@file:start-end' if a region is active) to the terminal
and switches focus to the Antigravity window."
  (interactive)
  (let* ((ref (antigravity-cli-ide--format-context-reference)))
    (unless ref
      (user-error "No file open in the current or companion buffer"))
    (let* ((working-dir (antigravity-cli-ide--get-working-directory))
           (buffer-name (antigravity-cli-ide--get-buffer-name working-dir))
           (term-buffer (get-buffer buffer-name)))
      (unless (and term-buffer (buffer-live-p term-buffer))
        (user-error "No active Antigravity session. Start one with M-x antigravity-cli-ide"))
      ;; Ensure window is displayed
      (let ((window (get-buffer-window term-buffer)))
        (unless window
          (setq window (antigravity-cli-ide--display-buffer-in-side-window term-buffer)))
        (with-current-buffer term-buffer
          (antigravity-cli-ide--terminal-send-string (concat ref " "))
          (setq antigravity-cli-ide--context-inserted-for-turn t))
        (when window (select-window window))
        (antigravity-cli-ide-debug "Inserted context reference: %s" ref)))))

;;;###autoload
(defun antigravity-cli-ide-send-escape ()
  "Send escape key to terminal."
  (interactive)
  (let ((buffer-name (antigravity-cli-ide--get-buffer-name)))
    (if-let* ((buffer (get-buffer buffer-name)))
        (with-current-buffer buffer (antigravity-cli-ide--terminal-send-escape))
      (user-error "No active session"))))

;;;###autoload
(defun antigravity-cli-ide-insert-newline ()
  "Insert newline into prompt."
  (interactive)
  (let ((buffer-name (antigravity-cli-ide--get-buffer-name)))
    (if-let* ((buffer (get-buffer buffer-name)))
        (with-current-buffer buffer
          (antigravity-cli-ide--terminal-send-string "\\")
          (sit-for 0.1)
          (antigravity-cli-ide--terminal-send-return))
      (user-error "No active session"))))

;;;###autoload
(defun antigravity-cli-ide-send-prompt (&optional prompt)
  "Send prompt to terminal.
When `antigravity-cli-ide-auto-prefix-prompt' is non-nil, automatically
pre-fills the prompt input with the active companion file context."
  (interactive)
  (let ((buffer-name (antigravity-cli-ide--get-buffer-name)))
    (if-let* ((buffer (get-buffer buffer-name)))
        (let* ((initial-ref (when antigravity-cli-ide-auto-prefix-prompt
                              (when-let* ((ref (antigravity-cli-ide--format-context-reference)))
                                (concat ref " "))))
               (p (or prompt (read-string "Antigravity prompt: " initial-ref))))
          (unless (string-empty-p p)
            (with-current-buffer buffer
              (antigravity-cli-ide--terminal-send-string p)
              (sit-for 0.1)
              (antigravity-cli-ide--terminal-send-return)
              (setq antigravity-cli-ide--context-inserted-for-turn nil))))
      (user-error "No active session"))))

;;;###autoload
(defun antigravity-cli-ide-toggle ()
  "Toggle Antigravity window visibility."
  (interactive)
  (let* ((working-dir (antigravity-cli-ide--get-working-directory))
         (buffer-name (antigravity-cli-ide--get-buffer-name))
         (buffer (get-buffer buffer-name)))
    (if buffer
        (antigravity-cli-ide--toggle-existing-window buffer working-dir)
      (user-error "No active session"))))

;;;###autoload
(defun antigravity-cli-ide-toggle-recent ()
  "Toggle most recent Antigravity window."
  (interactive)
  (let ((found nil))
    (maphash (lambda (directory _)
               (let* ((buffer-name (funcall antigravity-cli-ide-buffer-name-function directory))
                      (buffer (get-buffer buffer-name)))
                 (when (and buffer (buffer-live-p buffer) (get-buffer-window buffer))
                   (antigravity-cli-ide--toggle-existing-window buffer directory)
                   (setq found t))))
             antigravity-cli-ide--processes)
    (cond
     (found (message "Closed all Antigravity windows"))
     ((and antigravity-cli-ide--last-accessed-buffer (buffer-live-p antigravity-cli-ide--last-accessed-buffer))
      (antigravity-cli-ide--display-buffer-in-side-window antigravity-cli-ide--last-accessed-buffer)
      (message "Opened most recent Antigravity session"))
     (t (user-error "No recent session available")))))

(provide 'antigravity-cli-ide)
;;; antigravity-cli-ide.el ends here
