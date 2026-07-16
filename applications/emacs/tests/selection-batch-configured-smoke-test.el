;;; selection-batch-configured-smoke-test.el --- Nix configuration smoke -*- lexical-binding: t; -*-

(require 'ert)

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

;;; selection-batch-configured-smoke-test.el ends here
