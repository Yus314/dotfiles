;;; selection-batch-plan-test.el --- Edit plan tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch-plan)
(require 'selection-batch-ui)

(defun selection-batch-plan-test--selection (id anchor cursor)
  (selection-batch-snapshot-selection-create
   :id id :anchor anchor :cursor cursor))

(defun selection-batch-plan-test--snapshot (buffer triples &optional primary generation)
  (with-current-buffer buffer
    (selection-batch-snapshot-create
     :buffer buffer :buffer-tick (buffer-chars-modified-tick)
     :generation (or generation 0) :primary-id (or primary (caar triples))
     :narrowing (cons (point-min) (point-max))
     :selections (vconcat
                  (mapcar (lambda (triple)
                            (apply #'selection-batch-plan-test--selection triple))
                          triples)))))

(defun selection-batch-plan-test--edit
    (id index beginning end replacement result-anchor result-cursor)
  (selection-batch-edit-create
   :selection-id id :logical-index index :beginning beginning :end end
   :replacement replacement
   :result (selection-batch-plan-test--selection id result-anchor result-cursor)
   :tie-break index))

(defun selection-batch-plan-test--plan
    (source edits result-triples &optional primary register-update recipe)
  (selection-batch-plan-create
   :buffer (selection-batch-snapshot-buffer source)
   :source-buffer-tick (selection-batch-snapshot-buffer-tick source)
   :source-generation (selection-batch-snapshot-generation source)
   :source-narrowing (selection-batch-snapshot-narrowing source)
   :edits (vconcat edits)
   :register-update (or register-update selection-batch-no-update)
   :recipe (or recipe selection-batch-no-update)
   :result-policy
   (selection-batch-snapshot-create
    :buffer (selection-batch-snapshot-buffer source)
    :buffer-tick (selection-batch-snapshot-buffer-tick source)
    :generation (1+ (selection-batch-snapshot-generation source))
    :primary-id (or primary (selection-batch-snapshot-primary-id source))
    :narrowing (selection-batch-snapshot-narrowing source)
    :selections (vconcat
                 (mapcar (lambda (triple)
                           (apply #'selection-batch-plan-test--selection triple))
                         result-triples)))))

(defmacro selection-batch-plan-test--with-session (text triples primary &rest body)
  (declare (indent 3) (debug t))
  `(with-temp-buffer
     (buffer-enable-undo)
     (insert ,text)
     (undo-boundary)
     (setq buffer-undo-list nil)
     (goto-char (point-min))
     (unwind-protect
         (progn
           (selection-batch-install-snapshot
            (selection-batch-plan-test--snapshot
             (current-buffer) ,triples ,primary))
           ,@body)
       (when selection-batch--session
         (ignore-errors
           (selection-batch--cleanup selection-batch--session nil t))))))

(defun selection-batch-plan-test--triples (snapshot)
  (mapcar (lambda (selection)
            (list (selection-batch-snapshot-selection-id selection)
                  (selection-batch-snapshot-selection-anchor selection)
                  (selection-batch-snapshot-selection-cursor selection)))
          (append (selection-batch-snapshot-selections snapshot) nil)))

(ert-deftest selection-batch-edit-and-plan-are-defensive-values ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2)) 'a
    (let* ((replacement (copy-sequence "X"))
           (result (selection-batch-plan-test--selection 'a 1 2))
           (edit (selection-batch-edit-create
                  :selection-id 'a :logical-index 7 :beginning 1 :end 2
                  :replacement replacement :result result :tie-break 7))
           (edits (vector edit))
           (source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan source edits '((a 1 2)))))
      (aset replacement 0 ?Y)
      (aset edits 0 (selection-batch-plan-test--edit 'bad 0 2 3 "Z" 2 3))
      (should (equal "X" (selection-batch-edit-replacement edit)))
      (should (eq 'a (selection-batch-edit-selection-id edit)))
      (should (= 7 (selection-batch-edit-logical-index edit)))
      (let ((exposed (selection-batch-plan-edits plan)))
        (aset exposed 0 (selection-batch-plan-test--edit 'bad 0 2 3 "Z" 2 3)))
      (should (eq 'a (selection-batch-edit-selection-id
                      (aref (selection-batch-plan-edits plan) 0))))
      (should-error
       (eval `(setf (selection-batch--edit-beginning ,edit) 9))))))

(ert-deftest selection-batch-plan-order-is-descending-and-ties-are-reversed-logically ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 2) (b 2 2) (c 5 5)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 2 2 "A" 2 3)
                        (selection-batch-plan-test--edit 'c 2 5 5 "C" 7 8)
                        (selection-batch-plan-test--edit 'b 1 2 2 "B" 3 4))
                  '((a 2 3) (b 3 4) (c 7 8))))
           (ordered (selection-batch-plan-edits plan)))
      (should (equal '(c b a)
                     (mapcar #'selection-batch-edit-selection-id
                             (append ordered nil))))
      (selection-batch-apply-plan plan)
      (should (equal "aABbcdCef" (buffer-string))))))

