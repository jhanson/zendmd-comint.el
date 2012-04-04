;;; zendmd-comint.el --- Run zendmd as an inferior process for Zenoss development

;;; Copyright (C) 2010 Joseph Hanson

;;; Author: Joseph Hanson <jhanson@zenoss.com>
;;; Maintainer: Joseph Hanson <jhanson@zenoss.com>>
;;; Created: 12/12/10
;;; Version: 0.0.2
;;; Package-Requires: (comint)
;;; Keywords: python


;; zendmd-comint.el is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or
;; {at your option} any later version.

;; zendmd-comint.el is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING, or type `C-h C-c'. If
;; not, write to the Free Software Foundation at this address:

;;   Free Software Foundation
;;   51 Franklin Street, Fifth Floor
;;   Boston, MA 02110-1301
;;   USA

;;; Commentary:
;;; zendmd-comint lets you run the zendmd process as an inferior python process
;;; and send your python code directly to it. It also allows you to execute
;;; the current script as a zendmd script and see the output.
;;; The zendmd-minor-mode will replace your "send to python" commands in python with
;;; suitable "send to zendmd" commands.

;;  Usage:
;;  1. Put zendmd-comint.el in your load path
;;  2. Add (require 'zendmd-comint) to your .emacs
;;  3. Set inferior-zendmd-program-command to the execution command for running your zendmd
;;  (setq inferior-zendmd-program-command "/path/to/executable <args>")
;;  Do: M-x inferior-zendmd-start-process
;;  Away you go.

;;  To use the minor mode add a hook in your python mode like the following:
;;   (add-hook 'python-mode-hook '(lambda ()
;;                               (zendmd-minor-mode 1)))
;;; TODO:
;;  Update load file to keep keep context into account
;;; History:
;;  0.0.2 - Updated send region to take into account the current global and local scope so dmd
;;          can be used inside of a sent region
;;; Code:

(require 'comint)
(require 'python)

(defcustom inferior-zendmd-program-command "zendmd" "command used to invoke zendmd, the default assumes it is on your path"
  :group 'inferior-zendmd)

(defgroup inferior-zendmd nil
  "Run a zendmd process in a buffer."
  :group 'inferior-zendmd)

(defcustom inferior-zendmd-mode-hook nil
  "*Hook for customizing inferior-zendmd mode."
  :type 'hook
  :group 'inferior-zendmd)

(autoload 'ansi-color-for-comint-mode-on "ansi-color" nil t)
(add-hook 'comint-mode-hook 'ansi-color-for-comint-mode-on)
(defvar inferior-zendmd-buffer "*zendmd*")

(defun inferior-zendmd-start-process (cmd &optional dont-switch-p)
  "Run an inferior zendmd process, input and output via buffer `*zendmd*'.
