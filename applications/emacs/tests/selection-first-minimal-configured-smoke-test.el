;;; selection-first-minimal-configured-smoke-test.el --- Configured profile smoke -*- lexical-binding: t; -*-

(require 'ert)

(ert-deftest selection-first-minimal-native-package-closure-is-loaded ()
  (dolist (primitive '(set-window-extra-cursors
                       window-extra-cursors
                       set-window-cursor-type
                       window-cursor-type))
    (should (fboundp primitive)))
  (dolist (library '(corfu lsp-mode lean4-mode meow selection-first))
    (should (locate-library (symbol-name library)))
    (should (require library nil t)))
  (dolist (feature '(init-completion init-languages init-editing init-selection-batch))
    (should (featurep feature)))
  (should selection-first-global-mode)
  (should-not meow-global-mode)
  (should-not selection-batch-enable-meow-bindings)
  (should-not (selection-batch-active-p)))

(ert-deftest selection-first-minimal-real-command-loop-typing-episode-is-one-undo-unit ()
  (with-temp-buffer
    (fundamental-mode)
    (buffer-enable-undo)
    (insert "a b")
    (undo-boundary)
    (selection-first-mode 1)
    (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (execute-kbd-macro (kbd "i X RET Y <escape>")))
    (should (equal (buffer-string) "X\nYa X\nYb"))
    (should (eq selection-first--state 'normal))
    (should (= 2 (selection-batch-count)))
    ;; Each command-loop intent is exactly one undo boundary: Y, newline, X.
    (selection-first-undo)
    (should (equal (buffer-string) "X\na X\nb"))
    (should (= 0 (selection-batch-count)))
    (should-not (selection-batch-active-p))
    (let ((last-command 'undo))
      (selection-first-undo))
    (should (equal (buffer-string) "Xa Xb"))
    (should (= 0 (selection-batch-count)))
    (let ((last-command 'undo))
      (selection-first-undo))
    (should (equal (buffer-string) "a b"))
    (should (eq selection-first--state 'normal))
    (should (= 0 (selection-batch-count)))
    (should-not (selection-batch-active-p))))

;;; selection-first-minimal-configured-smoke-test.el ends here
