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

(ert-deftest selection-batch-clean-throw-rolls-back-and-propagates ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((session selection-batch--session)
           (before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (selection-batch-register '(:old "register"))
           (selection-batch-last-recipe '(:old "recipe"))
           (plan (selection-batch-plan-test--plan
                  before
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "XX" 1 3)
                        (selection-batch-plan-test--edit 'b 1 5 6 "YY" 6 8))
                  '((a 1 3) (b 6 8)) nil
                  '(:new "register") '(:new "recipe")))
           (primitive selection-batch--plan-primitive-edit-function)
           (calls 0)
           (selection-batch--plan-primitive-edit-function
            (lambda (edit)
              (funcall primitive edit)
              (when (= (cl-incf calls) 1)
                (throw 'selection-batch-test-exit 'original-throw)))))
      (should (eq 'original-throw
                  (catch 'selection-batch-test-exit
                    (selection-batch-apply-plan plan))))
      (should (equal "abcdef" (buffer-string)))
      (should (eq old-live (selection-batch--session-selections session)))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot))))
      (should (equal '(:old "register") selection-batch-register))
      (should (equal '(:old "recipe") selection-batch-last-recipe))
      (should (eq 'set (selection-batch--session-state session)))
      (dolist (selection (append old-live nil))
        (dolist (marker
                 (list (selection-batch--live-selection-anchor-marker selection)
                       (selection-batch--live-selection-cursor-marker selection)))
          (when (markerp marker)
            (should (marker-buffer marker))))))))

(ert-deftest selection-batch-clean-throw-compensation-throw-fails-closed ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2)) 'a
    (let* ((session selection-batch--session)
           (live (selection-batch--session-selections session))
           (source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2))
                  '((a 1 2))))
           (selection-batch--view-refresh-function
            (lambda (&rest _) (throw 'compensation-exit t)))
           (selection-batch--plan-primitive-edit-function
            (lambda (_edit) (throw 'original-exit t)))
           (error
            (should-error
             (catch 'compensation-exit
               (catch 'original-exit
                 (selection-batch-apply-plan plan)))
             :type 'error)))
      (should (string-match-p "compensation exited nonlocally"
                              (error-message-string error)))
      (should-not selection-batch--session)
      (should-not (selection-batch-active-p))
      (dolist (selection (append live nil))
        (dolist (marker
                 (list (selection-batch--live-selection-anchor-marker selection)
                       (selection-batch--live-selection-cursor-marker selection)))
          (when (markerp marker)
            (should-not (marker-buffer marker))))))))

(ert-deftest selection-batch-final-snapshot-throw-rolls-back-and-propagates ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2)) 'a
    (let* ((session selection-batch--session)
           (before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (plan (selection-batch-plan-test--plan
                  before
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "XX" 1 3))
                  '((a 1 3))))
           (snapshot-function (symbol-function 'selection-batch-current-snapshot))
           (calls 0))
      (cl-letf (((symbol-function 'selection-batch-current-snapshot)
                 (lambda ()
                   ;; The first call captures compensation state before any
                   ;; mutation; fail only at the final snapshot inside the
                   ;; atomic change group.
                   (if (= (cl-incf calls) 2)
                       (throw 'final-snapshot-exit 'original-final-throw)
                     (funcall snapshot-function)))))
        (should (eq 'original-final-throw
                    (catch 'final-snapshot-exit
                      (selection-batch-apply-plan plan)))))
      (should (= calls 2))
      (should (equal "abcdef" (buffer-string)))
      (should (eq session selection-batch--session))
      (should (eq old-live (selection-batch--session-selections session)))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot)))))))

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

(ert-deftest selection-batch-silent-hook-text-edit-rolls-back-entire-plan ()
  (selection-batch-plan-test--with-session "abcdef" '((a 1 2) (b 5 6)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2)
                        (selection-batch-plan-test--edit 'b 1 5 6 "Y" 5 6))
                  '((a 1 2) (b 5 6))))
           (mutated nil))
      (add-hook 'after-change-functions
                (lambda (&rest _)
                  (unless mutated
                    (setq mutated t)
                    (save-excursion
                      (goto-char 3)
                      (insert "!"))))
                nil t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal "abcdef" (buffer-string)))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-hook-property-edit-rolls-back-properties-and-state ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (changed nil))
      (add-hook 'after-change-functions
                (lambda (&rest _)
                  (unless changed
                    (setq changed t)
                    (put-text-property 4 5 'face 'bold))) nil t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal "abcdef" (buffer-string)))
      (should-not (text-property-any (point-min) (point-max) 'face 'bold))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-explicit-trusted-property-refresh-is-accepted ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (refresh
            (lambda (beginning end _old-length)
              (with-silent-modifications
                (put-text-property beginning end 'selection-derived t))))
           (rollback
            (lambda ()
              (with-silent-modifications
                (remove-text-properties (point-min) (point-max)
                                        '(selection-derived nil)))))
           (adapter (selection-batch--register-property-adapter
                     refresh rollback)))
      (unwind-protect
          (progn
            (add-hook
             'after-change-functions
             (lambda (&rest args)
               (selection-batch--call-trusted-property-refresh
                adapter refresh args))
             0 t)
            (selection-batch-apply-plan plan)
            (should (equal "aXcdef" (buffer-string)))
            (should (text-property-any 2 3 'selection-derived t)))
        (selection-batch--unregister-property-adapter adapter)))))

(ert-deftest selection-batch-untrusted-silent-property-after-trusted-is-rejected ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (refresh
            (lambda (&rest _)
              (with-silent-modifications
                (put-text-property 2 3 'selection-derived t))))
           (rollback
            (lambda ()
              (with-silent-modifications
                (remove-text-properties (point-min) (point-max)
                                        '(selection-derived nil)))))
           (adapter (selection-batch--register-property-adapter
                     refresh rollback)))
      (unwind-protect
          (progn
            (add-hook
             'after-change-functions
             (lambda (&rest args)
               (selection-batch--call-trusted-property-refresh
                adapter refresh args))
             0 t)
            (add-hook
             'after-change-functions
             (lambda (&rest _)
               (with-silent-modifications
                 (put-text-property 4 5 'read-only t)))
             10 t)
            (should-error (selection-batch-apply-plan plan) :type 'error)
            (should (equal "abcdef" (buffer-string)))
            (should-not (text-property-any (point-min) (point-max)
                                           'selection-derived t))
            (should (equal (selection-batch-plan-test--triples before)
                           (selection-batch-plan-test--triples
                            (selection-batch-current-snapshot)))))
        (selection-batch--unregister-property-adapter adapter)))))

(ert-deftest selection-batch-signalling-trusted-property-refresh-is-compensated ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (refresh
            (lambda (&rest _)
              (with-silent-modifications
                (put-text-property 4 5 'selection-derived t))
              (error "trusted refresh failed after mutation")))
           (rollback
            (lambda ()
              (with-silent-modifications
                (remove-text-properties (point-min) (point-max)
                                        '(selection-derived nil)))))
           (adapter (selection-batch--register-property-adapter
                     refresh rollback)))
      (unwind-protect
          (progn
            (add-hook
             'after-change-functions
             (lambda (&rest args)
               (selection-batch--call-trusted-property-refresh
                adapter refresh args))
             0 t)
            (should-error (selection-batch-apply-plan plan) :type 'error)
            (should (equal "abcdef" (buffer-string)))
            (should-not (text-property-any (point-min) (point-max)
                                           'selection-derived t)))
        (selection-batch--unregister-property-adapter adapter)))))

(ert-deftest selection-batch-signalling-trusted-refresh-validates-protected-state ()
  (dolist (mutation
           (list
            (lambda (_owner _other)
              (switch-to-buffer
               (get-buffer-create " *selection-batch-other*")))
            (lambda (_owner _other) (narrow-to-region 2 4))
            (lambda (_owner _other)
              (let ((inhibit-modification-hooks t)) (insert "!")))
            (lambda (_owner _other) (set-buffer-modified-p nil))
            (lambda (_owner _other)
              (setq buffer-undo-list (cons nil buffer-undo-list)))))
    (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
      (let* ((owner (current-buffer))
             (other (get-buffer-create " *selection-batch-other*"))
             (source (selection-batch-current-snapshot))
             (plan (selection-batch-plan-test--plan
                    source (list (selection-batch-plan-test--edit
                                  'a 0 2 3 "X" 2 3)) '((a 2 3))))
             (rollback-buffer nil)
             (refresh (lambda (&rest _)
                        (funcall mutation owner other)
                        (error "original trusted refresh failure")))
             (rollback (lambda () (setq rollback-buffer (current-buffer))))
             (adapter
              (selection-batch--register-property-adapter refresh rollback)))
        (unwind-protect
            (progn
              (add-hook 'after-change-functions
                        (lambda (&rest args)
                          (selection-batch--call-trusted-property-refresh
                           adapter refresh args))
                        0 t)
              (let ((error (should-error (selection-batch-apply-plan plan)
                                         :type 'error)))
                (should (string-match-p "changed protected state"
                                        (error-message-string error))))
              (should (eq rollback-buffer owner))
              (should (eq (current-buffer) owner))
              (should (equal "abcdef" (buffer-string))))
          (selection-batch--unregister-property-adapter adapter)
          (when (buffer-live-p other) (kill-buffer other)))))))

(ert-deftest selection-batch-signalling-trusted-refresh-preserves-original-error ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (refresh (lambda (&rest _) (error "original trusted failure")))
           (adapter (selection-batch--register-property-adapter refresh #'ignore)))
      (unwind-protect
          (progn
            (add-hook 'after-change-functions
                      (lambda (&rest args)
                        (selection-batch--call-trusted-property-refresh
                         adapter refresh args))
                      0 t)
            (let ((error (should-error (selection-batch-apply-plan plan))))
              (should (string-match-p "original trusted failure"
                                      (error-message-string error)))))
        (selection-batch--unregister-property-adapter adapter)))))

(ert-deftest selection-batch-trusted-refresh-validates-quit-and-throw ()
  (dolist (exit (list (lambda () (signal 'quit nil))
                      (lambda () (throw 'trusted-refresh-exit t))))
    (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
      (let* ((source (selection-batch-current-snapshot))
             (plan (selection-batch-plan-test--plan
                    source (list (selection-batch-plan-test--edit
                                  'a 0 2 3 "X" 2 3)) '((a 2 3))))
             (refresh (lambda (&rest _)
                        (set-buffer-modified-p nil)
                        (funcall exit)))
             (adapter (selection-batch--register-property-adapter
                       refresh #'ignore)))
        (unwind-protect
            (progn
              (add-hook 'after-change-functions
                        (lambda (&rest args)
                          (selection-batch--call-trusted-property-refresh
                           adapter refresh args))
                        0 t)
              (let ((error
                     (should-error
                      (catch 'trusted-refresh-exit
                        (selection-batch-apply-plan plan))
                      :type 'error)))
                (should (string-match-p "changed protected state"
                                        (error-message-string error))))
              (should (equal "abcdef" (buffer-string))))
          (selection-batch--unregister-property-adapter adapter))))))

(ert-deftest selection-batch-property-adapters-immutable-after-ledger-phase ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3))))
           (adapter (selection-batch--register-property-adapter #'ignore #'ignore))
           (original selection-batch--plan-install-result-function))
      (unwind-protect
          (dolist (operation
                   (list (lambda ()
                           (selection-batch--register-property-adapter
                            #'ignore #'ignore))
                         (lambda ()
                           (selection-batch--unregister-property-adapter adapter))))
            (let ((selection-batch--plan-install-result-function
                   (lambda (&rest arguments)
                     (should-not selection-batch--change-ledger)
                     (funcall operation)
                     (apply original arguments))))
              (should-error (selection-batch-apply-plan plan) :type 'error)
              (should (memq adapter selection-batch--property-adapters))
              (should (equal "abcdef" (buffer-string)))))
        (selection-batch--unregister-property-adapter adapter)))))

(ert-deftest selection-batch-unregistered-hook-cannot-nominate-property-refresh ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 3)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 3 "X" 2 3)) '((a 2 3)))))
      (add-hook
       'after-change-functions
       (lambda (&rest args)
         (selection-batch--call-trusted-property-refresh
          nil
          (lambda (&rest _)
            (with-silent-modifications
              (put-text-property 4 5 'read-only t)))
          args))
       0 t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal "abcdef" (buffer-string)))
      (should-not (text-property-any (point-min) (point-max) 'read-only t)))))

(ert-deftest selection-batch-hook-widened-edit-rolls-back-outside-narrowing ()
  (selection-batch-plan-test--with-session "0123456789" '((a 3 4)) 'a
    (narrow-to-region 2 7)
    (let* ((source (selection-batch-current-snapshot))
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 3 4 "X" 3 4)) '((a 3 4))))
           (changed nil))
      (add-hook 'after-change-functions
                (lambda (&rest _)
                  (unless changed
                    (setq changed t)
                    (save-restriction
                      (widen)
                      (goto-char (point-max))
                      (insert "!")))) nil t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (save-restriction
        (widen)
        (should (equal "0123456789" (buffer-string))))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-change-ledger-precedes-hostile-hook-depth ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 2)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 2 "X" 2 3)) '((a 2 3))))
           (changed nil))
      (add-hook 'before-change-functions
                (lambda (&rest _)
                  (unless changed
                    (setq changed t)
                    (save-excursion
                      (goto-char (point-max))
                      (insert "!"))))
                -200 t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal "abcdef" (buffer-string))))))

(ert-deftest selection-batch-change-ledger-restores-hook-narrowing ()
  (selection-batch-plan-test--with-session "0123456789" '((a 3 3)) 'a
    (narrow-to-region 2 7)
    (let* ((bounds (cons (point-min) (point-max)))
           (source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 3 3 "X" 3 4)) '((a 3 4)))))
      (add-hook 'after-change-functions (lambda (&rest _) (widen)) nil t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal bounds (cons (point-min) (point-max))))
      (save-restriction
        (widen)
        (should (equal "0123456789" (buffer-string)))))))

(ert-deftest selection-batch-change-ledger-preserves-observation-hook-sequence ()
  (selection-batch-plan-test--with-session "abcdef" '((a 2 4)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source (list (selection-batch-plan-test--edit
                                'a 0 2 4 "XYZ" 2 5)) '((a 2 5))))
           events)
      (add-hook 'before-change-functions
                (lambda (beginning end) (push (list 'before beginning end) events))
                nil t)
      (add-hook 'after-change-functions
                (lambda (beginning end old-length)
                  (push (list 'after beginning end old-length) events)) nil t)
      (selection-batch-apply-plan plan)
      (should (equal '((before 2 4) (after 2 2 2)
                       (before 2 2) (after 2 5 0))
                     (nreverse events))))))

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

(ert-deftest selection-batch-plan-empty-nonempty-collision-is-half-open ()
  (selection-batch-plan-test--with-session "abcdef" '((range 2 5) (point 3 3)) 'range
    (let ((source (selection-batch-current-snapshot)))
      (dolist (position '(2 3 4))
        (let ((collision
               (selection-batch-plan-test--plan
                source
                (list (selection-batch-plan-test--edit 'range 0 2 5 "R" 2 3)
                      (selection-batch-plan-test--edit
                       'point 1 position position "P" 3 4))
                '((range 2 3) (point 3 4)))))
          (should-error (selection-batch-validate-plan collision source)
                        :type 'user-error)))
      ;; A replacement is half-open [2,5): insertion at 5 is adjacent.
      (dolist (position '(1 5))
        (let ((adjacent
               (selection-batch-plan-test--plan
                source
                (list (selection-batch-plan-test--edit 'range 0 2 5 "R" 2 3)
                      (selection-batch-plan-test--edit
                       'point 1 position position "P" 3 4))
                '((range 2 3) (point 3 4)))))
          (should (eq adjacent (selection-batch-validate-plan adjacent source))))))))

(ert-deftest selection-batch-plan-read-only-insertion-obeys-boundary-stickiness ()
  (selection-batch-plan-test--with-session "abc" '((a 2 2)) 'a
    (let ((inhibit-read-only t))
      (put-text-property 1 2 'read-only t)
      (put-text-property 1 2 'rear-nonsticky '(read-only)))
    (let* ((source (selection-batch-current-snapshot))
           (allowed (selection-batch-plan-test--plan
                     source
                     (list (selection-batch-plan-test--edit 'a 0 2 2 "X" 2 3))
                     '((a 2 3)))))
      (should (eq allowed (selection-batch-validate-plan allowed source)))
      (selection-batch-apply-plan allowed)
      (should (equal "aXbc" (buffer-string)))))
  (selection-batch-plan-test--with-session "abc" '((a 2 2)) 'a
    (put-text-property 1 2 'read-only t)
    (let* ((source (selection-batch-current-snapshot))
           (forbidden (selection-batch-plan-test--plan
                       source
                       (list (selection-batch-plan-test--edit 'a 0 2 2 "X" 2 3))
                       '((a 2 3)))))
      (should-error (selection-batch-validate-plan forbidden source)
                    :type 'user-error))))

(ert-deftest selection-batch-signalling-register-commit-rolls-back-text-and-state ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2)) 'a
    (let* ((selection-batch-register '(:old "register"))
           (selection-batch-last-recipe '(:old "recipe"))
           (session selection-batch--session)
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  before
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2))
                  '((a 1 2)) nil '(:new "register") '(:new "recipe")))
           (watcher (lambda (_symbol new operation _where)
                      (when (and (eq operation 'set)
                                 (equal new '(:new "register")))
                        (error "injected register watcher failure")))))
      (add-variable-watcher 'selection-batch-register watcher)
      (unwind-protect
          (should-error (selection-batch-apply-plan plan) :type 'error)
        (remove-variable-watcher 'selection-batch-register watcher))
      (should (equal "abc" (buffer-string)))
      (should (eq session selection-batch--session))
      (should (equal '(:old "register") selection-batch-register))
      (should (equal '(:old "recipe") selection-batch-last-recipe))
      (should (equal (selection-batch-plan-test--triples before)
                     (selection-batch-plan-test--triples
                      (selection-batch-current-snapshot))))
      (should (eq 'set (selection-batch--session-state session))))))

(ert-deftest selection-batch-compensation-deep-copies-register-and-recipe ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2)) 'a
    (let* ((selection-batch-register (list :old (vector (copy-sequence "safe"))))
           (selection-batch-last-recipe (list :old (vector (copy-sequence "safe"))))
           (source (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  source
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2))
                  '((a 1 2))))
           (mutated nil)
           (selection-batch--plan-refresh-view-function
            (lambda (&rest _) (error "injected post-hook failure"))))
      (add-hook 'after-change-functions
                (lambda (&rest _)
                  (unless mutated
                    (setq mutated t)
                    (aset (aref (cadr selection-batch-register) 0) 0 ?X)
                    (aset (aref (cadr selection-batch-last-recipe) 0) 0 ?Y)))
                nil t)
      (should-error (selection-batch-apply-plan plan) :type 'error)
      (should (equal '(:old ["safe"]) selection-batch-register))
      (should (equal '(:old ["safe"]) selection-batch-last-recipe))
      (should (equal "abc" (buffer-string))))))

(ert-deftest selection-batch-mutating-watchers-fail-and-restoration-resists-recorruption ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2)) 'a
    (let* ((selection-batch-register (list :old (vector "register")))
           (selection-batch-last-recipe (list :old (vector "recipe")))
           (before (selection-batch-current-snapshot))
           (plan (selection-batch-plan-test--plan
                  before
                  (list (selection-batch-plan-test--edit 'a 0 1 2 "X" 1 2))
                  '((a 1 2)) nil
                  (list :new (vector "register"))
                  (list :new (vector "recipe"))))
           seen
           (watcher
            (lambda (symbol new operation _where)
              (when (eq operation 'set)
                (push (list symbol (selection-batch--plan-copy-value new)) seen)
                (when (and (consp new) (vectorp (cadr new)))
                  (aset (cadr new) 0 "corrupt"))))))
      (add-variable-watcher 'selection-batch-register watcher)
      (add-variable-watcher 'selection-batch-last-recipe watcher)
      (unwind-protect
          (should-error (selection-batch-apply-plan plan) :type 'error)
        (remove-variable-watcher 'selection-batch-register watcher)
        (remove-variable-watcher 'selection-batch-last-recipe watcher))
      (should (equal "abc" (buffer-string)))
      (should (equal '(:old ["register"]) selection-batch-register))
      (should (equal '(:old ["recipe"]) selection-batch-last-recipe))
      (should (cl-find 'selection-batch-register seen :key #'car))
      (should (cl-find 'selection-batch-last-recipe seen :key #'car)))))

(ert-deftest selection-batch-successful-watched-commit-equals-prepared-values ()
  (selection-batch-plan-test--with-session "abc" '((a 1 2)) 'a
    (let* ((source (selection-batch-current-snapshot))
           (new-register (list :new (vector "register")))
           (new-recipe (list :new (vector "recipe")))
           (plan (selection-batch-plan-test--plan
                  source nil '((a 1 2)) nil new-register new-recipe))
           seen
           (watcher (lambda (symbol new operation _where)
                      (when (eq operation 'set)
                        (push (cons symbol
                                    (selection-batch--plan-copy-value new)) seen)))))
      (add-variable-watcher 'selection-batch-register watcher)
      (add-variable-watcher 'selection-batch-last-recipe watcher)
      (unwind-protect
          (selection-batch-apply-plan plan)
        (remove-variable-watcher 'selection-batch-register watcher)
        (remove-variable-watcher 'selection-batch-last-recipe watcher))
      (should (equal new-register selection-batch-register))
      (should (equal new-recipe selection-batch-last-recipe))
      (should (equal new-register (cdr (assq 'selection-batch-register seen))))
      (should (equal new-recipe (cdr (assq 'selection-batch-last-recipe seen)))))))

(provide 'selection-batch-plan-test)
;;; selection-batch-plan-test.el ends here
