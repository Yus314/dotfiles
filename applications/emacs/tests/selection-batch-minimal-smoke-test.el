;;; selection-batch-minimal-smoke-test.el --- Standalone package smoke -*- lexical-binding: t; -*-

(require 'ert)
(require 'selection-first)

(ert-deftest selection-batch-org-deferred-unload-does-not-break-later-org-load ()
  (should-not (featurep 'org-indent))
  (should (memq #'selection-batch-org--after-load after-load-functions))
  (unload-feature 'selection-batch-org t)
  (should-not (memq #'selection-batch-org--after-load after-load-functions))
  (should (require 'org-indent nil t))
  (should (featurep 'org-indent))
  (should (require 'selection-batch-org nil t))
  (should (advice-member-p #'selection-batch-org--refresh-around
                           'org-indent-refresh-maybe)))

(ert-deftest selection-first-standalone-load-is-passive ()
  (should (featurep 'selection-batch))
  (should (featurep 'selection-first))
  (should-not selection-first-global-mode)
  (should-not (featurep 'selection-batch-meow))
  (should (eq (lookup-key selection-first-normal-map (kbd "d"))
              #'selection-first-backward-char))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC a"))
              #'selection-first-gather-same-all))
  (should-not (selection-batch-active-p)))

(ert-deftest selection-batch-standalone-gather-replace-undo ()
  (with-temp-buffer
    (fundamental-mode)
    (buffer-enable-undo)
    (insert "日本 aa 日本")
    (goto-char 3)
    (set-mark 1)
    (setq mark-active t)
    (activate-mark)
    (selection-first-mode 1)
    (selection-first-gather-same-all)
    (should (= 2 (selection-batch-count)))
    (selection-first-replace "和")
    (should (equal (buffer-string) "和 aa 和"))
    (selection-first-undo)
    (should (equal (buffer-string) "日本 aa 日本"))
    (should-not (selection-batch-active-p))))

;;; selection-batch-minimal-smoke-test.el ends here
