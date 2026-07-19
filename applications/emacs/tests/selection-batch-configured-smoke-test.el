;;; selection-batch-configured-smoke-test.el --- Nix configuration smoke -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'selection-first)

(defmacro selection-batch-configured--with-selection (mode text ranges &rest body)
  "Run BODY in MODE with TEXT and configured selection-first RANGES."
  (declare (indent 3) (debug t))
  `(with-temp-buffer
     (funcall ,mode)
     (buffer-enable-undo)
     (insert ,text)
     (setq buffer-undo-list nil)
     (goto-char (point-min))
     (when (bound-and-true-p meow-mode)
       (meow-mode -1))
     (selection-first-mode 1)
     (unwind-protect
         (progn
           (selection-first-install-ranges ,ranges (caar ,ranges))
           ,@body)
       (selection-first-mode -1)
       (when selection-batch--session
         (selection-batch--cleanup selection-batch--session nil t)))))

(defun selection-batch-configured--keys (keys)
  "Execute KEYS through the active configured command-loop keymaps."
  (save-window-excursion
    (switch-to-buffer (current-buffer))
    (execute-kbd-macro (kbd keys))))

(defun selection-batch-configured--assert-normal (count)
  "Assert configured normal state with selection COUNT."
  (should (eq selection-first--state 'normal))
  (should (= count (selection-batch-count)))
  (should-not selection-first--batch-insert-active))

(defun selection-batch-configured--assert-clean (text)
  "Assert TEXT is restored and all configured ownership has ended."
  (should (equal text (buffer-string)))
  (should (eq selection-first--state 'normal))
  (should (= 0 (selection-batch-count)))
  (should-not selection-first--batch-insert-active)
  (should-not (selection-batch-active-p))
  (should-not selection-batch--session))

(ert-deftest selection-batch-configured-artifacts-and-meow-are-present ()
  (should (locate-library "selection-batch"))
  (should (locate-library "meow"))
  (should (locate-library "puni"))
  (should (featurep 'init-editing))
  (should (require 'init-selection-batch nil t))
  (should-not selection-batch-enable-meow-bindings)
  (should-not (lookup-key meow-normal-state-keymap (kbd "g")))
  (should-not (selection-batch-active-p)))

(ert-deftest selection-batch-configured-gather-replace-undo ()
  (with-temp-buffer
    (fundamental-mode)
    (buffer-enable-undo)
    (insert "aa bb aa")
    (goto-char 3)
    (set-mark 1)
    (setq mark-active t)
    (activate-mark)
    (selection-batch-gather-same-all)
    (should (= 2 (selection-batch-count)))
    (selection-batch-replace "X")
    (should (equal (buffer-string) "X bb X"))
    (should (eq (command-remapping 'undo nil selection-batch--transaction-map)
                #'selection-batch-undo))
    (call-interactively
     (command-remapping 'undo nil selection-batch--transaction-map))
    (should (equal (buffer-string) "aa bb aa"))
    (should-not (selection-batch-active-p))))

(ert-deftest selection-batch-configured-forward-insert-at-cursor-endpoints ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "aa aa" '((a 1 3) (b 4 6))
    (selection-batch-configured--keys "i X <escape>")
    (should (equal "aaX aaX" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "aa aa")))

(ert-deftest selection-batch-configured-forward-append-at-anchor-endpoints ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "aa aa" '((a 1 3) (b 4 6))
    (selection-batch-configured--keys "a X <escape>")
    (should (equal "Xaa Xaa" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "aa aa")))

(ert-deftest selection-batch-configured-mixed-direction-insert-at-cursors ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "aa bb" '((forward 1 3) (reverse 6 4))
    (selection-batch-configured--keys "i X <escape>")
    (should (equal "aaX Xbb" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "aa bb")))

(ert-deftest selection-batch-configured-fixed-replacement-command-loop ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "one two" '((one 1 4) (two 5 8))
    (selection-batch-configured--keys "r X RET")
    (should (equal "X X" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (call-interactively #'selection-first-undo)
    (selection-batch-configured--assert-clean "one two")))

(ert-deftest selection-batch-configured-rejects-during-batch-insert-and-continues ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "aa aa" '((a 1 3) (b 4 6))
    (selection-batch-configured--keys "i X")
    (should-error (selection-batch-configured--keys "C-k") :type 'user-error)
    (should (equal "aaX aaX" (buffer-string)))
    (should (eq selection-first--state 'batch-insert))
    (should (= 2 (selection-batch-count)))
    (should selection-first--batch-insert-active)
    (selection-batch-configured--keys "Y <escape>")
    (should (equal "aaXY aaXY" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "aaX aaX")
    (let ((last-command 'undo))
      (selection-batch-configured--keys "u"))
    (selection-batch-configured--assert-clean "aa aa")))

(ert-deftest selection-batch-configured-batch-insert-undoes-each-intent ()
  (selection-batch-configured--with-selection
      #'fundamental-mode "aa aa" '((a 1 3) (b 4 6))
    (selection-batch-configured--keys "a X RET Y DEL Z <escape>")
    (should (equal "X\nZaa X\nZaa" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "X\naa X\naa")
    (dolist (expected '("X\nYaa X\nYaa"
                        "X\naa X\naa"
                        "Xaa Xaa"
                        "aa aa"))
      (let ((last-command 'undo))
        (selection-batch-configured--keys "u"))
      (selection-batch-configured--assert-clean expected))))

(ert-deftest selection-batch-configured-org-anchor-insert-command-loop ()
  (selection-batch-configured--with-selection
      #'org-mode "* A\nitem\n* B\nitem\n" '((a 5 9) (b 14 18))
    (selection-batch-configured--keys "a X <escape>")
    (should (equal "* A\nXitem\n* B\nXitem\n" (buffer-string)))
    (selection-batch-configured--assert-normal 2)
    (selection-batch-configured--keys "u")
    (selection-batch-configured--assert-clean "* A\nitem\n* B\nitem\n")))

;;; selection-batch-configured-smoke-test.el ends here
