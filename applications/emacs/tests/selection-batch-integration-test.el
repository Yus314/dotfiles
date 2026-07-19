;;; selection-batch-integration-test.el --- Frontend integration tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch)
(require 'selection-batch-meow)

(defvar meow-normal-state-keymap)

(defconst selection-batch-test--repository-root
  (expand-file-name ".." (file-name-directory load-file-name)))

(defun selection-batch-test--region (anchor cursor)
  (goto-char cursor)
  (set-mark anchor)
  (setq mark-active t)
  (activate-mark))

(defun selection-batch-test--binding (key)
  (lookup-key selection-batch-meow-prefix-map (kbd key)))

(ert-deftest selection-batch-public-query-wrappers-are-total ()
  (when selection-batch--session
    (selection-batch--cleanup selection-batch--session nil t))
  (should-not (selection-batch-active-p))
  (should (= 0 (selection-batch-count)))
  (should-not (selection-batch-current))
  (should-not (selection-batch-collapse))
  (should-not (selection-batch-cancel)))

(ert-deftest selection-batch-minimal-example-loads-without-startup-state ()
  (let ((example (expand-file-name "examples/minimal-init.el"
                                   selection-batch-test--repository-root)))
    (unwind-protect
        (progn
          (selection-first-global-mode -1)
          (load example nil nil t)
          (should (featurep 'selection-first))
          (should selection-first-global-mode)
          (should-not (selection-batch-active-p)))
      (selection-first-global-mode -1))))

(ert-deftest selection-batch-meow-grammar-is-semantic-and-complete ()
  (dolist (entry '(("n" . selection-batch-gather-same-next)
                   ("p" . selection-batch-gather-same-previous)
                   ("a" . selection-batch-gather-same-all)
                   ("r" . selection-batch-gather-regexp)
                   ("l" . selection-batch-split-lines)
                   ("k" . selection-batch-keep)
                   ("d" . selection-batch-drop)
                   ("m" . selection-batch-merge)
                   ("]" . selection-batch-rotate-primary-next)
                   ("[" . selection-batch-rotate-primary-previous)
                   ("u" . selection-batch-selection-undo)
                   ("U" . selection-batch-selection-redo)
                   ("y" . selection-batch-copy)
                   ("x" . selection-batch-delete)
                   ("c" . selection-batch-replace)
                   ("+" . selection-batch-uppercase)
                   ("-" . selection-batch-lowercase)
                   ("~" . selection-batch-capitalize)
                   ("b" . selection-batch-insert-before)
                   ("i" . selection-batch-insert-after)
                   ("P" . selection-batch-paste)
                   ("." . selection-batch-repeat)
                   ("q" . selection-batch-collapse)
                   ("C-g" . selection-batch-cancel)))
    (should (eq (selection-batch-test--binding (car entry)) (cdr entry)))
    (should (eq (lookup-key selection-batch--transaction-map (kbd (car entry)))
                (cdr entry))))
  (map-keymap (lambda (_event command)
                (should-not (and (symbolp command)
                                 (string-prefix-p "mc/" (symbol-name command)))))
              selection-batch-meow-prefix-map))

(ert-deftest selection-batch-meow-prefix-install-is-opt-in-and-conflict-safe ()
  (let ((meow-normal-state-keymap (make-sparse-keymap))
        (selection-batch-enable-meow-bindings nil))
    (selection-batch-meow-initialize)
    (should-not (lookup-key meow-normal-state-keymap (kbd "g")))
    (let ((selection-batch-enable-meow-bindings t))
      (selection-batch-meow-initialize)
      (should (eq (lookup-key meow-normal-state-keymap (kbd "g"))
                  selection-batch-meow-prefix-map)))
    (let ((meow-normal-state-keymap (make-sparse-keymap))
          (selection-batch-enable-meow-bindings t))
      (define-key meow-normal-state-keymap (kbd "g") #'ignore)
      (should-error (selection-batch-meow-initialize) :type 'user-error)
      (should (eq (lookup-key meow-normal-state-keymap (kbd "g")) #'ignore)))))

(ert-deftest selection-batch-single-meow-region-stays-standard-until-promotion ()
  (with-temp-buffer
    (insert "one two")
    (selection-batch-test--region 1 4)
    (selection-batch-gather-same-all)
    (should-not (selection-batch-active-p))
    (should mark-active)
    (should (= (region-beginning) 1))
    (should (= (region-end) 4))))

(ert-deftest selection-batch-line-gather-stays-standard-or-promotes-by-count ()
  (with-temp-buffer
    (insert "one")
    (selection-batch-test--region 1 4)
    (selection-batch-split-lines)
    (should-not (selection-batch-active-p))
    (should (equal (cons (region-beginning) (region-end)) '(1 . 4))))
  (with-temp-buffer
    (insert "one\ntwo")
    (selection-batch-test--region 1 (point-max))
    (unwind-protect
        (progn
          (selection-batch-split-lines)
          (should (selection-batch-active-p))
          (should (= 2 (selection-batch-count))))
      (when selection-batch--session
        (selection-batch-cancel)))))

(ert-deftest selection-batch-two-matches-promote-to-transaction ()
  (with-temp-buffer
    (insert "one two one")
    (selection-batch-test--region 1 4)
    (unwind-protect
        (progn
          (selection-batch-gather-same-all)
          (should (selection-batch-active-p))
          (should (= 2 (selection-batch-count)))
          (should (functionp
                   (selection-batch--session-transient-exit-function
                    selection-batch--session))))
      (when selection-batch--session
        (selection-batch-cancel)))))

(ert-deftest selection-batch-denies-special-and-read-only-buffers ()
  (dolist (setup (list (lambda () (special-mode))
                       (lambda () (setq buffer-read-only t))))
    (with-temp-buffer
      (insert "aa aa")
      (selection-batch-test--region 1 3)
      (funcall setup)
      (should-error (selection-batch-gather-same-all) :type 'user-error)
      (should-not (selection-batch-active-p)))))

(ert-deftest selection-batch-export-and-collapse-handoff-is-single-call ()
  (unwind-protect
      (with-temp-buffer
        (insert "aa bb aa")
        (selection-batch-test--region 1 3)
        (selection-batch-gather-same-all)
        (let ((ranges (selection-batch-export-ranges))
              (calls 0))
          (should (= 2 (length ranges)))
          (should (equal (mapcar (lambda (range)
                                   (cons (plist-get range :beginning)
                                         (plist-get range :end)))
                                 ranges)
                         '((1 . 3) (7 . 9))))
          (selection-batch-collapse-and-call
           (lambda () (interactive) (setq calls (1+ calls))))
          (should (= calls 1))
          (should-not (selection-batch-active-p))
          (should mark-active)))
    (when selection-batch--session
      (with-current-buffer (selection-batch--session-buffer selection-batch--session)
        (selection-batch-cancel)))))

(ert-deftest selection-batch-handoff-failure-leaves-primary-region ()
  (with-temp-buffer
    (insert "aa aa")
    (selection-batch-test--region 1 3)
    (selection-batch-gather-same-all)
    (should-error
     (selection-batch-collapse-and-call
      (lambda () (interactive) (error "backend failed"))))
    (should-not (selection-batch-active-p))
    (should mark-active)
    (should (equal (cons (region-beginning) (region-end)) '(1 . 3)))))

(provide 'selection-batch-integration-test)
;;; selection-batch-integration-test.el ends here
