;;; selection-first-test.el --- Meow-independent frontend tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-first)
(require 'org)
(require 'org-indent)

(defmacro selection-first-test--with-buffer (text &rest body)
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (buffer-enable-undo)
     (insert ,text)
     (undo-boundary)
     (goto-char (point-min))
     (selection-first-mode 1)
     (unwind-protect (progn ,@body)
       (selection-first-mode -1)
       (when selection-batch--session
         (selection-batch--cleanup selection-batch--session nil t)))))

(defun selection-first-test--select (anchor cursor)
  (goto-char cursor)
  (set-mark anchor)
  (setq mark-active t)
  (activate-mark))

(defun selection-first-test--triples ()
  (mapcar
   (lambda (selection)
     (list (selection-batch-snapshot-selection-id selection)
           (selection-batch-snapshot-selection-anchor selection)
           (selection-batch-snapshot-selection-cursor selection)))
   (append (selection-batch-snapshot-selections
            (selection-first-current-snapshot)) nil)))

(defmacro selection-first-test--with-org-indent-buffer (text &rest body)
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,text)
     (org-mode)
     (org-indent-mode 1)
     (buffer-enable-undo)
     (setq buffer-undo-list nil)
     (goto-char (point-min))
     (selection-first-mode 1)
     (unwind-protect (progn ,@body)
       (selection-first-mode -1)
       (when selection-batch--session
         (selection-batch--cleanup selection-batch--session nil t))
       (org-indent-mode -1))))

