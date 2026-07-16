;;; selection-batch-core-test.el --- Core tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch-core)

(defun selection-batch-test--selection (id anchor cursor)
  (selection-batch-snapshot-selection-create
   :id id :anchor anchor :cursor cursor))

(defun selection-batch-test--snapshot (buffer triples &optional primary generation)
  (with-current-buffer buffer
    (selection-batch-snapshot-create
     :buffer buffer :buffer-tick (buffer-chars-modified-tick)
     :generation (or generation 0) :primary-id (or primary (caar triples))
     :narrowing (cons (point-min) (point-max))
     :selections
     (vconcat (mapcar (lambda (triple)
                        (apply #'selection-batch-test--selection triple))
                      triples)))))

(defmacro selection-batch-test--with-buffer (text &rest body)
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (insert ,text)
     (goto-char (point-min))
     (unwind-protect (progn ,@body)
       (when selection-batch--session
         (selection-batch--cleanup selection-batch--session nil t)))))

(defun selection-batch-test--triples (snapshot)
  (mapcar (lambda (selection)
            (list (selection-batch-snapshot-selection-id selection)
                  (selection-batch-snapshot-selection-anchor selection)
                  (selection-batch-snapshot-selection-cursor selection)))
          (append (selection-batch-snapshot-selections snapshot) nil)))

(ert-deftest selection-batch-value-model-derived-accessors ()
  (dolist (case '((2 5 2 5 t nil nil)
                  (5 2 2 5 nil t nil)
                  (3 3 3 3 t nil t)))
    (pcase-let ((`(,anchor ,cursor ,beginning ,end ,forward ,backward ,empty) case))
      (let ((selection (selection-batch-test--selection 7 anchor cursor)))
        (should (= beginning (selection-batch-selection-beginning selection)))
        (should (= end (selection-batch-selection-end selection)))
        (should (eq forward (selection-batch-selection-forward-p selection)))
        (should (eq backward (selection-batch-selection-backward-p selection)))
        (should (eq empty (selection-batch-selection-empty-p selection)))
        (should (= 7 (selection-batch-snapshot-selection-id selection)))))))

(ert-deftest selection-batch-snapshot-equality-is-by-value ()
  (selection-batch-test--with-buffer "abcdef"
    (let ((a (selection-batch-test--snapshot (current-buffer) '((1 2 5)) 1))
          (b (selection-batch-test--snapshot (current-buffer) '((1 2 5)) 1)))
      (should (equal a b))
      (should-not (eq a b)))))

(ert-deftest selection-batch-session-primary-is-projected-without-markers ()
  (selection-batch-test--with-buffer "abcdef"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((p 2 5) (s 3 6)) 'p))
    (let* ((session selection-batch--session)
           (primary (selection-batch--live-by-id session 'p))
           (secondary (selection-batch--live-by-id session 's)))
      (should (eq (current-buffer) (selection-batch--session-buffer session)))
      (should-not (selection-batch--live-selection-anchor-marker primary))
      (should-not (selection-batch--live-selection-cursor-marker primary))
      (should (markerp (selection-batch--live-selection-anchor-marker secondary)))
      (should (= 5 (point)))
      (should (= 2 (mark t)))
      (should mark-active)
      (should (equal '((p 2 5) (s 3 6))
                     (selection-batch-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-empty-primary-establishes-explicit-mark ()
  (selection-batch-test--with-buffer "abc"
    (goto-char 2)
    (set-marker (mark-marker) nil)
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((p 2 2)) 'p) t)
    (should (= 2 (mark t)))
    (should mark-active)))

(ert-deftest selection-batch-unset-installed-primary-mark-is-invariant-error ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((p 2 2) (s 1 2)) 'p) t)
    (set-marker (mark-marker) nil)
    (should-error (selection-batch-current-snapshot) :type 'user-error)
    (should-not selection-batch--session)))

(ert-deftest selection-batch-primary-rotation-rehomes-markers ()
  (selection-batch-test--with-buffer "abcdef"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 4 6)) 'a))
    (selection-batch-apply-transform #'selection-batch-transform-rotate-primary)
    (let ((a (selection-batch--live-by-id selection-batch--session 'a))
          (b (selection-batch--live-by-id selection-batch--session 'b)))
      (should (markerp (selection-batch--live-selection-anchor-marker a)))
      (should-not (selection-batch--live-selection-anchor-marker b))
      (should (= 6 (point)))
      (should (= 4 (mark t))))))

(ert-deftest selection-batch-projection-refuses-foreign-current-buffer ()
  (selection-batch-test--with-buffer "abc"
    (let ((owner (current-buffer)))
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot owner '((a 1 2)) 'a))
      (with-temp-buffer
        (should-error
         (selection-batch--project-primary selection-batch--session 1 1)
         :type 'user-error))
      (should (eq owner (selection-batch--session-buffer selection-batch--session))))))

(ert-deftest selection-batch-normalization-table ()
  (selection-batch-test--with-buffer "abcdefghij"
    (dolist (case
             '((duplicate ((a 1 3) (b 1 3)) a reject ((a 1 3)) a)
               (adjacent ((a 1 3) (b 3 5)) a reject ((a 1 3) (b 3 5)) a)
               (merge ((a 1 5) (b 3 7)) a merge ((a 1 7)) a)
               (nested ((a 1 8) (b 3 5)) b merge ((b 1 8)) b)
               (duplicate-primary ((a 1 3) (b 1 3)) b reject ((b 1 3)) b)))
      (pcase-let ((`(,_ ,triples ,primary ,policy ,expected ,expected-primary) case))
        (let* ((input (selection-batch-test--snapshot
                       (current-buffer) triples primary))
               (original (copy-tree (selection-batch-test--triples input)))
               (result (selection-batch-normalize-snapshot input policy)))
          (should (equal expected (selection-batch-test--triples result)))
          (should (equal expected-primary
                         (selection-batch-snapshot-primary-id result)))
          (should (equal original (selection-batch-test--triples input))))))))