If there is a process already running in `*zendmd*', switch to that buffer.
With argument, allows you to edit the command line (default is value
of `inferior-zendmd-program-command').
Runs the hook `inferior-zendmd-mode-hook' \(after the `comint-mode-hook'
is run).
\(Type \\[describe-mode] in the process buffer for a list of commands.)"

  (interactive (list
                (if current-prefix-arg
                    (read-string "Run zendmd: " inferior-zendmd-program-command)
                  inferior-zendmd-program-command)))

    (if (not (comint-check-proc "*zendmd*"))
        (save-excursion
          (let ((cmdlist (split-string cmd)))
            (set-buffer (apply 'make-comint "zendmd" (car cmdlist)
                               nil (cdr cmdlist)))
            (inferior-zendmd-mode))
          (setq inferior-zendmd-program-command cmd)
          (setq inferior-zendmd-buffer "*zendmd*")
          (accept-process-output (get-buffer-process inferior-zendmd-buffer) 5)
          (zendmd-send-string "import sys")
          (zendmd-send-string (concat "sys.path.append('" data-directory "')"))
          ;; send append to system path cmdpath
          (zendmd-send-string "import emacs")
          (if (not dont-switch-p)
              (pop-to-buffer "*zendmd*"))
          (run-hooks 'inferior-zendmd-hook))))

(defun zendmd-send-string (string)
  "Evaluate STRING in inferior Python process."
  (interactive "sPython command: ")
  (comint-send-string (zendmd-proc) string)
  (unless (string-match "\n\\'" string)
    ;; Make sure the text is properly LF-terminated.
    (comint-send-string (zendmd-proc) "\n"))
  (when (string-match "\n[ \t].*\n?\\'" string)
    ;; If the string contains a final indented line, add a second newline so
    ;; as to make sure we terminate the multiline instruction.
    (comint-send-string (zendmd-proc) "\n")))

(defun zendmd-send-command (command)
  "Like `zendmd-send-string' but resets `compilation-shell-minor-mode'."
  (when (zendmd-check-comint-prompt)
    (with-current-buffer (get-buffer inferior-zendmd-buffer)
      (goto-char (point-max))
      (compilation-forget-errors)
      (zendmd-send-string command)
      (setq compilation-last-buffer (current-buffer)))))

(defun zendmd-proc ()
  "Return the current zendmd process.
See variable `inferior-zendmd-buffer'.  Starts a new process if necessary."
  (unless (comint-check-proc inferior-zendmd-buffer)
    (inferior-zendmd-start-process inferior-zendmd-program-command t))
  (get-buffer-process (if (derived-mode-p 'inferior-zendmd-mode)
              (current-buffer)
            inferior-zendmd-buffer)))

(defun zendmd-send-region (start end)
  "Send the current region to the inferior zendmd process. Because we are sending
python and whitespace is important we create a temporary file and send that to the intpreter
see `python-send-region' from which this was largely copied from."
  (interactive "r")
  (inferior-zendmd-start-process inferior-zendmd-program-command t)
  (let* ((f (make-temp-file "py"))
         ;; use regular execfile instead of emacs defined eexecfile
         ;; since we can pass in globals and locals
         (command (format "execfile(%S, globals(), locals())" f))
         ;;(command (format "emacs.eexecfile(%S)" f))

         (orig-start (copy-marker start)))
    (when (save-excursion
            (goto-char start)
            (/= 0 (current-indentation))) ; need dummy block
      (save-excursion
        (goto-char orig-start)
        ;; Wrong if we had indented code at buffer start.
        (set-marker orig-start (line-beginning-position 0)))
      (write-region "if True:\n" nil f nil 'nomsg))
    (write-region start end f t 'nomsg)
    (zendmd-send-command command)
    (with-current-buffer (process-buffer (zendmd-proc))
      ;; Tell compile.el to redirect error locations in file `f' to
      ;; positions past marker `orig-start'.  It has to be done *after*
      ;; `zendmd-send-command''s call to `compilation-forget-errors'.
      (compilation-fake-loc orig-start f))))

(defun zendmd-check-comint-prompt (&optional proc)
  "Return non-nil if and only if there's a normal prompt in the inferior buffer.
If there isn't, it's probably not appropriate to send input to return Eldoc
information etc.  If PROC is non-nil, check the buffer for that process."
  (with-current-buffer (process-buffer (or proc (zendmd-proc)))
    (save-excursion
      (save-match-data (re-search-backward "In" nil t)))))

(defun zendmd-send-region-and-go (start end)
  "Send the current region to the inferior Zendmd process."
  (interactive "r")
  (inferior-zendmd-start-process inferior-zendmd-program-command t)
  (zendmd-send-region start end)
  (comint-send-string inferior-zendmd-buffer "\n")
  (switch-to-zendmd))

(defun zendmd-send-last-sexp-and-go ()
  "Send the previous sexp to the inferior zendmd process."
  (interactive)
  (zendmd-send-region-and-go (save-excursion (backward-sexp) (point)) (point)))

(defun zendmd-send-last-sexp ()
  "Send the previous sexp to the inferior zendmd process."
  (interactive)
  (zendmd-send-region (save-excursion (backward-sexp) (point)) (point)))

(defun zendmd-send-buffer ()
  "Send the buffer to the inferior zendmd process."
  (interactive)
  (zendmd-send-region (point-min) (point-max)))

(defun zendmd-send-buffer-and-go ()
  "Send the buffer to the inferior zendmd process."
  (interactive)
  (zendmd-send-region-and-go (point-min) (point-max)))

(defvar zendmd-prev-dir/file nil
  "Caches (directory . file) pair used in the last `zendmd-load-file' command.
Used for determining the default in the next one.")

(defun zendmd-load-file (file-name)
  "Load a Python file FILE-NAME into the inferior zendmd process.
If the file has extension `.py' import or reload it as a module.
Treating it as a module keeps the global namespace clean, provides
function location information for debugging, and supports users of
module-qualified names."
  (interactive (comint-get-source "Load Python file: " zendmd-prev-dir/file
                  python-source-modes
                  t))   ; because execfile needs exact name
  (comint-check-source file-name)     ; Check to see if buffer needs saving.
  (setq zendmd-prev-dir/file (cons (file-name-directory file-name)
                   (file-name-nondirectory file-name)))
  (zendmd-send-command
   (if (string-match "\\.py\\'" file-name)
       (let ((module (file-name-sans-extension
                      (file-name-nondirectory file-name))))
         (format "emacs.eimport(%S,%S)"
                 module (file-name-directory file-name)))
     (format "execfile(%S)" file-name)))
  (message "%s loaded" file-name))

(defun zendmd-execute-current-script ()
  "Runs the current script through the zendmd --script"
  (interactive)
  (if (buffer-file-name (current-buffer))
      (let ((cmd (concat
                  inferior-zendmd-program-command
                  " --script "
                  (buffer-file-name (current-buffer)) " &"))
            (buff-name "*ZENDMD-OUTPUT*"))
        (if (get-buffer buff-name)
            (kill-buffer buff-name))
        (shell-command cmd buff-name))))

(defun switch-to-zendmd ()
  "Switch to the zendmd process buffer."
  (interactive)
  (if (or (and inferior-zendmd-buffer (get-buffer inferior-zendmd-buffer))
          (inferior-zendmd-start-process inferior-zendmd-program-command))
      (if (get-buffer inferior-zendmd-buffer)
          (pop-to-buffer inferior-zendmd-buffer)
        (push-mark)
        (goto-char (point-max)))))

(defvar inferior-zendmd-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m "\C-x\C-e" 'zendmd-send-last-sexp)
    (define-key m "\C-cl" 'zendmd-load-file)
    m))


(define-derived-mode inferior-zendmd-mode comint-mode "zendmd"
  "Major mode for interacting with an inferior zendmd process.

The following commands are available:
\\{inferior-zendmd-mode-map}

A zendmd process can be fired up with M-x inferior-zendmd-start-process.

Customization: Entry to this mode runs the hooks on comint-mode-hook and
inferior-zendmd-mode-hook (in that order).

You can send text to the inferior zendmd process from othber buffers containing
zendmd source.
    switch-to-zendmd switches the current buffer to the zendmd process buffer.
    zendmd-send-region sends the current region to the zendmd process.


"
  ;; piggy back on python keywords if it is loaded
  (if (boundp 'python-font-lock-keywords)
      (progn
        (set (make-local-variable 'font-lock-defaults)
       '(python-font-lock-keywords nil nil nil nil
         ))))
  (set (make-local-variable 'parse-sexp-lookup-properties) t)
  (set (make-local-variable 'parse-sexp-ignore-comments) t)
  (set (make-local-variable 'comment-start) "# ")

  (use-local-map inferior-zendmd-mode-map))

(provide 'zendmd-comint)

;;
(defvar zendmd-minor-mode-map
  (let ((map (make-sparse-keymap)))
    ;; Mostly taken from python-mode.el.
    (define-key map "\C-c\C-s" 'zendmd-send-string)
    (define-key map [?\C-\M-x] 'zendmd-send-defun)
    (define-key map "\C-c\C-r" 'zendmd-send-region)
    (define-key map "\C-c\M-r" 'zendmd-send-region-and-go)
    (define-key map "\C-c\C-c" 'zendmd-send-buffer)
    (define-key map "\C-c\C-z" 'switch-to-zendmd)
    (define-key map "\C-c\C-m" 'zendmd-execute-current-script)
    (define-key map "\C-c\C-l" 'zendmd-load-file)
    map))

(define-minor-mode zendmd-minor-mode
  "Zendmd is a minor mode that replaces sending the
python functions from a python process to the zendmd process.

\\{zendmd-minor-mode-map}"
  nil
  " dmd"
  :keymap zendmd-minor-mode-map
  :group 'zendmd)