(defun selection-first-test--org-indent-signature ()
  "Return line-prefix and wrap-prefix values throughout the buffer."
  (let (result)
    (dotimes (offset (buffer-size) (nreverse result))
      (let ((position (1+ offset)))
        (push (list (get-text-property position 'line-prefix)
                    (get-text-property position 'wrap-prefix))
              result)))))

(defvar selection-first-test--native-observation nil)

(defvar selection-first-test--switch-destination nil)

(defvar selection-first-test--unowned-command-calls 0)

(defvar selection-first-test--org-outer-advice-calls 0)

(defun selection-first-test--org-suppressing-outer-advice (_function &rest _arguments)
  "Suppress Org's refresh to test fail-closed advice-chain validation."
  (cl-incf selection-first-test--org-outer-advice-calls)
  'suppressed)

(defun selection-first-test--unowned-command ()
  "Record an unsupported command-loop dispatch and mutate at point."
  (interactive)
  (cl-incf selection-first-test--unowned-command-calls)
  (insert "UNOWNED"))

(defun selection-first-test--native-edit-and-switch ()
  "Edit the source buffer and switch to the configured test destination."
  (interactive)
  (insert "X")
  (switch-to-buffer selection-first-test--switch-destination))

(defun selection-first-test--native-prompt-and-edit (text)
  "Read TEXT recursively and insert it in the source buffer."
  (interactive "sNative text: ")
  (insert text))

(defun selection-first-test--native-edit-and-error ()
  "Edit the source buffer and signal an error."
  (interactive)
  (insert "E")
  (error "native test error"))

(defun selection-first-test--native-edit-and-quit ()
  "Edit the source buffer and signal quit."
  (interactive)
  (insert "Q")
  (signal 'quit nil))

(defun selection-first-test--disabled-native-command ()
  "Record an execution that disabled-command handling should prevent."
  (interactive)
  (setq selection-first-test--native-observation 'executed))

(defun selection-first-test--native-prefix-target (argument)
  "Record native prefix dispatch state with numeric prefix ARGUMENT."
  (interactive "p")
  (setq selection-first-test--native-observation
        (list :argument argument
              :state selection-first--state
              :this this-command
              :real real-this-command
              :keys (this-command-keys-vector)
              :region (and mark-active
                           (cons (region-beginning) (region-end))))))

(ert-deftest selection-first-singleton-and-plural-share-snapshot-boundary ()
  (selection-first-test--with-buffer "aa bb aa"
    (selection-first-test--select 1 3)
    (should (equal '((0 1 3)) (selection-first-test--triples)))
    (selection-first-gather-same-all)
    (should (selection-batch-active-p))
    (should (equal '((0 1 3) (1 7 9))
                   (selection-first-test--triples)))))

(ert-deftest selection-first-plural-to-single-transform-demotes-to-native-region ()
  (selection-first-test--with-buffer "abcdef"
    (selection-first-install-ranges '((a 3 1) (b 4 6)) 'a)
    (should (selection-batch-active-p))
    (selection-first--apply-transform
     (lambda (snapshot)
       (let ((first (aref (selection-batch-snapshot-selections snapshot) 0)))
         (selection-batch-snapshot-with-selections
          snapshot (vector first)
          (selection-batch-snapshot-selection-id first)))))
    (should-not (selection-batch-active-p))
    (should (= (point) 1))
    (should (= (mark) 3))
    (should mark-active)
    (should (equal '((0 3 1)) (selection-first-test--triples)))))

(ert-deftest selection-first-install-rejects-stale-live-generation ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (let ((stale (selection-first-current-snapshot)))
      (selection-first-reverse)
      (let ((current (selection-first-current-snapshot)))
        (should-error (selection-first-install-snapshot stale) :type 'user-error)
        (should (equal current (selection-first-current-snapshot)))))))

(ert-deftest selection-first-incremental-gather-adds-and-promotes-primary ()
  (selection-first-test--with-buffer "aa x aa y aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-next)
    (should (selection-batch-active-p))
    (should (equal '((0 1 3) ("occurrence-0" 6 8))
                   (selection-first-test--triples)))
    (should (equal "occurrence-0"
                   (selection-batch-snapshot-primary-id
                    (selection-first-current-snapshot))))
    (selection-first-gather-same-next)
    (should (equal '((0 1 3)
                     ("occurrence-0" 6 8)
                     ("occurrence-1" 11 13))
                   (selection-first-test--triples)))
    (should (equal "occurrence-1"
                   (selection-batch-snapshot-primary-id
                    (selection-first-current-snapshot))))))

(ert-deftest selection-first-incremental-gather-failure-is-atomic ()
  (selection-first-test--with-buffer "aa x aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-next)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-gather-same-next) :type 'user-error)
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-incremental-gather-previous-promotes-singleton ()
  (selection-first-test--with-buffer "aa x aa"
    (selection-first-test--select 6 8)
    (selection-first-gather-same-previous)
    (should (equal '(("occurrence-0" 1 3) (0 6 8))
                   (selection-first-test--triples)))
    (should (equal "occurrence-0"
                   (selection-batch-snapshot-primary-id
                    (selection-first-current-snapshot))))))

(ert-deftest selection-first-selection-history-roundtrips-across-cardinality ()
  (selection-first-test--with-buffer "aa x aa y aa"
    (let ((text (buffer-string)))
      (selection-first-test--select 1 3)
      (selection-first-gather-same-next)
      (should (selection-batch-active-p))
      (selection-first-selection-undo)
      (should-not (selection-batch-active-p))
      (should (equal '((0 1 3)) (selection-first-test--triples)))
      (selection-first-selection-redo)
      (should (equal '((0 1 3) ("occurrence-0" 6 8))
                     (selection-first-test--triples)))
      (selection-first-gather-same-next)
      (let* ((three (selection-first-current-snapshot))
             (three-triples (selection-first-test--triples))
             (three-primary (selection-batch-snapshot-primary-id three)))
        (selection-first-selection-undo)
        (let ((undo-generation
               (selection-batch-snapshot-generation
                (selection-first-current-snapshot))))
          (should (> undo-generation
                     (selection-batch-snapshot-generation three)))
          (should (equal '((0 1 3) ("occurrence-0" 6 8))
                         (selection-first-test--triples)))
          (selection-first-selection-redo)
          (let ((redone (selection-first-current-snapshot)))
            (should (equal three-triples (selection-first-test--triples)))
            (should (equal three-primary
                           (selection-batch-snapshot-primary-id redone)))
            (should (> (selection-batch-snapshot-generation redone)
                       undo-generation))))
        (should (equal text (buffer-string)))))))

(ert-deftest selection-first-selection-history-failure-is-atomic ()
  (selection-first-test--with-buffer "aa x aa"
    (selection-first-test--select 1 3)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-selection-undo) :type 'user-error)
      (should-error (selection-first-selection-redo) :type 'user-error)
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-new-transform-after-undo-clears-redo ()
  (selection-first-test--with-buffer "aa x aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-next)
    (selection-first-selection-undo)
    (should selection-first--selection-redo)
    (selection-first-reverse)
    (should-not selection-first--selection-redo)
    (should-error (selection-first-selection-redo) :type 'user-error)))

(ert-deftest selection-first-failed-plan-preserves-frontend-history ()
  (selection-first-test--with-buffer "aa x aa y aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-next)
    (selection-first-gather-same-next)
    (selection-first-selection-undo)
    (let ((before (selection-first-current-snapshot))
          (history (copy-sequence selection-first--selection-history))
          (redo (copy-sequence selection-first--selection-redo)))
      (should-error (selection-first-replace 3) :type 'wrong-type-argument)
      (should (equal before (selection-first-current-snapshot)))
      (should (equal history selection-first--selection-history))
      (should (equal redo selection-first--selection-redo)))))

(ert-deftest selection-first-successful-noop-text-plan-clears-history ()
  (selection-first-test--with-buffer "abcd"
    (selection-first-install-ranges '((a 1 2) (b 3 4)) 'a)
    (selection-first--apply-transform
     (lambda (snapshot)
       (selection-batch-snapshot-with-selections
        snapshot
        (vconcat
         (mapcar
          (lambda (selection)
            (selection-batch-snapshot-selection-create
             :id (selection-batch-snapshot-selection-id selection)
             :anchor (min (selection-batch-snapshot-selection-anchor selection)
                          (selection-batch-snapshot-selection-cursor selection))
             :cursor (min (selection-batch-snapshot-selection-anchor selection)
                          (selection-batch-snapshot-selection-cursor selection))))
          (append (selection-batch-snapshot-selections snapshot) nil)))
        (selection-batch-snapshot-primary-id snapshot))))
    (should selection-first--selection-history)
    (let ((tick (buffer-chars-modified-tick)))
      (selection-first-delete)
      (should (= tick (buffer-chars-modified-tick))))
    (should-not selection-first--selection-history)
    (should-not selection-first--selection-redo)))

(ert-deftest selection-first-keep-regexp-demotes-and-history-restores-plural ()
  (selection-first-test--with-buffer "aa bb cc"
    (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
    (selection-first-keep-regexp "bb")
    (should-not (selection-batch-active-p))
    (should (equal '((0 4 6)) (selection-first-test--triples)))
    (selection-first-selection-undo)
    (should (equal '((a 1 3) (b 4 6) (c 7 9))
                   (selection-first-test--triples)))
    (selection-first-selection-redo)
    (should-not (selection-batch-active-p))
    (should (equal '((0 4 6)) (selection-first-test--triples)))))

(ert-deftest selection-first-regexp-refinement-prompt-and-failure-are-safe ()
  (selection-first-test--with-buffer "aa bb cc"
    (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
    (let ((calls 0))
      (cl-letf (((symbol-function 'selection-batch-read-regexp)
                 (lambda (_prompt)
                   (setq calls (1+ calls))
                   "bb")))
        (call-interactively #'selection-first-keep-regexp))
      (should (= calls 1)))
    (let ((before (selection-first-current-snapshot))
          (history selection-first--selection-history))
      (should-error (selection-first-drop-regexp ".") :type 'user-error)
      (should (equal before (selection-first-current-snapshot)))
      (should (equal history selection-first--selection-history)))))

(ert-deftest selection-first-text-plan-is-selection-history-barrier ()
  (selection-first-test--with-buffer "aa x aa y aa"
    (let ((text (buffer-string)))
      (selection-first-test--select 1 3)
      (selection-first-gather-same-all)
      (selection-first-reverse)
      (should selection-first--selection-history)
      (should (selection-batch--session-history selection-batch--session))
      (selection-first-replace "zz")
      (should-not selection-first--selection-history)
      (should-not selection-first--selection-redo)
      (should-not (selection-batch--session-history selection-batch--session))
      (should-not (selection-batch--session-redo selection-batch--session))
      (let ((before (selection-first-current-snapshot))
            (changed (buffer-string)))
        (should-error (selection-first-selection-undo) :type 'user-error)
        (should (equal before (selection-first-current-snapshot)))
        (should (equal changed (buffer-string))))
      (selection-first-undo)
      (should (equal text (buffer-string))))))

(ert-deftest selection-first-foreign-history-failure-preserves-owner ()
  (let ((owner (generate-new-buffer " *selection-first-history-owner*"))
        (other (generate-new-buffer " *selection-first-history-other*")))
    (unwind-protect
        (progn
          (with-current-buffer owner
            (insert "aa x aa y aa z aa")
            (selection-first-mode 1)
            (selection-first-test--select 1 3)
            (selection-first-gather-same-next)
            (selection-first-gather-same-next)
            (selection-first-gather-same-next)
            (selection-first-selection-undo))
          (let ((snapshot (with-current-buffer owner
                            (selection-first-current-snapshot)))
                (history (with-current-buffer owner
                           (copy-sequence
                            selection-first--selection-history)))
                (redo (with-current-buffer owner
                        (copy-sequence
                         selection-first--selection-redo))))
            (should history)
            (should redo)
            (with-current-buffer other
              (insert "bb")
              (selection-first-mode 1)
              (should-error (selection-first-selection-undo)
                            :type 'user-error)
              (should-error (selection-first-selection-redo)
                            :type 'user-error))
            (should (selection-batch-active-p))
            (should (eq owner
                        (selection-batch--session-buffer
                         selection-batch--session)))
            (with-current-buffer owner
              (should (equal snapshot (selection-first-current-snapshot)))
              (should (equal history selection-first--selection-history))
              (should (equal redo selection-first--selection-redo)))))
      (when selection-batch--session
        (with-current-buffer (selection-batch--session-buffer
                              selection-batch--session)
          (selection-batch-collapse)))
      (kill-buffer owner)
      (kill-buffer other))))

(ert-deftest selection-first-stale-local-history-preserves-foreign-owner ()
  (let ((stale (generate-new-buffer " *selection-first-stale-history*"))
        (owner (generate-new-buffer " *selection-first-live-owner*")))
    (unwind-protect
        (progn
          (with-current-buffer stale
            (insert "aa x aa")
            (selection-first-mode 1)
            (selection-first-test--select 1 3)
            (selection-first-gather-same-next))
          (with-current-buffer owner
            (insert "bb x bb")
            (selection-first-mode 1)
            (selection-first-test--select 1 3)
            (selection-first-gather-same-next))
          (let ((owner-snapshot
                 (with-current-buffer owner
                   (selection-first-current-snapshot))))
            (with-current-buffer stale
              (goto-char (point-max))
              (insert "!")
              (should-error (selection-first-selection-undo)
                            :type 'user-error))
            (should (selection-batch-active-p))
            (should (eq owner (selection-batch-owner-buffer)))
            (with-current-buffer owner
              (should (equal owner-snapshot
                             (selection-first-current-snapshot))))))
      (when selection-batch--session
        (with-current-buffer (selection-batch-owner-buffer)
          (selection-batch-collapse)))
      (kill-buffer stale)
      (kill-buffer owner))))

(ert-deftest selection-first-forward-and-backward-char-transform-all-selections ()
  (selection-first-test--with-buffer "abcdef"
    (selection-first-install-ranges '((a 1 2) (b 4 5)) 'a)
    (selection-first-forward-char)
    (should (equal '((a 2 3) (b 5 6)) (selection-first-test--triples)))
    (selection-first-backward-char)
    (should (equal '((a 2 1) (b 5 4)) (selection-first-test--triples)))))

(ert-deftest selection-first-extend-and-reverse-preserve-main-and-direction ()
  (selection-first-test--with-buffer "abcdef"
    (selection-first-install-ranges '((a 2 3) (b 4 5)) 'b)
    (selection-first-forward-char-extend)
    (should (equal '((a 2 4) (b 4 6)) (selection-first-test--triples)))
    (should (eq 'b (selection-batch-snapshot-primary-id
                    (selection-first-current-snapshot))))
    (selection-first-reverse)
    (should (equal '((a 4 2) (b 6 4)) (selection-first-test--triples)))))

(ert-deftest selection-first-word-motion-uses-each-selection-cursor ()
  (selection-first-test--with-buffer "one two three"
    (selection-first-install-ranges '((a 1 1) (b 5 5)) 'a)
    (selection-first-forward-word)
    (should (equal '((a 1 4) (b 5 8)) (selection-first-test--triples)))
    (selection-first-backward-word)
    (should (equal '((a 4 1) (b 8 5)) (selection-first-test--triples)))))

(ert-deftest selection-first-line-motion-preserves-per-selection-goal-columns ()
  (selection-first-test--with-buffer "abcd\nxy\n12345\n"
    (selection-first-install-ranges '((a 2 2) (b 4 4)) 'a)
    (let ((last-command 'ignore))
      (selection-first-next-line))
    (should (equal '((a 7 7) (b 8 8)) (selection-first-test--triples)))
    (let ((last-command 'selection-first-next-line))
      (selection-first-next-line))
    (should (equal '((a 10 10) (b 12 12))
                   (selection-first-test--triples)))
    (let ((last-command 'selection-first-next-line))
      (selection-first-previous-line))
    (should (equal '((a 7 7) (b 8 8))
                   (selection-first-test--triples)))))

(ert-deftest selection-first-line-extend-retains-anchor-and-goal-column ()
  (selection-first-test--with-buffer "abc\nxyz\n"
    (selection-first-install-ranges '((a 1 3)) 'a)
    (let ((last-command 'ignore))
      (selection-first-next-line-extend))
    (should (equal '((0 1 7)) (selection-first-test--triples)))
    (let ((last-command 'selection-first-next-line-extend))
      (selection-first-previous-line-extend))
    (should (equal '((0 1 3)) (selection-first-test--triples)))))

(ert-deftest selection-first-line-motion-is-all-or-nothing-at-boundary ()
  (selection-first-test--with-buffer "a\nb"
    (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
    (let ((before (selection-first-test--triples))
          (selection-first--vertical-run '(:sentinel old))
          (last-command 'ignore))
      (should-error (selection-first-previous-line) :type 'user-error)
      (should (equal before (selection-first-test--triples)))
      (should (equal '(:sentinel old) selection-first--vertical-run)))))

(ert-deftest selection-first-line-motion-uses-display-columns-without-insertion ()
  (selection-first-test--with-buffer "\t日x\nab\n\t日x"
    (let ((before (buffer-string)))
      (selection-first-install-ranges '((a 3 3)) 'a)
      (let ((last-command 'ignore))
        (selection-first-next-line))
      (should (equal '((0 7 7)) (selection-first-test--triples)))
      (let ((last-command 'selection-first-next-line))
        (selection-first-next-line))
      (should (equal '((0 10 10)) (selection-first-test--triples)))
      (should (equal before (buffer-string))))))

(ert-deftest selection-first-line-motion-resets-goal-after-other-command ()
  (selection-first-test--with-buffer "abcd\nx\nwxyz\n"
    (selection-first-install-ranges '((a 4 4)) 'a)
    (let ((last-command 'ignore))
      (selection-first-next-line))
    (should (equal '((0 7 7)) (selection-first-test--triples)))
    (let ((last-command 'ignore))
      (selection-first-next-line))
    (should (equal '((0 9 9)) (selection-first-test--triples)))))

(ert-deftest selection-first-line-motion-respects-narrowing-boundary ()
  (selection-first-test--with-buffer "a\nbc\ndef"
    (narrow-to-region 3 (point-max))
    (selection-first-install-ranges '((a 3 3)) 'a)
    (let ((before (selection-first-test--triples))
          (last-command 'ignore))
      (should-error (selection-first-previous-line) :type 'user-error)
      (should (equal before (selection-first-test--triples))))))

(ert-deftest selection-first-plural-line-extend-rejects-overlap-atomically ()
  (selection-first-test--with-buffer "ab\ncd"
    (selection-first-install-ranges '((a 1 1) (b 2 2)) 'a)
    (let ((before (selection-first-test--triples))
          (last-command 'ignore))
      (should-error (selection-first-next-line-extend) :type 'user-error)
      (should (equal before (selection-first-test--triples))))))

(ert-deftest selection-first-line-motion-rejects-coincident-clamped-carets ()
  (selection-first-test--with-buffer "abcdef\nx\nabcdef"
    (selection-first-install-ranges '((a 5 5) (b 6 6)) 'a)
    (let ((before (selection-first-test--triples))
          (selection-first--vertical-run '(:sentinel old))
          (last-command 'ignore))
      (should-error (selection-first-next-line) :type 'user-error)
      (should (equal before (selection-first-test--triples)))
      (should (equal '(:sentinel old) selection-first--vertical-run)))))

(ert-deftest selection-first-line-motion-rejects-stale-run-fingerprint ()
  (selection-first-test--with-buffer "abcd\nx\nwxyz\n"
    (selection-first-install-ranges '((a 4 4)) 'a)
    (let ((last-command 'ignore))
      (selection-first-next-line))
    (should selection-first--vertical-run)
    ;; Replace the singleton with the same canonical ID at a different cursor.
    (selection-first-install-ranges '((fresh 6 6)) 'fresh)
    (let ((last-command 'selection-first-next-line))
      (selection-first-next-line))
    (should (equal '((0 8 8)) (selection-first-test--triples)))))

(ert-deftest selection-first-mode-toggle-clears-vertical-run ()
  (selection-first-test--with-buffer "ab\ncd"
    (selection-first-install-ranges '((a 1 1)) 'a)
    (let ((last-command 'ignore))
      (selection-first-next-line))
    (should selection-first--vertical-run)
    (selection-first-mode -1)
    (should-not selection-first--vertical-run)
    (selection-first-mode 1)
    (should-not selection-first--vertical-run)))

(ert-deftest selection-first-planned-delete-keeps-normal-state-and-one-undo-unit ()
  (selection-first-test--with-buffer "aa bb aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (selection-first-delete)
    (should (equal " bb " (buffer-string)))
    (should (eq selection-first--state 'normal))
    (selection-first-undo)
    (should (equal "aa bb aa" (buffer-string)))
    (should-not (selection-batch-active-p))))

(ert-deftest selection-first-singleton-insert-targets-directed-endpoints ()
  (dolist (case '((selection-first-insert nil 3)
                  (selection-first-append nil 1)
                  (selection-first-insert t 1)
                  (selection-first-append t 3)))
    (pcase-let ((`(,command ,reverse-p ,expected) case))
      (selection-first-test--with-buffer "abc"
        (selection-first-test--select 1 3)
        (when reverse-p
          (selection-first-reverse))
        (funcall command)
        (should (eq selection-first--state 'insert))
        (should-not mark-active)
        (should (= expected (point)))))))

(ert-deftest selection-first-scalar-insert-hands-off-to-native-command-loop ()
  (selection-first-test--with-buffer "abc"
    (selection-first-test--select 1 2)
    (selection-first-insert)
    (should (eq selection-first--state 'insert))
    (should-not mark-active)
    (should (= 2 (point)))
    (insert "日")
    (selection-first-exit-insert)
    (should (eq selection-first--state 'normal))
    (should (equal "a日bc" (buffer-string)))
    (should (equal (list (list 0 3 3))
                   (selection-first-test--triples)))))

(ert-deftest selection-first-plural-insert-targets-directed-endpoints ()
  (dolist (case '((selection-first-insert nil ((a 3 3) (b 6 6)))
                  (selection-first-append nil ((a 1 1) (b 4 4)))
                  (selection-first-insert t ((a 1 1) (b 4 4)))
                  (selection-first-append t ((a 3 3) (b 6 6)))))
    (pcase-let ((`(,command ,reverse-p ,expected) case))
      (selection-first-test--with-buffer "aa aa"
        (selection-first-install-ranges '((a 1 3) (b 4 6)) 'a)
        (when reverse-p
          (selection-first-reverse))
        (funcall command)
        (should (eq selection-first--state 'batch-insert))
        (should (equal expected (selection-first-test--triples)))
        (should (= 2 (selection-batch-count)))))))

(ert-deftest selection-first-plural-insert-targets-each-mixed-direction-endpoint ()
  (dolist (case '((selection-first-insert ((forward 3 3) (reverse 4 4)))
                  (selection-first-append ((forward 1 1) (reverse 6 6)))))
    (pcase-let ((`(,command ,expected) case))
      (selection-first-test--with-buffer "aa aa"
        (selection-first-install-ranges
         '((forward 1 3) (reverse 6 4)) 'reverse)
        (funcall command)
        (should (eq selection-first--state 'batch-insert))
        (should (equal expected (selection-first-test--triples)))
        (should (eq 'reverse
                    (selection-batch-snapshot-primary-id
                     (selection-first-current-snapshot))))))))

(ert-deftest selection-first-batch-insert-literal-multichar-unicode-and-advance ()
  (selection-first-test--with-buffer "ab cd"
    (selection-first-install-ranges '((a 1 1) (b 4 4)) 'a)
    (selection-first-insert)
    (selection-first-batch-insert-string "日🙂")
    (should (equal "日🙂ab 日🙂cd" (buffer-string)))
    (should (equal '((a 3 3) (b 8 8)) (selection-first-test--triples)))))

(ert-deftest selection-first-batch-insert-command-loop-printable-newline-and-exit ()
  (selection-first-test--with-buffer "a\nb\n"
    (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (execute-kbd-macro (kbd "i X RET Y <escape>")))
    (should (equal "X\nYa\nX\nYb\n" (buffer-string)))
    (should (eq selection-first--state 'normal))
    (should (= 2 (selection-batch-count)))))

(ert-deftest selection-first-org-indent-batch-command-loop-is-supported ()
  (selection-first-test--with-org-indent-buffer "* A\nbody\n* B\nbody\n"
    (selection-first-install-ranges '((a 5 5) (b 14 14)) 'a)
    (save-window-excursion
      (switch-to-buffer (current-buffer))
      (execute-kbd-macro (kbd "i X <escape>")))
    (should (equal "* A\nXbody\n* B\nXbody\n" (buffer-string)))
    (should (eq selection-first--state 'normal))
    (should (= 2 (selection-batch-count)))))

(ert-deftest selection-first-org-indent-properties-refresh-after-rollback ()
  (selection-first-test--with-org-indent-buffer "* A\nbody\n* B\nbody\n"
    (org-indent-refresh-maybe (point-min) (point-max) 0)
    (let ((before-text (buffer-string))
          (before-properties (selection-first-test--org-indent-signature))
          (original selection-batch--plan-primitive-edit-function)
          (original-rollback
           (symbol-function 'selection-batch-org--rollback-refresh))
          (calls 0)
          properties-differed
          rollback-called)
      (selection-first-install-ranges '((a 1 1) (b 10 10)) 'a)
      (selection-first-insert)
      (let ((selection-batch--plan-primitive-edit-function
             (lambda (edit)
               (cl-incf calls)
               (if (= calls 2)
                   (progn
                     (setq properties-differed
                           (not (equal before-properties
                                       (selection-first-test--org-indent-signature))))
                     (error "injected second primitive failure"))
                 (funcall original edit)))))
        (cl-letf (((symbol-function 'selection-batch-org--rollback-refresh)
                   (lambda ()
                     (setq rollback-called t)
                     (funcall original-rollback))))
          (should-error (selection-first-batch-insert-string "*")
                        :type 'error)))
      (should (= calls 2))
      (should properties-differed)
      (should rollback-called)
      (should (equal before-text (buffer-string)))
      (should (equal before-properties
                     (selection-first-test--org-indent-signature))))))

(ert-deftest selection-first-org-indent-rollback-refresh-widens-and-recomputes ()
  (selection-first-test--with-org-indent-buffer "* A\nbody\n* B\nbody\n"
    (org-indent-refresh-maybe (point-min) (point-max) 0)
    (let ((expected (selection-first-test--org-indent-signature)))
      (with-silent-modifications
        (put-text-property 14 15 'line-prefix "STALE")
        (put-text-property 14 15 'wrap-prefix "STALE"))
      (narrow-to-region 1 10)
      (selection-batch-org--rollback-refresh)
      (should (= (point-min) 1))
      (should (= (point-max) 10))
      (save-restriction
        (widen)
        (should (equal expected
                       (selection-first-test--org-indent-signature)))))))

(ert-deftest selection-first-org-indent-adapter-rejects-changed-inner-chain ()
  (selection-first-test--with-org-indent-buffer "* A\nbody\n* B\nbody\n"
    (selection-first-install-ranges '((a 5 5) (b 14 14)) 'a)
    (selection-first-insert)
    (let ((selection-batch-org--raw-refresh-function #'ignore)
          (before (buffer-string)))
      (should-error (selection-first-batch-insert-string "X") :type 'error)
      (should (equal before (buffer-string))))))

(ert-deftest selection-first-org-indent-adapter-rejects-suppressing-outer-advice ()
  (selection-first-test--with-org-indent-buffer "* A\nbody\n* B\nbody\n"
    (selection-first-install-ranges '((a 5 5) (b 14 14)) 'a)
    (selection-first-insert)
    (let ((before (buffer-string))
          (selection-first-test--org-outer-advice-calls 0))
      (advice-add 'org-indent-refresh-maybe :around
                  #'selection-first-test--org-suppressing-outer-advice)
      (unwind-protect
          (progn
            (should-error (selection-first-batch-insert-string "X")
                          :type 'error)
            (should (equal before (buffer-string)))
            ;; Validation runs before the first primitive, so suppression is
            ;; detected without invoking the foreign advice at all.
            (should (= 0 selection-first-test--org-outer-advice-calls)))
        (advice-remove 'org-indent-refresh-maybe
                       #'selection-first-test--org-suppressing-outer-advice)))))

(ert-deftest selection-first-org-indent-adapter-unloads-cleanly ()
  (unwind-protect
      (progn
        (should (advice-member-p #'selection-batch-org--refresh-around
                                 'org-indent-refresh-maybe))
        (unload-feature 'selection-batch-org t)
        (should-not (advice-member-p #'selection-batch-org--refresh-around
                                     'org-indent-refresh-maybe)))
    (require 'selection-batch-org))
  (should (advice-member-p #'selection-batch-org--refresh-around
                           'org-indent-refresh-maybe)))

(ert-deftest selection-first-org-indent-unload-is-atomic-during-apply ()
  (require 'org-indent)
  (selection-batch-org--install)
  (let ((hook-before (copy-sequence after-load-functions))
        (registry-before (copy-sequence selection-batch--property-adapters))
        (adapter-before selection-batch-org--adapter)
        (raw-before selection-batch-org--raw-refresh-function)
        (reason-before selection-batch-org--disabled-reason))
    (let ((selection-batch--plan-application-active t))
      (should-error (selection-batch-org-unload-function) :type 'error))
    (should (equal hook-before after-load-functions))
    (should (equal registry-before selection-batch--property-adapters))
    (should (eq adapter-before selection-batch-org--adapter))
    (should (eq raw-before selection-batch-org--raw-refresh-function))
    (should (equal reason-before selection-batch-org--disabled-reason))
    (should (advice-member-p #'selection-batch-org--refresh-around
                             'org-indent-refresh-maybe))))

(ert-deftest selection-first-org-indent-deferred-install-retries-cleanly ()
  (let ((installed selection-batch-org--adapter))
    (unwind-protect
        (progn
          (advice-remove 'org-indent-refresh-maybe
                         #'selection-batch-org--refresh-around)
          (selection-batch--unregister-property-adapter installed)
          (setq selection-batch-org--adapter nil
                selection-batch-org--raw-refresh-function nil)
          (add-hook 'after-load-functions #'selection-batch-org--after-load)
          (let ((selection-batch--plan-application-active t))
            (should-error (selection-batch-org--after-load) :type 'error))
          (should (memq #'selection-batch-org--after-load after-load-functions))
          (should-not selection-batch-org--adapter)
          (should-not selection-batch-org--raw-refresh-function)
          (should-not (advice-member-p #'selection-batch-org--refresh-around
                                       'org-indent-refresh-maybe))
          (selection-batch-org--after-load)
          (should selection-batch-org--adapter)
          (should (memq selection-batch-org--adapter
                        selection-batch--property-adapters))
          (should (advice-member-p #'selection-batch-org--refresh-around
                                   'org-indent-refresh-maybe))
          (should-not (memq #'selection-batch-org--after-load
                            after-load-functions)))
      (unless selection-batch-org--adapter
        (selection-batch-org--install)))))

(defun selection-first-test--org-adapter-state ()
  "Capture every mutable part of the Org adapter lifecycle."
  (list (copy-sequence after-load-functions)
        (copy-sequence selection-batch--property-adapters)
        (symbol-function 'org-indent-refresh-maybe)
        selection-batch-org--adapter
        selection-batch-org--raw-refresh-function
        selection-batch-org--disabled-reason))

(ert-deftest selection-first-org-indent-install-rolls-back-late-registration-error ()
  (let ((installed selection-batch-org--adapter))
    (unwind-protect
        (progn
          (advice-remove 'org-indent-refresh-maybe
                         #'selection-batch-org--refresh-around)
          (selection-batch--unregister-property-adapter installed)
          (setq selection-batch-org--adapter nil
                selection-batch-org--raw-refresh-function nil)
          (add-hook 'after-load-functions #'selection-batch-org--after-load)
          (let ((before (selection-first-test--org-adapter-state))
                (register (symbol-function
                           'selection-batch--register-property-adapter)))
            (cl-letf (((symbol-function 'selection-batch--register-property-adapter)
                       (lambda (&rest arguments)
                         (apply register arguments)
                         (error "late registration failure"))))
              (should-error (selection-batch-org--after-load) :type 'error))
            (should (equal before (selection-first-test--org-adapter-state))))
          (selection-batch-org--after-load)
          (should (memq selection-batch-org--adapter
                        selection-batch--property-adapters))
          (should (advice-member-p #'selection-batch-org--refresh-around
                                   'org-indent-refresh-maybe)))
      (unless selection-batch-org--adapter
        (selection-batch-org--install)))))

(ert-deftest selection-first-org-indent-install-rolls-back-late-advice-error ()
  (let ((installed selection-batch-org--adapter))
    (unwind-protect
        (progn
          (advice-remove 'org-indent-refresh-maybe
                         #'selection-batch-org--refresh-around)
          (selection-batch--unregister-property-adapter installed)
          (setq selection-batch-org--adapter nil
                selection-batch-org--raw-refresh-function nil)
          (add-hook 'after-load-functions #'selection-batch-org--after-load)
          (let ((before (selection-first-test--org-adapter-state))
                (add (symbol-function 'advice-add)))
            (cl-letf (((symbol-function 'advice-add)
                       (lambda (&rest arguments)
                         (apply add arguments)
                         (error "late advice failure"))))
              (should-error (selection-batch-org--after-load) :type 'error))
            (should (equal before (selection-first-test--org-adapter-state))))
          (selection-batch-org--after-load)
          (should (memq selection-batch-org--adapter
                        selection-batch--property-adapters))
          (should (advice-member-p #'selection-batch-org--refresh-around
                                   'org-indent-refresh-maybe)))
      (unless selection-batch-org--adapter
        (selection-batch-org--install)))))

(ert-deftest selection-first-org-indent-unload-rolls-back-late-unregister-error ()
  (selection-batch-org--install)
  (let ((before (selection-first-test--org-adapter-state))
        (unregister (symbol-function
                     'selection-batch--unregister-property-adapter)))
    (cl-letf (((symbol-function 'selection-batch--unregister-property-adapter)
               (lambda (adapter)
                 (funcall unregister adapter)
                 (error "late unregister failure"))))
      (should-error (selection-batch-org-unload-function) :type 'error))
    (should (equal before (selection-first-test--org-adapter-state)))
    (selection-batch-org--validate selection-batch-org--adapter)))

(ert-deftest selection-first-batch-insert-command-loop-rejects-unsupported-keys ()
  (dolist (keys '("C-k" "TAB" "C-/" "C-x u" "C-c z"))
    (selection-first-test--with-buffer "abc def"
      (selection-first-install-ranges '((a 1 1) (b 5 5)) 'a)
      (selection-first-insert)
      (local-set-key (kbd "C-c z") #'selection-first-test--unowned-command)
      (let ((before (selection-first-current-snapshot))
            (selection-first-test--unowned-command-calls 0))
        (save-window-excursion
          (switch-to-buffer (current-buffer))
          (should-error (execute-kbd-macro (kbd keys)) :type 'user-error))
        (should (equal "abc def" (buffer-string)))
        (should (equal before (selection-first-current-snapshot)))
        (should (eq selection-first--state 'batch-insert))
        (should (= 0 selection-first-test--unowned-command-calls))))))

(ert-deftest selection-first-batch-insert-backward-and-forward-delete ()
  (selection-first-test--with-buffer "abc def"
    (selection-first-install-ranges '((a 2 2) (b 6 6)) 'a)
    (selection-first-insert)
    (selection-first-batch-delete-backward)
    (should (equal "bc ef" (buffer-string)))
    (should (equal '((a 1 1) (b 4 4)) (selection-first-test--triples)))
    (selection-first-batch-delete-forward)
    (should (equal "c f" (buffer-string)))
    (should (equal '((a 1 1) (b 3 3)) (selection-first-test--triples)))))

(ert-deftest selection-first-batch-delete-boundary-and-read-only-are-atomic ()
  (selection-first-test--with-buffer "abc"
    (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
    (selection-first-insert)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-batch-delete-backward) :type 'user-error)
      (should (equal "abc" (buffer-string)))
      (should (equal before (selection-first-current-snapshot)))))
  (selection-first-test--with-buffer "abcd"
    (put-text-property 2 3 'read-only t)
    (selection-first-install-ranges '((a 1 1) (b 2 2)) 'a)
    (selection-first-insert)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-batch-delete-forward) :type 'user-error)
      (should (equal "abcd" (buffer-string)))
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-batch-delete-backward-rejects-adjacent-caret-collapse ()
  (selection-first-test--with-buffer "abcd"
    (selection-first-install-ranges '((a 2 2) (b 3 3)) 'a)
    (selection-first-insert)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-batch-delete-backward) :type 'user-error)
      (should (equal "abcd" (buffer-string)))
      (should (equal before (selection-first-current-snapshot)))
      (selection-first-batch-insert-string "X")
      (should (equal "aXbXcd" (buffer-string))))))

(ert-deftest selection-first-batch-delete-forward-rejects-adjacent-caret-collapse ()
  (selection-first-test--with-buffer "abcd"
    (selection-first-install-ranges '((a 2 2) (b 3 3)) 'a)
    (selection-first-insert)
    (let ((before (selection-first-current-snapshot)))
      (should-error (selection-first-batch-delete-forward) :type 'user-error)
      (should (equal "abcd" (buffer-string)))
      (should (equal before (selection-first-current-snapshot)))
      (selection-first-batch-insert-string "X")
      (should (equal "aXbXcd" (buffer-string))))))

(ert-deftest selection-first-batch-entry-rejects-same-position-endpoints ()
  (dolist (case '((selection-first-insert ((range 1 3) (caret 3 3)))
                  (selection-first-append ((caret 1 1) (range 1 3)))))
    (pcase-let ((`(,command ,ranges) case))
      (selection-first-test--with-buffer "abc"
        (selection-first-install-ranges ranges (caar ranges))
        (let ((before (selection-first-current-snapshot)))
          (should-error (funcall command) :type 'user-error)
          (should (eq selection-first--state 'normal))
          (should (equal before (selection-first-current-snapshot)))
          (should (equal "abc" (buffer-string))))))))

(ert-deftest selection-first-batch-intent-rejects-external-edit-away-from-carets ()
  (selection-first-test--with-buffer "abc def"
    (selection-first-install-ranges '((a 1 1) (b 5 5)) 'a)
    (selection-first-insert)
    (goto-char (point-max))
    (insert "!")
    (should-error (selection-first-batch-insert-string "x") :type 'user-error)
    (should (equal "abc def!" (buffer-string)))
    (should (eq selection-first--state 'batch-insert))))

(ert-deftest selection-first-batch-fingerprint-rejects-session-transform-and-clears ()
  (selection-first-test--with-buffer "abc def"
    (selection-first-install-ranges '((a 1 1) (b 5 5)) 'a)
    (selection-first-insert)
    (let ((fingerprint selection-first--batch-insert-fingerprint))
      (should fingerprint)
      (selection-batch-apply-transform
       (lambda (snapshot)
         (selection-batch-snapshot-with-selections
          snapshot (selection-batch-snapshot-selections snapshot) 'b)))
      (should-error (selection-first-batch-insert-string "x") :type 'user-error)
      (should (equal fingerprint selection-first--batch-insert-fingerprint))
      (selection-first-exit-batch-insert)
      (should-not selection-first--batch-insert-fingerprint))))

(ert-deftest selection-first-failed-batch-entry-preserves-history-and-redo ()
  (selection-first-test--with-buffer "abcd"
    (selection-first-install-ranges '((a 1 2) (b 2 2)) 'a)
    (selection-first-reverse)
    (selection-first-reverse)
    (selection-first-selection-undo)
    (let ((history (copy-sequence selection-first--selection-history))
          (redo (copy-sequence selection-first--selection-redo)))
      (should history)
      (should redo)
      (should-error (selection-first-append) :type 'user-error)
      (should (equal history selection-first--selection-history))
      (should (equal redo selection-first--selection-redo))
      (should (eq selection-first--state 'normal)))))

(ert-deftest selection-first-batch-intent-error-and-quit-roll-back-session ()
  (dolist (condition '(error quit))
    (selection-first-test--with-buffer "abc def"
      (selection-first-install-ranges '((a 1 1) (b 5 5)) 'a)
      (selection-first-insert)
      (let* ((before (selection-first-current-snapshot))
             (before-triples (selection-first-test--triples))
             (before-generation (selection-batch-snapshot-generation before))
             (calls 0)
            (selection-batch--plan-primitive-edit-function
             (lambda (edit)
               (cl-incf calls)
               (if (= calls 2)
                   (signal condition nil)
                 (selection-batch--plan-primitive-edit edit)))))
        (let (caught)
          (condition-case err
              (selection-first-batch-insert-string "x")
            ((error quit) (setq caught (car err))))
          (should (eq caught condition)))
        (should (equal "abc def" (buffer-string)))
        ;; Emacs modification ticks are monotonic even after rollback; the
        ;; session's semantic state and generation are restored.
        (should (equal before-triples (selection-first-test--triples)))
        (should (= before-generation
                   (selection-batch-snapshot-generation
                    (selection-first-current-snapshot))))
        (should (eq selection-first--state 'batch-insert))
        (selection-first-batch-insert-string "y")
        (should (equal "yabc ydef" (buffer-string)))))))

(ert-deftest selection-first-batch-delete-error-resynchronizes-fingerprint ()
  (dolist (command '(selection-first-batch-delete-backward
                     selection-first-batch-delete-forward))
    (selection-first-test--with-buffer "abc def"
      (selection-first-install-ranges '((a 2 2) (b 6 6)) 'a)
      (selection-first-insert)
      (let ((calls 0)
            (selection-batch--plan-primitive-edit-function
             (lambda (edit)
               (cl-incf calls)
               (if (= calls 2)
                   (error "injected delete failure")
                 (selection-batch--plan-primitive-edit edit)))))
        (should-error (funcall command) :type 'error))
      (should (equal "abc def" (buffer-string)))
      (should (eq selection-first--state 'batch-insert))
      (selection-first-batch-insert-string "X")
      (should (equal "aXbc dXef" (buffer-string))))))

(ert-deftest selection-first-batch-insert-one-undo-unit-per-intent ()
  (selection-first-test--with-buffer "a b"
    (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
    (selection-first-insert)
    (selection-first-batch-insert-string "x")
    (selection-first-batch-insert-string "y")
    (selection-first-exit-batch-insert)
    (selection-first-undo)
    (should (equal "xa xb" (buffer-string)))
    (let ((last-command 'undo))
      (selection-first-undo))
    (should (equal "a b" (buffer-string)))
    (should-not (selection-batch-active-p))
    (should (eq selection-first--state 'normal))))

(ert-deftest selection-first-batch-self-insert-rejects-rebound-control-event ()
  (selection-first-test--with-buffer "a b"
    (let ((old (local-key-binding (kbd "C-k"))))
      (unwind-protect
          (progn
            (local-set-key (kbd "C-k") #'selection-first-batch-self-insert)
            (selection-first-install-ranges '((a 1 1) (b 3 3)) 'a)
            (selection-first-insert)
            (let ((before (selection-first-current-snapshot))
                  (window (selected-window))
                  (old-buffer (window-buffer (selected-window))))
              (unwind-protect
                  (progn
                    (set-window-buffer window (current-buffer))
                    (condition-case nil
                        (execute-kbd-macro (kbd "C-k"))
                      (error nil)))
                (set-window-buffer window old-buffer))
              (should (equal "a b" (buffer-string)))
              (should (equal before (selection-first-current-snapshot)))
              (should (eq selection-first--state 'batch-insert))))
        (local-set-key (kbd "C-k") old)))))

(ert-deftest selection-first-native-once-collapses-calls-once-and-reimports ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (let ((calls 0))
      (selection-first-native-once
       (lambda ()
         (interactive)
         (setq calls (1+ calls))
         (goto-char (point-max))
         (deactivate-mark)))
      (should (= 1 calls))
      (should-not (selection-batch-active-p))
      (should (eq selection-first--state 'normal))
      (should (equal (list (list 0 (point-max) (point-max)))
                     (selection-first-test--triples))))))

(ert-deftest selection-first-mode-has-stable-dvp-grammar-without-meow ()
  (should (eq (lookup-key selection-first-normal-map (kbd "d"))
              #'selection-first-backward-char))
  (should (eq (lookup-key selection-first-normal-map (kbd "n"))
              #'selection-first-forward-char))
  (should (eq (lookup-key selection-first-normal-map (kbd "t"))
              #'selection-first-previous-line))
  (should (eq (lookup-key selection-first-normal-map (kbd "s"))
              #'selection-first-next-line))
  (should (eq (lookup-key selection-first-normal-map (kbd "T"))
              #'selection-first-previous-line-extend))
  (should (eq (lookup-key selection-first-normal-map (kbd "S"))
              #'selection-first-next-line-extend))
  (should (eq (lookup-key selection-first-normal-map (kbd "x"))
              #'selection-first-copy))
  (should (eq (lookup-key selection-first-normal-map (kbd "y"))
              #'selection-first-paste))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC a"))
              #'selection-first-gather-same-all))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC n"))
              #'selection-first-gather-same-next))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC p"))
              #'selection-first-gather-same-previous))
  (should (eq (lookup-key selection-first-normal-map (kbd "I"))
              #'selection-first-insert-before-all))
  (should (eq (lookup-key selection-first-normal-map (kbd "A"))
              #'selection-first-insert-after-all))
  (should (eq (lookup-key selection-first-normal-map (kbd "."))
              #'selection-first-repeat))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC u"))
              #'selection-first-selection-undo))
  (should (eq (lookup-key selection-first-normal-map (kbd "SPC U"))
              #'selection-first-selection-redo))
  (should (eq (lookup-key selection-first-normal-map (kbd "u"))
              #'selection-first-undo))
  (should (eq (lookup-key selection-first-normal-map [remap self-insert-command])
              #'selection-first-undefined-key)))

(ert-deftest selection-first-global-turn-on-obeys-buffer-policy ()
  (with-temp-buffer
    (fundamental-mode)
    (selection-first--turn-on)
    (should selection-first-mode)
    (selection-first-mode -1))
  (with-temp-buffer
    (special-mode)
    (selection-first--turn-on)
    (should-not selection-first-mode))
  (with-temp-buffer
    (setq buffer-read-only t)
    (selection-first--turn-on)
    (should-not selection-first-mode)))

(ert-deftest selection-first-disable-collapses-live-set-without-losing-primary ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (selection-first-mode -1)
    (should-not (selection-batch-active-p))
    (should mark-active)
    (should (equal '(1 . 3) (cons (region-beginning) (region-end))))))

(ert-deftest selection-first-fixed-insertion-and-repeat-use-atomic-backend ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-install-ranges '((a 1 3) (b 4 6)) 'a)
    (selection-first-insert-before-all "<")
    (should (equal "<aa <aa" (buffer-string)))
    (selection-first-repeat)
    (should (equal "<<aa <<aa" (buffer-string)))
    (should-not selection-first--selection-history)
    (should-not selection-first--selection-redo))
  (selection-first-test--with-buffer "aa aa"
    (selection-first-install-ranges '((a 1 3) (b 4 6)) 'a)
    (selection-first-insert-after-all ">")
    (should (equal "aa> aa>" (buffer-string)))))

(ert-deftest selection-first-fixed-insertion-prompts-through-safe-reader ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-install-ranges '((a 1 3) (b 4 6)) 'a)
    (let ((calls 0))
      (cl-letf (((symbol-function 'selection-batch-read-string)
                 (lambda (_prompt &optional _initial)
                   (setq calls (1+ calls))
                   "!")))
        (call-interactively #'selection-first-insert-after-all))
      (should (= calls 1))
      (should (equal "aa! aa!" (buffer-string))))))

(ert-deftest selection-first-repeat-copy-keeps-history-and-missing-recipe-is-atomic ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-install-ranges '((a 1 3) (b 4 6)) 'a)
    (selection-first-reverse)
    (selection-first-copy)
    (let ((history (copy-sequence selection-first--selection-history)))
      (selection-first-repeat)
      (should (equal history selection-first--selection-history))))
  (selection-first-test--with-buffer "aa"
    (selection-first-test--select 1 3)
    (let ((selection-batch-last-recipe nil)
          (before (selection-first-current-snapshot)))
      (should-error (selection-first-repeat) :type 'user-error)
      (should-not (selection-batch-active-p))
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-vector-copy-and-paste-use-existing-atomic-backend ()
  (selection-first-test--with-buffer "aa bb aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (selection-first-copy)
    (selection-first-replace "X")
    (should (equal "X bb X" (buffer-string)))
    (selection-first-paste)
    (should (equal "aa bb aa" (buffer-string)))))

(ert-deftest selection-first-singleton-native-text-command-clears-history ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-native-barrier*"))
         (kill-ring nil)
         (kill-ring-yank-pointer nil))
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "aa bb cc")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
            (selection-first-keep-regexp "bb")
            (should selection-first--selection-history)
            (execute-kbd-macro (kbd "C-k"))
            (should (equal "aa bb" (buffer-string)))
            (should-not selection-first--selection-history)
            (should-not selection-first--selection-redo)))
      (set-window-buffer window old)
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest selection-first-native-edit-switch-clears-source-history ()
  (let* ((window (selected-window))
         (old-buffer (window-buffer window))
         (source (generate-new-buffer " *selection-first-switch-source*"))
         (destination (generate-new-buffer " *selection-first-switch-destination*"))
         (key (kbd "C-c C-z"))
         (old-binding (lookup-key global-map key)))
    (unwind-protect
        (progn
          (define-key global-map key
                      #'selection-first-test--native-edit-and-switch)
          (setq selection-first-test--switch-destination destination)
          (set-window-buffer window source)
          (with-current-buffer source
            (insert "aa bb cc")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
            (selection-first-keep-regexp "bb")
            (should selection-first--selection-history))
          (execute-kbd-macro key)
          (should (eq destination (window-buffer window)))
          (with-current-buffer source
            (should (equal "aa bbX cc" (buffer-string)))
            (should-not selection-first--selection-history)
            (should-not selection-first--selection-redo)))
      (define-key global-map key old-binding)
      (setq selection-first-test--switch-destination nil)
      (set-window-buffer window old-buffer)
      (dolist (buffer (list source destination))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest selection-first-native-prompt-edit-clears-history ()
  (let* ((window (selected-window))
         (old-buffer (window-buffer window))
         (source (generate-new-buffer " *selection-first-prompt-source*"))
         (key (kbd "C-c C-p"))
         (old-binding (lookup-key global-map key)))
    (unwind-protect
        (progn
          (define-key global-map key #'selection-first-test--native-prompt-and-edit)
          (set-window-buffer window source)
          (with-current-buffer source
            (insert "aa bb cc")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
            (selection-first-keep-regexp "bb")
            (should selection-first--selection-history))
          (execute-kbd-macro (vconcat key (kbd "Z RET")))
          (with-current-buffer source
            (should (equal "aa bbZ cc" (buffer-string)))
            (should-not selection-first--selection-history)))
      (define-key global-map key old-binding)
      (set-window-buffer window old-buffer)
      (when (buffer-live-p source)
        (kill-buffer source)))))

(ert-deftest selection-first-native-error-and-quit-clear-history ()
  (dolist (case '((selection-first-test--native-edit-and-error error "aa bbE cc")
                  (selection-first-test--native-edit-and-quit quit "aa bbQ cc")))
    (selection-first-test--with-buffer "aa bb cc"
      (selection-first-install-ranges '((a 1 3) (b 4 6) (c 7 9)) 'b)
      (selection-first-keep-regexp "bb")
      (should selection-first--selection-history)
      (let ((caught
             (condition-case condition
                 (progn
                   (command-execute (car case))
                   nil)
               (error condition)
               (quit condition))))
        (should (eq (car caught) (cadr case))))
      (should (equal (caddr case) (buffer-string)))
      (should-not selection-first--selection-history)
      (should-not selection-first--selection-redo))))

(ert-deftest selection-first-native-command-execute-preserves-emacs-semantics ()
  (selection-first-test--with-buffer "abc"
    (let ((selection-first-test--native-observation nil)
          (disabled-command-function
           (lambda (&rest _)
             (setq selection-first-test--native-observation 'disabled)))
          (old-disabled
           (get 'selection-first-test--disabled-native-command 'disabled)))
      (unwind-protect
          (progn
            (put 'selection-first-test--disabled-native-command 'disabled t)
            (command-execute 'selection-first-test--disabled-native-command)
            (should (eq selection-first-test--native-observation 'disabled)))
        (put 'selection-first-test--disabled-native-command 'disabled old-disabled)))
    (let ((window (selected-window))
          (old-buffer (window-buffer (selected-window))))
      (unwind-protect
          (progn
            (set-window-buffer window (current-buffer))
            (local-set-key (kbd "<f14>")
                           #'selection-first-test--native-prefix-target)
            (fset 'selection-first-test--keyboard-macro (kbd "<f14>"))
            (setq selection-first-test--native-observation nil)
            (command-execute 'selection-first-test--keyboard-macro)
            (should (eq (plist-get selection-first-test--native-observation :this)
                        #'selection-first-test--native-prefix-target)))
        (set-window-buffer window old-buffer)
        (fmakunbound 'selection-first-test--keyboard-macro)))))

(ert-deftest selection-first-plural-native-command-execute-preserves-emacs-semantics ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (let ((selection-first-test--native-observation nil)
          (disabled-command-function
           (lambda (&rest _)
             (setq selection-first-test--native-observation 'disabled)))
          (old-disabled
           (get 'selection-first-test--disabled-native-command 'disabled)))
      (unwind-protect
          (progn
            (put 'selection-first-test--disabled-native-command 'disabled t)
            (command-execute 'selection-first-test--disabled-native-command)
            (should (eq selection-first-test--native-observation 'disabled))
            (should (selection-batch-active-p)))
        (put 'selection-first-test--disabled-native-command 'disabled old-disabled)))
    (let ((window (selected-window))
          (old-buffer (window-buffer (selected-window))))
      (unwind-protect
          (progn
            (set-window-buffer window (current-buffer))
            (local-set-key (kbd "<f14>")
                           #'selection-first-test--native-prefix-target)
            (fset 'selection-first-test--plural-keyboard-macro (kbd "<f14>"))
            (setq selection-first-test--native-observation nil)
            (command-execute 'selection-first-test--plural-keyboard-macro)
            (should (eq (plist-get selection-first-test--native-observation :this)
                        #'selection-first-test--native-prefix-target))
            (should-not (selection-batch-active-p)))
        (set-window-buffer window old-buffer)
        (fmakunbound 'selection-first-test--plural-keyboard-macro)))))

(ert-deftest selection-first-singleton-normal-allows-unspecified-native-command ()
  (should (eq (lookup-key selection-first-normal-map (kbd ":"))
              #'selection-first-native-key-once))
  (should-not (memq 'delete-backward-char selection-first--normal-commands))
  (should (advice-member-p #'selection-first--around-command-execute
                           #'command-execute)))

(ert-deftest selection-first-plural-native-command-uses-safe-handoff ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (command-execute 'delete-char)
    (should (equal "aaaa" (buffer-string)))
    (should-not (selection-batch-active-p))
    (should (eq selection-first--state 'normal))))

(ert-deftest selection-first-plural-frontend-alias-retains-atomic-semantics ()
  (unwind-protect
      (progn
        (defalias 'selection-first-test--delete-alias #'selection-first-delete)
        (selection-first-test--with-buffer "aa aa"
          (selection-first-test--select 1 3)
          (selection-first-gather-same-all)
          (command-execute 'selection-first-test--delete-alias)
          (should (equal " " (buffer-string)))
          (should (selection-batch-active-p))))
    (fmakunbound 'selection-first-test--delete-alias)))

(ert-deftest selection-first-invalid-command-preserves-plural-session ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (let ((before (selection-first-current-snapshot)))
      (should-error (command-execute 42) :type 'wrong-type-argument)
      (should (selection-batch-active-p))
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-unowned-prefix-preserves-native-command-loop ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-prefix-fallback*"))
         (map (make-sparse-keymap)))
    (define-key map (kbd "g z") #'selection-first-test--native-prefix-target)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (use-local-map map)
            (insert "aa aa")
            (selection-first-mode 1)
            (let ((selection-first-test--native-observation nil))
              (execute-kbd-macro (kbd "g z"))
              (should (equal
                       '(:argument 1 :state normal
                         :this selection-first-test--native-prefix-target
                         :real selection-first-test--native-prefix-target
                         :keys [103 122]
                         :region nil)
                       selection-first-test--native-observation))
              (selection-first-test--select 1 3)
              (selection-first-gather-same-all)
              (setq selection-first-test--native-observation nil)
              (execute-kbd-macro (kbd "g z"))
              (should (equal
                       '(:argument 1 :state normal
                         :this selection-first-test--native-prefix-target
                         :real selection-first-test--native-prefix-target
                         :keys [103 122]
                         :region (1 . 3))
                       selection-first-test--native-observation))
              (should-not (selection-batch-active-p)))
            (should (eq selection-first--state 'normal))))
      (set-window-buffer window old)
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (selection-first-mode -1))
        (kill-buffer buffer)))))

(ert-deftest selection-first-normal-map-wins-real-key-resolution ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-key-resolution*")))
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (fundamental-mode)
            (selection-first-mode 1)
            (should (advice-member-p #'selection-first--around-command-execute
                                     #'command-execute))
            (should (eq (key-binding (kbd "n")) #'selection-first-forward-char))
            (should (eq (key-binding (kbd "a")) #'selection-first-append))
            (should (eq (key-binding (kbd "z"))
                        #'selection-first-undefined-key))
            (should (eq (key-binding (kbd "C-k")) #'kill-line))
            (insert "abc")
            (goto-char (point-min))
            (execute-kbd-macro (kbd "C-k"))
            (should (equal "" (buffer-string)))))
      (set-window-buffer window old)
      (kill-buffer buffer))))

(ert-deftest selection-first-line-motion-runs-through-real-command-loop ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-line-command-loop*")))
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (fundamental-mode)
            (insert "abcd\nx\nwxyz\n")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 4 4)) 'a)
            (let ((last-command 'ignore))
              (execute-kbd-macro (kbd "s s t"))
              (should (eq last-command #'selection-first-previous-line)))
            (should (equal '((0 7 7)) (selection-first-test--triples)))))
      (set-window-buffer window old)
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest selection-first-incremental-gather-runs-through-command-loop ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-gather-command-loop*")))
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (fundamental-mode)
            (insert "aa x aa y aa")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 1 3)) 'a)
            (execute-kbd-macro (kbd "SPC n SPC n"))
            (should (equal '((0 1 3)
                             ("occurrence-0" 6 8)
                             ("occurrence-1" 11 13))
                           (selection-first-test--triples)))
            (should (equal "occurrence-1"
                           (selection-batch-snapshot-primary-id
                            (selection-first-current-snapshot))))))
      (set-window-buffer window old)
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest selection-first-selection-history-runs-through-command-loop ()
  (let* ((window (selected-window))
         (old (window-buffer window))
         (buffer (generate-new-buffer " *selection-first-history-command-loop*")))
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (fundamental-mode)
            (insert "aa x aa y aa")
            (selection-first-mode 1)
            (selection-first-install-ranges '((a 1 3)) 'a)
            (execute-kbd-macro (kbd "SPC n SPC n SPC u"))
            (should (equal '((0 1 3) ("occurrence-0" 6 8))
                           (selection-first-test--triples)))
            (execute-kbd-macro (kbd "SPC U"))
            (should (equal '((0 1 3)
                             ("occurrence-0" 6 8)
                             ("occurrence-1" 11 13))
                           (selection-first-test--triples)))
            (should (equal "aa x aa y aa" (buffer-string)))))
      (set-window-buffer window old)
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(ert-deftest selection-first-plural-motion-is-all-or-nothing-at-boundary ()
  (selection-first-test--with-buffer "abc"
    (selection-first-install-ranges '((a 1 2) (b 3 4)) 'a)
    (let ((before (selection-first-test--triples)))
      (should-error (selection-first-forward-char) :type 'user-error)
      (should (equal before (selection-first-test--triples))))))

(ert-deftest selection-first-normal-predicate-requires-enabled-mode ()
  (with-temp-buffer
    (selection-first--set-state 'normal)
    (should (eq selection-first--state 'normal))
    (should-not selection-first--normal-active)))

(ert-deftest selection-first-foreign-session-is-collapsed-before-current-buffer-use ()
  (let ((a (generate-new-buffer " *selection-first-a*"))
        (b (generate-new-buffer " *selection-first-b*")))
    (unwind-protect
        (progn
          (with-current-buffer a
            (insert "aa aa")
            (selection-first-mode 1)
            (selection-first-test--select 1 3)
            (selection-first-gather-same-all)
            (should (selection-batch-active-p)))
          (with-current-buffer b
            (insert "bb")
            (goto-char 2)
            (selection-first-mode 1)
            (let ((snapshot (selection-first-current-snapshot)))
              (should (eq b (selection-batch-snapshot-buffer snapshot)))
              (should (= 1 (length (selection-batch-snapshot-selections snapshot))))))
          (should-not (selection-batch-active-p))
          (with-current-buffer a
            (should mark-active)
            (should (equal '(1 . 3) (cons (region-beginning) (region-end))))))
      (when selection-batch--session
        (with-current-buffer (selection-batch--session-buffer selection-batch--session)
          (selection-batch-collapse)))
      (kill-buffer a)
      (kill-buffer b))))

(ert-deftest selection-first-failed-singleton-operation-demotes-created-session ()
  (selection-first-test--with-buffer "abc"
    (selection-first-test--select 1 2)
    (let ((selection-batch-register nil))
      (should-error (selection-first-paste) :type 'user-error))
    (should-not (selection-batch-active-p))
    (should mark-active)
    (should (equal '(1 . 2) (cons (region-beginning) (region-end))))))

(ert-deftest selection-first-native-once-restores-source-not-destination-state ()
  (let ((source (generate-new-buffer " *selection-first-source*"))
        (destination (generate-new-buffer " *selection-first-destination*")))
    (unwind-protect
        (progn
          (with-current-buffer source
            (insert "a")
            (selection-first-mode 1)
            (selection-first-native-once
             (lambda ()
               (interactive)
               (set-buffer destination))))
          (with-current-buffer source
            (should (eq selection-first--state 'normal))
            (should selection-first--normal-active))
          (with-current-buffer destination
            (should-not selection-first--state)
            (should-not selection-first--normal-active)))
      (kill-buffer source)
      (kill-buffer destination))))

(ert-deftest selection-first-rejects-foreign-singleton-snapshot ()
  (let ((source (generate-new-buffer " *selection-first-snapshot-source*"))
        (destination (generate-new-buffer " *selection-first-snapshot-destination*"))
        snapshot)
    (unwind-protect
        (progn
          (with-current-buffer source
            (insert "abc")
            (goto-char 2)
            (setq snapshot (selection-first-current-snapshot)))
          (with-current-buffer destination
            (insert "xyz")
            (goto-char 3)
            (should-error (selection-first-install-snapshot snapshot)
                          :type 'user-error)
            (should (= 3 (point)))
            (should-not mark-active)))
      (kill-buffer source)
      (kill-buffer destination))))

(ert-deftest selection-first-interactive-singleton-replace-uses-native-reader ()
  (selection-first-test--with-buffer "abc"
    (selection-first-test--select 1 2)
    (let ((native-calls 0)
          (batch-calls 0))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _)
                   (cl-incf native-calls)
                   "X"))
                ((symbol-function 'selection-batch-read-string)
                 (lambda (&rest _)
                   (cl-incf batch-calls)
                   (ert-fail "singleton prompt used session reader"))))
        (call-interactively #'selection-first-replace))
      (should (= native-calls 1))
      (should (= batch-calls 0))
      (should (equal "Xbc" (buffer-string)))
      (should-not (selection-batch-active-p)))))

(ert-deftest selection-first-interactive-singleton-replace-quit-is-no-op ()
  (selection-first-test--with-buffer "abc"
    (selection-first-test--select 1 2)
    (let ((before (selection-first-current-snapshot))
          (quit-seen nil))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _) (signal 'quit nil))))
        (condition-case nil
            (call-interactively #'selection-first-replace)
          (quit (setq quit-seen t))))
      (should quit-seen)
      (should (equal "abc" (buffer-string)))
      (should-not (selection-batch-active-p))
      (should (equal before (selection-first-current-snapshot))))))

(ert-deftest selection-first-interactive-plural-replace-uses-safe-reader ()
  (selection-first-test--with-buffer "aa aa"
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (let ((native-calls 0)
          (batch-calls 0))
      (cl-letf (((symbol-function 'read-string)
                 (lambda (&rest _)
                   (cl-incf native-calls)
                   (ert-fail "plural prompt bypassed safe reader")))
                ((symbol-function 'selection-batch-read-string)
                 (lambda (&rest _)
                   (cl-incf batch-calls)
                   "X")))
        (call-interactively #'selection-first-replace))
      (should (= native-calls 0))
      (should (= batch-calls 1))
      (should (equal "X X" (buffer-string))))))

(ert-deftest selection-first-native-key-once-resolves-under-passthrough-state ()
  (selection-first-test--with-buffer "abc"
    (let ((seen-state nil)
          (calls 0))
      (cl-letf (((symbol-function 'read-key-sequence)
                 (lambda (&rest _)
                   (setq seen-state selection-first--state)
                   (kbd "C-e")))
                ((symbol-function 'key-binding)
                 (lambda (&rest _)
                   (lambda ()
                     (interactive)
                     (cl-incf calls)
                     (goto-char (point-max))))))
        (selection-first-native-key-once))
      (should (eq seen-state 'passthrough))
      (should (= calls 1))
      (should (= (point) (point-max)))
      (should (eq selection-first--state 'normal)))))

(ert-deftest selection-first-grammar-drives-map-guard-and-help ()
  (dolist (entry selection-first--grammar)
    (pcase-let ((`(,key ,command ,_category ,_description) entry))
      (should (eq (lookup-key selection-first-normal-map (kbd key)) command))
      (should (memq command selection-first--normal-commands))))
  (with-temp-buffer
    (let ((standard-output (current-buffer)))
      (selection-first--print-help)
      (goto-char (point-min))
      (should (search-forward "SPC a" nil t))
      (should (search-forward "Native key sequence" nil t)))))

(ert-deftest selection-first-lighter-shows-state-and-cardinality ()
  (selection-first-test--with-buffer "aa aa"
    (should (equal " Sel N:1" (selection-first--lighter)))
    (selection-first-test--select 1 3)
    (selection-first-gather-same-all)
    (should (equal " Sel N:2" (selection-first--lighter)))
    (selection-first-collapse)
    (selection-first-insert)
    (should (equal " Sel I" (selection-first--lighter)))
    (selection-first-exit-insert)))

(ert-deftest selection-first-grammar-reinitialization-replaces-active-map ()
  (let ((original-grammar selection-first--grammar)
        (old-map selection-first-normal-map))
    (unwind-protect
        (progn
          (setq selection-first--grammar
                (append original-grammar
                        '(("z" ignore "Test" "Reload sentinel"))))
          (selection-first--initialize-grammar-state)
          (should-not (eq old-map selection-first-normal-map))
          (should (eq (lookup-key selection-first-normal-map (kbd "z"))
                      #'ignore))
          (should (memq #'ignore selection-first--normal-commands))
          (should (eq (cdar selection-first--emulation-alist)
                      selection-first-normal-map)))
      (setq selection-first--grammar original-grammar)
      (selection-first--initialize-grammar-state))))

(ert-deftest selection-first-native-handoff-disables-ineligible-source ()
  (selection-first-test--with-buffer "abc"
    (selection-first-native-once
     (lambda ()
       (interactive)
       (setq buffer-read-only t)))
    (should buffer-read-only)
    (should-not selection-first-mode)
    (should-not selection-first--state)
    (should-not selection-first--normal-active)))

(provide 'selection-first-test)
;;; selection-first-test.el ends here