(ert-deftest selection-batch-normalization-rejects-overlap-and-empty-set ()
  (selection-batch-test--with-buffer "abcdefghij"
    (should-error
     (selection-batch-normalize-snapshot
      (selection-batch-test--snapshot (current-buffer) '((a 1 5) (b 2 3)) 'a)
      'reject)
     :type 'user-error)
    (let ((old (selection-batch-test--snapshot (current-buffer) '((a 1 2)) 'a)))
      (selection-batch-install-snapshot old)
      (should-error (selection-batch--filtered-snapshot old nil) :type 'user-error)
      (should (equal '((a 1 2))
                     (selection-batch-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-filter-primary-inherits-next-then-previous ()
  (selection-batch-test--with-buffer "abcdef"
    (let* ((snapshot (selection-batch-test--snapshot
                      (current-buffer) '((a 1 2) (b 2 3) (c 3 4)) 'b))
           (next (selection-batch--filtered-snapshot
                  snapshot (list (aref (selection-batch-snapshot-selections snapshot) 0)
                                 (aref (selection-batch-snapshot-selections snapshot) 2))))
           (previous (selection-batch--filtered-snapshot
                      snapshot (list (aref (selection-batch-snapshot-selections snapshot) 0)))))
      (should (eq 'c (selection-batch-snapshot-primary-id next)))
      (should (eq 'a (selection-batch-snapshot-primary-id previous))))))

(ert-deftest selection-batch-cleanup-collapse-and-cancel-policies ()
  (selection-batch-test--with-buffer "abcdef"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 2 4) (b 4 6)) 'a))
    (let ((marker (selection-batch--live-selection-anchor-marker
                   (selection-batch--live-by-id selection-batch--session 'b))))
      (selection-batch-collapse)
      (should-not selection-batch--session)
      (should-not (marker-buffer marker))
      (should mark-active)
      (should (= 2 (mark t)))
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot (current-buffer) '((a 2 4)) 'a))
      (selection-batch-cancel)
      (should-not mark-active))))

(ert-deftest selection-batch-cleanup-is-idempotent ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2)) 'a))
    (let ((session selection-batch--session))
      (selection-batch--cleanup session nil t)
      (selection-batch--cleanup session nil t)
      (should-not selection-batch--session))))

(ert-deftest selection-batch-stale-secondary-marker-cleans-session ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
    (set-marker (selection-batch--live-selection-anchor-marker
                 (selection-batch--live-by-id selection-batch--session 'b)) nil)
    (should-error (selection-batch-current-snapshot) :type 'user-error)
    (should-not selection-batch--session)))

(ert-deftest selection-batch-buffer-lifecycle-hooks-clean ()
  (dolist (hook '(before-revert-hook change-major-mode-hook))
    (selection-batch-test--with-buffer "abc"
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
      (run-hooks hook)
      (should-not selection-batch--session)))
  (let ((buffer (generate-new-buffer " *selection-batch-kill*")) marker)
    (with-current-buffer buffer
      (insert "abc")
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot buffer '((a 1 2) (b 2 3)) 'a))
      (setq marker (selection-batch--live-selection-anchor-marker
                    (selection-batch--live-by-id selection-batch--session 'b))))
    (kill-buffer buffer)
    (should-not selection-batch--session)
    (should-not (marker-buffer marker))))

(ert-deftest selection-batch-provider-region-contract ()
  (selection-batch-test--with-buffer "abcdef"
    (goto-char 5) (set-mark 2) (setq mark-active t)
    (let ((result (selection-batch-provider-region)))
      (should (equal '((0 2 5))
                     (selection-batch-test--triples
                      (selection-batch-provider-snapshot result)))))
    (setq mark-active nil)
    (should-error (selection-batch-provider-region) :type 'user-error)
    (should (equal '((0 5 5))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-region t)))))))

(ert-deftest selection-batch-provider-same-text-directions ()
  (selection-batch-test--with-buffer "foo x foo y foo"
    (should (equal '((0 1 4) (1 7 10) (2 13 16))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-same-text "foo" 'all)))))
    (should (equal '((1 7 10))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-same-text "foo" 'next 5)))))
    (should (equal '((1 7 10))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-same-text "foo" 'previous 12)))))))

(ert-deftest selection-batch-provider-regexp-region-zero-width-and-no-match ()
  (selection-batch-test--with-buffer "ab ab"
    (goto-char 3) (set-mark 1) (setq mark-active t)
    (should (equal '((0 1 3))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-regexp "a." 'region)))))
    (let ((empty (selection-batch-provider-regexp "\\_<" 'accessible)))
      (should (> (length (selection-batch-provider-result-selections empty)) 0))
      (dolist (selection (append (selection-batch-provider-result-selections empty) nil))
        (should (selection-batch-selection-empty-p selection))))
    (let ((old (selection-batch-test--snapshot (current-buffer) '((old 1 2)) 'old)))
      (selection-batch-install-snapshot old)
      (should-error
       (selection-batch-provider-snapshot
        (selection-batch-provider-regexp "z+" 'accessible))
       :type 'user-error)
      (should (equal '((old 1 2))
                     (selection-batch-test--triples
                      (selection-batch-current-snapshot)))))))

(ert-deftest selection-batch-providers-respect-narrowing-and-multibyte ()
  (selection-batch-test--with-buffer "外 日本 外 日本"
    (narrow-to-region 6 (point-max))
    (let ((matches (selection-batch-provider-same-text "日本" 'all)))
      (should (equal '((0 8 10))
                     (selection-batch-test--triples
                      (selection-batch-provider-snapshot matches)))))))

(ert-deftest selection-batch-provider-lines-final-line-without-newline ()
  (selection-batch-test--with-buffer "aa\nbb"
    (should (equal '((0 1 3) (1 4 6))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-lines)))))))

(ert-deftest selection-batch-transformers-keep-drop-reverse-merge ()
  (selection-batch-test--with-buffer "foo xx bar yy"
    (let ((snapshot (selection-batch-test--snapshot
                     (current-buffer) '((a 1 4) (b 5 7) (c 8 11)) 'b)))
      (should (equal '((a 1 4) (c 8 11))
                     (selection-batch-test--triples
                      (selection-batch-transform-keep-regexp snapshot "[a-z]\\{3\\}"))))
      (should (equal '((b 5 7))
                     (selection-batch-test--triples
                      (selection-batch-transform-drop-regexp snapshot "[a-z]\\{3\\}"))))
      (should (equal '((a 4 1) (b 7 5) (c 11 8))
                     (selection-batch-test--triples
                      (selection-batch-transform-reverse snapshot)))))
    (let ((overlap (selection-batch-test--snapshot
                    (current-buffer) '((a 1 5) (b 3 7)) 'b)))
      (should (equal '((b 1 7))
                     (selection-batch-test--triples
                      (selection-batch-transform-merge overlap)))))))

(ert-deftest selection-batch-transform-split-lines ()
  (selection-batch-test--with-buffer "aa\nbb\ncc"
    (let ((result (selection-batch-transform-split-lines
                   (selection-batch-test--snapshot
                    (current-buffer) '((a 1 6)) 'a))))
      (should (equal '((a 1 3) ("split-0" 4 6))
                     (selection-batch-test--triples result))))))

(ert-deftest selection-batch-rotate-primary-forward-and-backward ()
  (selection-batch-test--with-buffer "abc"
    (let* ((snapshot (selection-batch-test--snapshot
                      (current-buffer) '((a 1 1) (b 2 2) (c 3 3)) 'a))
           (forward (selection-batch-transform-rotate-primary snapshot))
           (backward (selection-batch-transform-rotate-primary snapshot t)))
      (should (eq 'b (selection-batch-snapshot-primary-id forward)))
      (should (eq 'c (selection-batch-snapshot-primary-id backward))))))

(ert-deftest selection-batch-history-noop-failure-and-redo-clearing ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
    (selection-batch-apply-transform #'identity)
    (should-not (selection-batch--session-history selection-batch--session))
    (should-error
     (selection-batch-apply-transform
      (lambda (_snapshot) (user-error "failed")))
     :type 'user-error)
    (should-not (selection-batch--session-history selection-batch--session))
    (selection-batch-apply-transform #'selection-batch-transform-reverse)
    (selection-batch-selection-undo)
    (should (selection-batch--session-redo selection-batch--session))
    (selection-batch-apply-transform #'selection-batch-transform-rotate-primary)
    (should-not (selection-batch--session-redo selection-batch--session))))

(ert-deftest selection-batch-history-is-bounded-and-integer-only ()
  (selection-batch-test--with-buffer "abc"
    (let ((selection-batch-history-limit 2))
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
      (dotimes (_ 3)
        (selection-batch-apply-transform #'selection-batch-transform-rotate-primary))
      (should (= 2 (length (selection-batch--session-history selection-batch--session))))
      (dolist (snapshot (selection-batch--session-history selection-batch--session))
        (dolist (selection (append (selection-batch-snapshot-selections snapshot) nil))
          (should (integerp (selection-batch-snapshot-selection-anchor selection)))
          (should (integerp (selection-batch-snapshot-selection-cursor selection))))
        (should-not (cl-some #'markerp (flatten-tree snapshot)))))))

(ert-deftest selection-batch-history-rejects-noninteger-limit ()
  (selection-batch-test--with-buffer "abc"
    (let ((selection-batch-history-limit 1.5))
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
      (should-error
       (selection-batch-apply-transform #'selection-batch-transform-rotate-primary)
       :type 'user-error)
      (should-not (selection-batch--session-history selection-batch--session)))))

(ert-deftest selection-batch-history-undo-redo-roundtrip ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2) (b 2 3)) 'a))
    (selection-batch-apply-transform #'selection-batch-transform-reverse)
    (should (equal '((a 2 1) (b 3 2))
                   (selection-batch-test--triples (selection-batch-current-snapshot))))
    (selection-batch-selection-undo)
    (should (equal '((a 1 2) (b 2 3))
                   (selection-batch-test--triples (selection-batch-current-snapshot))))
    (selection-batch-selection-redo)
    (should (equal '((a 2 1) (b 3 2))
                   (selection-batch-test--triples (selection-batch-current-snapshot))))))

(ert-deftest selection-batch-public-snapshot-slots-are-read-only ()
  (let ((selection (selection-batch-test--selection 'a 1 2)))
    (should-error
     (eval `(setf (selection-batch-snapshot-selection-anchor ,selection) 9)))))

(ert-deftest selection-batch-normalization-merges-transitive-overlap-chain ()
  (selection-batch-test--with-buffer "abcdefghijklmnop"
    (let ((result
           (selection-batch-normalize
            (selection-batch-test--snapshot
             (current-buffer) '((wide 1 11) (nested 2 4) (tail 10 14)) 'tail)
            'merge)))
      (should (equal '((tail 1 14))
                     (selection-batch-test--triples
                      (selection-batch-normalization-snapshot result))))
      (should (equal '(wide nested tail)
                     (plist-get (selection-batch-normalization-diagnostics result)
                                :merged-ids))))))

(ert-deftest selection-batch-install-replaces-the-single-owner-safely ()
  (let ((first (generate-new-buffer " *selection-first*"))
        (second (generate-new-buffer " *selection-second*"))
        old-marker)
    (unwind-protect
        (progn
          (with-current-buffer first
            (insert "abc")
            (selection-batch-install-snapshot
             (selection-batch-test--snapshot first '((a 1 2) (b 2 3)) 'a))
            (setq old-marker
                  (selection-batch--live-selection-anchor-marker
                   (selection-batch--live-by-id selection-batch--session 'b))))
          (with-current-buffer second
            (insert "xyz")
            (selection-batch-install-snapshot
             (selection-batch-test--snapshot second '((x 1 2)) 'x)))
          (should (eq second (selection-batch--session-buffer selection-batch--session)))
          (should-not (marker-buffer old-marker)))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (kill-buffer first)
      (kill-buffer second))))

(ert-deftest selection-batch-cleanup-destroys-derived-artifacts-once ()
  (selection-batch-test--with-buffer "abc"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer) '((a 1 2)) 'a))
    (let ((overlay (make-overlay 1 2))
          (calls 0)
          (session selection-batch--session))
      (setf (selection-batch--session-overlays session) (list overlay)
            (selection-batch--session-transient-exit-function session)
            (lambda () (setq calls (1+ calls))))
      (selection-batch--cleanup session nil t)
      (selection-batch--cleanup session nil t)
      (should-not (overlay-buffer overlay))
      (should (= 1 calls)))))

(ert-deftest selection-batch-transform-refresh-failure-restores-live-state ()
  (selection-batch-test--with-buffer "abcdef"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer)
                                     '((primary 1 3) (secondary 4 6)) 'primary))
    (let* ((session selection-batch--session)
           (before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (old-generation (selection-batch--session-generation session))
           candidate-live)
      (cl-letf (((symbol-value 'selection-batch--view-refresh-function)
                 (lambda (candidate)
                   (unless candidate-live
                     (setq candidate-live
                           (selection-batch--session-selections candidate)))
                   (error "injected refresh failure"))))
        (should-error
         (selection-batch-apply-transform #'selection-batch-transform-reverse)
         :type 'error))
      (should (eq session selection-batch--session))
      (should (eq old-live (selection-batch--session-selections session)))
      (should (= old-generation (selection-batch--session-generation session)))
      (should (equal before (selection-batch-current-snapshot)))
      (should-not (selection-batch--session-history session))
      (dolist (selection (append candidate-live nil))
        (dolist (marker (list (selection-batch--live-selection-anchor-marker selection)
                              (selection-batch--live-selection-cursor-marker selection)))
          (when (markerp marker) (should-not (marker-buffer marker))))))))

(ert-deftest selection-batch-initial-install-refresh-failure-leaves-no-zombie ()
  (selection-batch-test--with-buffer "abcdef"
    (let (candidate marker)
      (cl-letf (((symbol-value 'selection-batch--view-refresh-function)
                 (lambda (session)
                   (setq candidate session
                         marker (selection-batch--live-selection-anchor-marker
                                 (selection-batch--live-by-id session 'secondary)))
                   (error "injected refresh failure"))))
        (should-error
         (selection-batch-install-snapshot
          (selection-batch-test--snapshot (current-buffer)
                                          '((primary 1 3) (secondary 4 6)) 'primary))
         :type 'error))
      (should candidate)
      (should-not selection-batch--session)
      (should-not (marker-buffer marker))
      (dolist (hook '(kill-buffer-hook before-revert-hook change-major-mode-hook))
        (should-not (memq #'selection-batch--lifecycle-exit (symbol-value hook)))))))

(ert-deftest selection-batch-replacement-refresh-failure-restores-old-owner ()
  (let ((old-buffer (generate-new-buffer " *selection-old-owner*"))
        (new-buffer (generate-new-buffer " *selection-new-owner*"))
        old-session old-snapshot old-marker candidate-marker)
    (unwind-protect
        (progn
          (with-current-buffer old-buffer
            (insert "abcdef")
            (selection-batch-install-snapshot
             (selection-batch-test--snapshot
              old-buffer '((old 1 3) (old-secondary 4 6)) 'old))
            (setq old-session selection-batch--session
                  old-snapshot (selection-batch-current-snapshot)
                  old-marker (selection-batch--live-selection-anchor-marker
                              (selection-batch--live-by-id old-session 'old-secondary))))
          (with-current-buffer new-buffer
            (insert "uvwxyz")
            (cl-letf (((symbol-value 'selection-batch--view-refresh-function)
                       (lambda (session)
                         (setq candidate-marker
                               (selection-batch--live-selection-anchor-marker
                                (selection-batch--live-by-id session 'new-secondary)))
                         (error "injected refresh failure"))))
              (should-error
               (selection-batch-install-snapshot
                (selection-batch-test--snapshot
                 new-buffer '((new 1 3) (new-secondary 4 6)) 'new))
               :type 'error)))
          (should (eq old-session selection-batch--session))
          (with-current-buffer old-buffer
            (should (equal old-snapshot (selection-batch-current-snapshot)))
            (should (memq #'selection-batch--lifecycle-exit kill-buffer-hook)))
          (should (marker-buffer old-marker))
          (should-not (marker-buffer candidate-marker)))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (kill-buffer old-buffer)
      (kill-buffer new-buffer))))

(ert-deftest selection-batch-cleanup-continues-after-view-destroy-error ()
  (selection-batch-test--with-buffer "abcdef"
    (selection-batch-install-snapshot
     (selection-batch-test--snapshot (current-buffer)
                                     '((primary 1 3) (secondary 4 6)) 'primary))
    (let* ((session selection-batch--session)
           (marker (selection-batch--live-selection-anchor-marker
                    (selection-batch--live-by-id session 'secondary)))
           (overlay (make-overlay 1 2))
           (exit-calls 0))
      (setf (selection-batch--session-overlays session) (list overlay)
            (selection-batch--session-transient-exit-function session)
            (lambda () (setq exit-calls (1+ exit-calls))))
      (cl-letf (((symbol-value 'selection-batch--view-destroy-function)
                 (lambda (_candidate) (error "injected destroy failure"))))
        (should-error (selection-batch--cleanup session nil t) :type 'error))
      (should-not selection-batch--session)
      (should-not (marker-buffer marker))
      (should-not (overlay-buffer overlay))
      (should (= 1 exit-calls))
      (dolist (hook '(kill-buffer-hook before-revert-hook change-major-mode-hook))
        (should-not (memq #'selection-batch--lifecycle-exit (symbol-value hook)))))))

(ert-deftest selection-batch-empty-regexp-terminates-at-character-boundaries ()
  (selection-batch-test--with-buffer "日本"
    (let ((result (selection-batch-provider-regexp "" 'accessible)))
      (should (equal '((0 1 1) (1 2 2) (2 3 3))
                     (selection-batch-test--triples
                      (selection-batch-provider-snapshot result)))))))

(ert-deftest selection-batch-split-lines-preserves-source-ids-and-direction ()
  (selection-batch-test--with-buffer "aa\nbb xx\nyy"
    (let ((result
           (selection-batch-transform-split-lines
            (selection-batch-test--snapshot
             (current-buffer) '((a 1 6) (b 11 7)) 'b))))
      (should (equal '((a 1 3) ("split-0" 4 6)
                       (b 9 7) ("split-1" 11 10))
                     (selection-batch-test--triples result)))
      (should (eq 'b (selection-batch-snapshot-primary-id result))))))

(ert-deftest selection-batch-split-lines-does-not-collide-with-existing-ids ()
  (selection-batch-test--with-buffer "aa\nbb\ncc"
    (let* ((snapshot (selection-batch-test--snapshot
                      (current-buffer) '((a 1 6) ("split-0" 7 9)) 'a))
           (result (selection-batch-transform-split-lines snapshot))
           (ids (mapcar #'selection-batch-snapshot-selection-id
                        (append (selection-batch-snapshot-selections result) nil))))
      (should (equal '(a "split-1" "split-0") ids))
      (should (= (length ids) (length (delete-dups (copy-sequence ids))))))))

(ert-deftest selection-batch-normalization-empty-does-not-break-overlap-group ()
  (selection-batch-test--with-buffer "abcdefghij"
    (let ((snapshot (selection-batch-test--snapshot
                     (current-buffer) '((a 1 6) (empty 3 3) (b 4 8)) 'a)))
      (should-error (selection-batch-normalize-snapshot snapshot 'reject)
                    :type 'user-error)
      (should (equal '((a 1 8) (empty 3 3))
                     (selection-batch-test--triples
                      (selection-batch-normalize-snapshot snapshot 'merge)))))))

(ert-deftest selection-batch-snapshot-defensively-copies-compound-slots ()
  (selection-batch-test--with-buffer "abcdef"
    (let* ((selection (selection-batch-test--selection 'a 1 3))
           (input-selections (vector selection))
           (input-narrowing (cons 1 7))
           (snapshot (selection-batch-snapshot-create
                      :buffer (current-buffer) :buffer-tick 0 :generation 0
                      :primary-id 'a :narrowing input-narrowing
                      :selections input-selections)))
      ;; Mutating constructor arguments cannot alter the snapshot.
      (aset input-selections 0 (selection-batch-test--selection 'bad 2 4))
      (setcar input-narrowing 2)
      (should (equal '((a 1 3)) (selection-batch-test--triples snapshot)))
      (should (equal '(1 . 7) (selection-batch-snapshot-narrowing snapshot)))
      ;; Nor can mutating values returned by public accessors.
      (let ((exposed-selections (selection-batch-snapshot-selections snapshot))
            (exposed-narrowing (selection-batch-snapshot-narrowing snapshot)))
        (aset exposed-selections 0 (selection-batch-test--selection 'bad 3 5))
        (setcdr exposed-narrowing 6))
      (should (equal '((a 1 3)) (selection-batch-test--triples snapshot)))
      (should (equal '(1 . 7) (selection-batch-snapshot-narrowing snapshot))))))

(ert-deftest selection-batch-split-lines-obeys-half-open-end ()
  (selection-batch-test--with-buffer "aa\nbb"
    (let ((result (selection-batch-transform-split-lines
                   (selection-batch-test--snapshot
                    (current-buffer) '((a 1 4)) 'a))))
      (should (equal '((a 1 3)) (selection-batch-test--triples result))))))

(ert-deftest selection-batch-same-text-previous-includes-match-ending-at-origin ()
  (selection-batch-test--with-buffer "foo bar foo"
    (should (equal '((0 1 4))
                   (selection-batch-test--triples
                    (selection-batch-provider-snapshot
                     (selection-batch-provider-same-text "foo" 'previous 4)))))))

(ert-deftest selection-batch-snapshot-deep-copies-compound-identifiers ()
  (selection-batch-test--with-buffer "abc"
    (let* ((id (list 'compound (vector (copy-sequence "id"))))
           (snapshot (selection-batch-snapshot-create
                      :buffer (current-buffer) :buffer-tick 0 :generation 0
                      :primary-id id :narrowing (cons 1 4)
                      :selections
                      (vector (selection-batch-test--selection id 1 2)))))
      (aset (aref (cadr id) 0) 0 ?X)
      (let* ((exposed (aref (selection-batch-snapshot-selections snapshot) 0))
             (exposed-id (selection-batch-snapshot-selection-id exposed))
             (exposed-primary (selection-batch-snapshot-primary-id snapshot)))
        (aset (aref (cadr exposed-id) 0) 0 ?Y)
        (aset (aref (cadr exposed-primary) 0) 0 ?Z))
      (should (equal '(compound ["id"])
                     (selection-batch-snapshot-primary-id snapshot)))
      (should (equal '(compound ["id"])
                     (selection-batch-snapshot-selection-id
                      (aref (selection-batch-snapshot-selections snapshot) 0)))))))

(ert-deftest selection-batch-dead-owner-is-pruned-before-query-and-first-install ()
  (let ((dead (generate-new-buffer " *selection-batch-dead-owner*")))
    (with-current-buffer dead
      (insert "abc")
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot dead '((a 1 2) (b 2 3)) 'a))
      (remove-hook 'kill-buffer-hook #'selection-batch--lifecycle-exit t))
    (kill-buffer dead)
    (should-not (selection-batch-active-p))
    (should-not selection-batch--session)
    (selection-batch-test--with-buffer "xy"
      (selection-batch-install-snapshot
       (selection-batch-test--snapshot (current-buffer) '((x 1 2)) 'x))
      (should (selection-batch-active-p)))))

(provide 'selection-batch-core-test)
;;; selection-batch-core-test.el ends here