(ert-deftest selection-batch-plan-rejects-overlap-but-allows-adjacency ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 3) (b 2 4)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (overlap (selection-batch-plan-test--plan
                     source
                     (list (selection-batch-plan-test--edit 'a 0 1 3 "A" 1 2)
                           (selection-batch-plan-test--edit 'b 1 2 4 "B" 2 3))
                     '((a 1 2) (b 2 3))))
           (adjacent (selection-batch-plan-test--plan
                      source
                      (list (selection-batch-plan-test--edit 'a 0 1 3 "A" 1 2)
                            (selection-batch-plan-test--edit 'b 1 3 5 "B" 2 3))
                      '((a 1 2) (b 2 3)))))
      (should-error (selection-batch-validate-plan overlap source) :type 'user-error)
      (should (eq adjacent (selection-batch-validate-plan adjacent source))))))

(ert-deftest selection-batch-plan-validation-covers-cardinality-narrowing-and-staleness ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (edit (selection-batch-plan-test--edit 'a 0 2 3 "X" 2 3))
           (valid (selection-batch-plan-test--plan source (list edit) '((a 2 3))))
           (wrong-count (selection-batch-plan-test--plan source nil '((a 2 3))))
           (outside (selection-batch-plan-test--plan
                     source
                     (list (selection-batch-plan-test--edit 'a 0 0 2 "X" 1 2))
                     '((a 1 2)))))
      (should (eq valid (selection-batch-validate-plan valid source)))
      (should-error (selection-batch-validate-plan wrong-count source) :type 'user-error)
      (should-error (selection-batch-validate-plan outside source) :type 'user-error)
      (insert "!")
      (should-error (selection-batch-validate-plan valid) :type 'user-error))))

(ert-deftest selection-batch-plan-rejects-generation-and-narrowing-staleness ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit 'a 0 2 3 "X" 2 3))
                  '((a 2 3)))))
      (cl-incf (selection-batch--session-generation selection-batch--session))
      (should-error (selection-batch-validate-plan plan) :type 'user-error)
      (cl-decf (selection-batch--session-generation selection-batch--session))
      (narrow-to-region 2 5)
      (should-error (selection-batch-validate-plan plan) :type 'user-error))))

(ert-deftest selection-batch-plan-rejects-buffer-and-property-read-only ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit 'a 0 2 3 "X" 2 3))
                  '((a 2 3)))))
      (setq buffer-read-only t)
      (should-error (selection-batch-validate-plan plan source) :type 'user-error)
      (setq buffer-read-only nil)
      (put-text-property 2 3 'read-only t)
      (should-error (selection-batch-validate-plan plan source) :type 'user-error))))

(ert-deftest selection-batch-apply-two-replacements-and-one-undo-unit ()
  (selection-batch-plan-test--with-session "aa bb cc" '((a 1 3) (b 7 9)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 3 "A" 1 2)
                        (selection-batch-plan-test--edit 'b 1 7 9 "C" 6 7))
                  '((a 1 2) (b 6 7)))))
      (selection-batch-apply-plan plan)
      (should (equal "A bb C" (buffer-string)))
      ;; A live primary keeps the region active; deactivate it so the standard
      ;; command performs whole-buffer undo rather than Emacs' undo-in-region.
      (let ((mark-active nil)) (undo))
      (should (equal "aa bb cc" (buffer-string))))))

(ert-deftest selection-batch-result-uses-explicit-integers-not-moving-markers ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "LONG" 2 4)
                        (selection-batch-plan-test--edit 'b 1 5 6 "Q" 7 8))
                  '((a 2 4) (b 7 8)) 'b)))
      (selection-batch-apply-plan plan)
      (should (equal '((a 2 4) (b 7 8))
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot))))
      (should (eq 'b (selection-batch--session-primary-id selection-batch--session))))))

(defun selection-batch-plan-test--failure-case (condition stage)
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((session selection-batch--session)
           (before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (old-history (list before))
           (old-redo (list before))
           (selection-batch-register '(:old "register"))
           (selection-batch-last-recipe '(:old "recipe"))
           (source before)
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "XX" 1 3)
                        (selection-batch-plan-test--edit 'b 1 5 6 "YY" 6 8))
                  '((a 1 3) (b 6 8)) nil
                  '(:new "register") '(:new "recipe"))))
      (setf (selection-batch--session-history session) old-history
            (selection-batch--session-redo session) old-redo)

      (let ((selection-batch--plan-primitive-edit-function
             (if (eq stage 'edit)
                 (lambda (_edit) (signal condition '("edit failure")))
               selection-batch--plan-primitive-edit-function))
            (selection-batch--plan-install-result-function
             (if (eq stage 'install)
                 (lambda (&rest _) (signal condition '("install failure")))
               selection-batch--plan-install-result-function))
            (selection-batch--plan-refresh-view-function
             (if (eq stage 'view)
                 (lambda (&rest _) (signal condition '("view failure")))
               selection-batch--plan-refresh-view-function)))
        (condition-case caught
            (progn (selection-batch-apply-plan plan)
                   (ert-fail "injected failure was not signalled"))
          ((error quit)
           (should (eq condition (car caught))))))
      (should (equal "abcdef" (buffer-string)))
      (should (eq session selection-batch--session))
      (should (eq old-live (selection-batch--session-selections session)))
      ;; Character modification ticks are intentionally monotonic in Emacs,
      ;; including an aborted change group.  Every restorable integer field is
      ;; exact; the fresh snapshot necessarily reports the newer live tick.
      (let ((restored (selection-batch-current-snapshot)))
        (should (equal (selection-batch-plan-test--triples before)
                       (selection-batch-plan-test--triples restored)))
        (should (= (selection-batch-snapshot-generation before)
                   (selection-batch-snapshot-generation restored)))
        (should (equal (selection-batch-snapshot-narrowing before)
                       (selection-batch-snapshot-narrowing restored))))
      (should (eq old-history (selection-batch--session-history session)))
      (should (eq old-redo (selection-batch--session-redo session)))
      (should (equal '(:old "register") selection-batch-register))
      (should (equal '(:old "recipe") selection-batch-last-recipe))
      (should (eq 'set (selection-batch--session-state session))))))

(ert-deftest selection-batch-primitive-error-rolls-back-every-domain ()
  (selection-batch-plan-test--failure-case 'error 'edit))

(ert-deftest selection-batch-quit-rolls-back-every-domain ()
  (selection-batch-plan-test--failure-case 'quit 'edit))

(ert-deftest selection-batch-result-install-error-rolls-back-every-domain ()
  (selection-batch-plan-test--failure-case 'error 'install))

(ert-deftest selection-batch-view-error-rolls-back-every-domain ()
  (selection-batch-plan-test--failure-case 'error 'view))

(ert-deftest selection-batch-apply-rejects-reentry ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2))
                  '((a 1 2))))
           reentry-condition)
      (let ((selection-batch--plan-primitive-edit-function
             (lambda (edit)
               (condition-case err
                   (selection-batch-apply-plan plan)
                 (user-error (setq reentry-condition err)))
               (selection-batch--plan-primitive-edit edit))))
        (selection-batch-apply-plan plan))
      (should (eq 'user-error (car reentry-condition)))
      (should (equal "Xbc" (buffer-string))))))

(ert-deftest selection-batch-change-hooks-see-real-edits-without-command-replay ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2)
                        (selection-batch-plan-test--edit 'b 1 5 6 "Y" 5 6))
                  '((a 1 2) (b 5 6))))
           before after pre-command post-command)
      (add-hook 'before-change-functions
                (lambda (beginning end) (push (list beginning end) before)) nil t)
      (add-hook 'after-change-functions
                (lambda (beginning end old-length)
                  (push (list beginning end old-length) after)) nil t)
      (add-hook 'pre-command-hook (lambda () (cl-incf pre-command)) nil t)
      (add-hook 'post-command-hook (lambda () (cl-incf post-command)) nil t)
      (selection-batch-apply-plan plan)
      (should (= 4 (length before)))
      (should (= 4 (length after)))
      (should-not pre-command)
      (should-not post-command))))

(ert-deftest selection-batch-replacements-are-fully-copied-before-first-edit ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((first (copy-sequence "X"))
           (second (copy-sequence "Y"))
           (source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 first 1 2)
                        (selection-batch-plan-test--edit 'b 1 5 6 second 5 6))
                  '((a 1 2) (b 5 6))))
           (calls 0)
           (real selection-batch--plan-primitive-edit-function))
      (aset first 0 ?Q)
      (aset second 0 ?R)
      (let ((selection-batch--plan-primitive-edit-function
             (lambda (edit)
               (cl-incf calls)
               (when (= calls 1)
                 ;; Corrupt the not-yet-applied descriptor through its private
                 ;; string object.  The engine must already own a full copy.
                 (let ((pending (cl-find 'a
                                         (append (selection-batch--plan-edits plan) nil)
                                         :key #'selection-batch--edit-selection-id)))
                   (aset (selection-batch--edit-replacement pending) 0 ?Z)))
               (funcall real edit))))
        (selection-batch-apply-plan plan))
      (should (equal "XbcdYf" (buffer-string))))))

(ert-deftest selection-batch-compensation-failure-cleans-session ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2) (b 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2)
                        (selection-batch-plan-test--edit 'b 1 2 3 "Y" 2 3))
                  '((a 1 2) (b 2 3))))
           (refresh-calls 0)
           (selection-batch--plan-install-result-function
            (lambda (&rest _) (error "install failure")))
           (selection-batch--view-refresh-function
            (lambda (&rest _)
              (cl-incf refresh-calls)
              (error "restore view failure"))))
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should-not selection-batch--session)
      (should (equal "abc" (buffer-string))))))

(provide 'selection-batch-plan-test)
;;; selection-batch-plan-test.el ends here
