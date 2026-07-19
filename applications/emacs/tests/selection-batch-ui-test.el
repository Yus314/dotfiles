;;; selection-batch-ui-test.el --- UI tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch-ui)
(require 'selection-batch-plan)

(defun selection-batch-ui-test--snapshot (buffer triples primary)
  (with-current-buffer buffer
    (selection-batch-snapshot-create
     :buffer buffer :buffer-tick (buffer-chars-modified-tick)
     :generation 0 :primary-id primary :narrowing (cons (point-min) (point-max))
     :selections
     (vconcat
      (mapcar (lambda (triple)
                (apply #'selection-batch-snapshot-selection-create
                       (cl-mapcan (lambda (key value) (list key value))
                                  '(:id :anchor :cursor) triple)))
              triples)))))

(defmacro selection-batch-ui-test--with-session (text triples primary &rest body)
  (declare (indent 3) (debug t))
  `(with-temp-buffer
     (insert ,text)
     (goto-char (point-min))
     (unwind-protect
         (progn
           (selection-batch-install-snapshot
            (selection-batch-ui-test--snapshot
             (current-buffer) ,triples ,primary) t)
           ,@body)
       (when selection-batch--session
         (selection-batch--cleanup selection-batch--session nil t)))))

(ert-deftest selection-batch-view-renders-secondary-ranges-and-directed-cursors ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 3) (forward 3 5) (backward 5 3) (caret 6 6)) 'primary
    (let* ((overlays (selection-batch--session-overlays selection-batch--session))
           (ranges (cl-remove-if-not
                    (lambda (overlay)
                      (eq 'range (overlay-get overlay 'selection-batch-role)))
                    overlays))
           (cursors (cl-remove-if-not
                     (lambda (overlay)
                       (eq 'cursor (overlay-get overlay 'selection-batch-role)))
                     overlays)))
      (should (= 2 (length ranges)))
      (should (= 3 (length cursors)))
      (should (equal '((5 . 6) (3 . 4) (6 . 7))
                     (mapcar (lambda (overlay)
                               (cons (overlay-start overlay) (overlay-end overlay)))
                             cursors)))
      (dolist (range ranges)
        (should (equal '(3 . 5) (cons (overlay-start range) (overlay-end range))))
        (should (eq 'selection-batch-secondary (overlay-get range 'face))))
      (dolist (overlay overlays)
        (should (equal selection-batch--overlay-priority
                       (overlay-get overlay 'priority)))))))

(ert-deftest selection-batch-fallback-uses-after-string-only-at-eol-and-eof ()
  (selection-batch-ui-test--with-session
      "ab\ncd" '((primary 1 2) (inline 2 2) (eol 3 3) (eof 6 6)) 'primary
    (let ((cursors (selection-batch--session-overlays selection-batch--session)))
      (should (= 3 (length cursors)))
      (let ((inline (nth 0 cursors)) (eol (nth 1 cursors)) (eof (nth 2 cursors)))
        (should (equal '(2 . 3) (cons (overlay-start inline) (overlay-end inline))))
        (should (eq 'selection-batch-secondary-cursor (overlay-get inline 'face)))
        (should-not (overlay-get inline 'after-string))
        (dolist (overlay (list eol eof))
          (should (= (overlay-start overlay) (overlay-end overlay)))
          (should (stringp (overlay-get overlay 'after-string))))))))

(ert-deftest selection-batch-native-api-receives-all-directed-secondary-endpoints ()
  (let ((buffer (generate-new-buffer " *selection-native*"))
        (window (selected-window)) calls)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (candidate cursors)
                         (push (list candidate
                                     (mapcar #'marker-position cursors)) calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (forward 3 5) (backward 5 3) (empty 6 6))
                'primary) t)
              (should (equal (list window '(5 3 6)) (car calls)))
              ;; Only range highlighting remains in the native backend.
              (should (= 2 (length (selection-batch--session-overlays
                                    selection-batch--session))))
              (should (cl-every
                       (lambda (overlay)
                         (eq 'range (overlay-get overlay 'selection-batch-role)))
                       (selection-batch--session-overlays selection-batch--session)))
              (selection-batch-collapse)
              (should (equal (list window nil) (car calls)))
              (should-not selection-batch--installed-window-cursors))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer))))

(ert-deftest selection-batch-native-deleted-window-drops-ledger ()
  (let ((buffer (generate-new-buffer " *selection-native-delete*"))
        (first (selected-window)) extra calls)
    (unwind-protect
        (progn
          (setq extra (split-window first nil 'right))
          (set-window-buffer extra buffer)
          (select-window extra)
          (with-current-buffer buffer
            (insert "abc")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (window cursors)
                         (push (list window (mapcar #'marker-position cursors)) calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 2 3)) 'primary) t)
              (select-window first)
              (delete-window extra)
              (setq extra nil)
              (selection-batch--reconcile-window-cursors)
              (should-not selection-batch--installed-window-cursors)
              (should selection-batch--session)
              (selection-batch-collapse-owner))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (when (window-live-p extra) (delete-window extra))
      (when (window-live-p first)
        (select-window first)
        (set-window-buffer first (get-buffer-create "*scratch*")))
      (kill-buffer buffer))))

(ert-deftest selection-batch-native-window-switch-and-buffer-replacement-clean-up ()
  (let ((buffer (generate-new-buffer " *selection-native-owner*"))
        (foreign (generate-new-buffer " *selection-native-foreign*"))
        (first (selected-window)) second calls)
    (unwind-protect
        (progn
          (setq second (split-window first nil 'right))
          (set-window-buffer first buffer)
          (set-window-buffer second buffer)
          (select-window first)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (window cursors)
                         (push (list window (mapcar #'marker-position cursors)) calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
              (select-window second)
              (selection-batch--reconcile-window-cursors)
              (should (equal (list second '(5)) (car calls)))
              (should (member (list first nil) calls))
              (set-window-buffer second foreign)
              (selection-batch--reconcile-window-cursors)
              (should (equal (list second nil) (car calls)))
              (should-not selection-batch--installed-window-cursors)
              (let ((derived (copy-sequence
                              (selection-batch--session-overlays
                               selection-batch--session))))
                (selection-batch-collapse-owner)
                (dolist (overlay derived) (should-not (overlay-buffer overlay)))
                (should-not (cl-find-if
                             (lambda (overlay)
                               (overlay-get overlay 'selection-batch-view))
                             (overlays-in (point-min) (point-max))))))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (when (window-live-p second) (delete-window second))
      (when (window-live-p first)
        (select-window first)
        (set-window-buffer first (get-buffer-create "*scratch*")))
      (kill-buffer buffer)
      (kill-buffer foreign))))

(ert-deftest selection-batch-native-reconcile-keeps-lifetime-and-stable-fast-path ()
  (let ((buffer (generate-new-buffer " *selection-native-reconcile*"))
        (foreign (generate-new-buffer " *selection-native-away*"))
        (window (selected-window)) calls installed)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (candidate cursors)
                         (setq installed cursors)
                         (push (list candidate
                                     (mapcar #'marker-position cursors)) calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
              (let ((initial-call-count (length calls)))
                ;; Stable post-command reconciliation must not call the setter.
                (selection-batch--reconcile-window-cursors)
                (should (= initial-call-count (length calls)))
                ;; Native marker endpoints track edits without reinstalling.
                (goto-char 1)
                (insert "X")
                (should (equal '(6) (mapcar #'marker-position installed)))
                (selection-batch--reconcile-window-cursors)
                (should (= initial-call-count (length calls))))
              ;; Leaving clears ownership, but the live native-capable session
              ;; keeps reconciliation hooks so returning can reinstall it.
              (set-window-buffer window foreign)
              (selection-batch--reconcile-window-cursors)
              (should-not selection-batch--installed-window-cursors)
              (should selection-batch--window-cursor-hooks-installed-p)
              (should (memq #'selection-batch--reconcile-window-cursors
                            post-command-hook))
              (let ((away-call-count (length calls)))
                (selection-batch--reconcile-window-cursors)
                (should (= away-call-count (length calls))))
              (set-window-buffer window buffer)
              (selection-batch--reconcile-window-cursors)
              (should (equal (list window '(6)) (car calls)))
              (should selection-batch--installed-window-cursors)
              (selection-batch-collapse-owner)
              (should-not selection-batch--window-cursor-hooks-installed-p))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer)
      (kill-buffer foreign))))

(ert-deftest selection-batch-native-refresh-setter-error-is-transactional ()
  (let ((buffer (generate-new-buffer " *selection-native-error*"))
        (window (selected-window))
        fail native-state)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (_window cursors)
                         ;; Mutate first, then fail once: the adapter must use
                         ;; its old ledger to compensate the hostile setter.
                         (setq native-state cursors)
                         (when fail
                           (setq fail nil)
                           (error "hostile native setter")))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
              (let ((old-overlays
                     (selection-batch--session-overlays selection-batch--session))
                    (old-ledger selection-batch--installed-window-cursors)
                    (old-native native-state))
                (setq fail t)
                (should-error
                 (selection-batch--view-refresh selection-batch--session)
                 :type 'error)
                ;; No ledger was committed and no old view was deleted.
                (should (eq old-ledger selection-batch--installed-window-cursors))
                (should (eq old-overlays
                            (selection-batch--session-overlays
                             selection-batch--session)))
                (should (eq old-native native-state))
                (dolist (overlay old-overlays)
                  (should (overlay-buffer overlay)))
                ;; The failed refresh's provisional overlays were all swept.
                (should (equal old-overlays
                               (cl-remove-if-not
                                (lambda (overlay)
                                  (overlay-get overlay 'selection-batch-view))
                                (overlays-in (point-min) (point-max))))))
                (selection-batch-collapse-owner))))
      (setq fail nil)
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer))))

(ert-deftest selection-batch-native-primary-cursor-installs-and-restores ()
  (let ((buffer (generate-new-buffer " *selection-native-primary*"))
        (window (selected-window))
        (cursor-state 'bar)
        cursor-calls)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (_window _cursors)))
                      ((symbol-function 'window-cursor-type)
                       (lambda (&optional _window) cursor-state))
                      ((symbol-function 'set-window-cursor-type)
                       (lambda (_window type)
                         (setq cursor-state type)
                         (push type cursor-calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
              (should (eq 'box cursor-state))
              (should (equal '(box) cursor-calls))
              ;; Stable reconciliation and refresh do not repeat the primary
              ;; setter for an already-owned window.
              (selection-batch--reconcile-window-cursors)
              (selection-batch--view-refresh selection-batch--session)
              (should (equal '(box) cursor-calls))
              (selection-batch-collapse-owner)
              (should (eq 'bar cursor-state))
              (should (equal '(bar box) cursor-calls)))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer))))

(ert-deftest selection-batch-native-primary-cursor-preserves-intervening-change ()
  (let ((buffer (generate-new-buffer " *selection-native-primary-change*"))
        (window (selected-window))
        (cursor-state 'hbar)
        cursor-calls)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abc")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (_window _cursors)))
                      ((symbol-function 'window-cursor-type)
                       (lambda (&optional _window) cursor-state))
                      ((symbol-function 'set-window-cursor-type)
                       (lambda (_window type)
                         (setq cursor-state type)
                         (push type cursor-calls))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 2 3)) 'primary) t)
              (setq cursor-state 'hollow)
              (selection-batch--view-refresh selection-batch--session)
              (selection-batch-collapse-owner)
              (should (eq 'hollow cursor-state))
              (should (equal '(box) cursor-calls)))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer))))

(ert-deftest selection-batch-native-primary-cursor-follows-owner-window ()
  (let ((buffer (generate-new-buffer " *selection-native-primary-owner*"))
        (foreign (generate-new-buffer " *selection-native-primary-away*"))
        (first (selected-window)) second
        (states (make-hash-table :test #'eq)))
    (unwind-protect
        (progn
          (setq second (split-window first nil 'right))
          (puthash first 'bar states)
          (puthash second 'hbar states)
          (set-window-buffer first buffer)
          (set-window-buffer second buffer)
          (select-window first)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (_window _cursors)))
                      ((symbol-function 'window-cursor-type)
                       (lambda (&optional window)
                         (gethash (or window (selected-window)) states)))
                      ((symbol-function 'set-window-cursor-type)
                       (lambda (window type) (puthash window type states))))
              (selection-batch-install-snapshot
               (selection-batch-ui-test--snapshot
                buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
              (should (eq 'box (gethash first states)))
              (select-window second)
              (selection-batch--reconcile-window-cursors)
              (should (eq 'bar (gethash first states)))
              (should (eq 'box (gethash second states)))
              (set-window-buffer second foreign)
              (selection-batch--reconcile-window-cursors)
              (should (eq 'hbar (gethash second states)))
              (set-window-buffer second buffer)
              (selection-batch--reconcile-window-cursors)
              (should (eq 'box (gethash second states)))
              (selection-batch-collapse-owner)
              (should (eq 'hbar (gethash second states))))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (when (window-live-p second) (delete-window second))
      (when (window-live-p first)
        (select-window first)
        (set-window-buffer first (get-buffer-create "*scratch*")))
      (kill-buffer buffer)
      (kill-buffer foreign))))

(ert-deftest selection-batch-native-primary-setter-failure-is-compensated ()
  (let ((buffer (generate-new-buffer " *selection-native-primary-error*"))
        (window (selected-window))
        (cursor-state 'bar)
        extra-state)
    (unwind-protect
        (progn
          (set-window-buffer window buffer)
          (with-current-buffer buffer
            (insert "abcdef")
            (cl-letf (((symbol-function 'set-window-extra-cursors)
                       (lambda (_window cursors) (setq extra-state cursors)))
                      ((symbol-function 'window-cursor-type)
                       (lambda (&optional _window) cursor-state))
                      ((symbol-function 'set-window-cursor-type)
                       (lambda (_window type)
                         (setq cursor-state type)
                         (when (eq type 'box)
                           (error "hostile primary setter")))))
              (should-error
               (selection-batch-install-snapshot
                (selection-batch-ui-test--snapshot
                 buffer '((primary 1 2) (secondary 3 5)) 'primary) t)
               :type 'error)
              (should (eq 'bar cursor-state))
              (should-not extra-state)
              (should-not selection-batch--installed-window-cursors))))
      (when selection-batch--session
        (selection-batch--cleanup selection-batch--session nil t))
      (set-window-buffer window (get-buffer-create "*scratch*"))
      (kill-buffer buffer))))

(ert-deftest selection-batch-view-refresh-replaces-with-a-stable-count ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (let ((old (copy-sequence
                (selection-batch--session-overlays selection-batch--session))))
      (selection-batch--view-refresh selection-batch--session)
      (should (= 2 (length (selection-batch--session-overlays
                            selection-batch--session))))
      (dolist (overlay old) (should-not (overlay-buffer overlay))))))

(ert-deftest selection-batch-empty-secondary-becomes-range-after-insertion ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 4 4)) 'primary
    (goto-char 4)
    (insert "XY")
    (let* ((overlays (selection-batch--session-overlays selection-batch--session))
           (range (cl-find 'range overlays
                           :key (lambda (overlay)
                                  (overlay-get overlay 'selection-batch-role)))))
      (should range)
      (should (equal '(4 . 6) (cons (overlay-start range) (overlay-end range))))
      (should (eq 'selection-batch-secondary (overlay-get range 'face)))
      (should (equal '((primary 1 6) (secondary 4 6))
                     (mapcar
                      (lambda (selection)
                        (list (selection-batch-snapshot-selection-id selection)
                              (selection-batch-snapshot-selection-anchor selection)
                              (selection-batch-snapshot-selection-cursor selection)))
                      (append (selection-batch-snapshot-selections
                               (selection-batch-current-snapshot)) nil)))))))

(ert-deftest selection-batch-view-is-derived-and-collapse-destroys-it ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (let ((overlay (car (selection-batch--session-overlays selection-batch--session))))
      (delete-overlay overlay)
      (should (equal 2 (length (selection-batch-snapshot-selections
                                (selection-batch-current-snapshot)))))
      (selection-batch--view-refresh selection-batch--session)
      (setq overlay (car (selection-batch--session-overlays selection-batch--session)))
      (selection-batch-collapse)
      (should-not (overlay-buffer overlay))
      (should-not selection-batch--session))))

(ert-deftest selection-batch-view-refreshes-once-per-transform-commit ()
  (let ((calls 0)
        (backend selection-batch--view-refresh-function))
    (cl-letf (((symbol-value 'selection-batch--view-refresh-function)
               (lambda (session)
                 (setq calls (1+ calls))
                 (funcall backend session))))
      (selection-batch-ui-test--with-session
          "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
        (setq calls 0)
        (selection-batch-apply-transform #'selection-batch-transform-reverse)
        (should (= 1 calls))
        (selection-batch-apply-transform #'identity)
        (should (= 1 calls))))))

(ert-deftest selection-batch-transaction-map-is-private-and-supported ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (let ((global-t (lookup-key global-map (kbd "t")))
          (old-t (lookup-key selection-batch--transaction-map (kbd "t")))
          (command (make-symbol "selection-batch-test-supported")))
      (fset command (lambda () (interactive)))
      (unwind-protect
          (progn
            (define-key selection-batch--transaction-map (kbd "t") command)
            (selection-batch-register-transaction-command command)
            (selection-batch--transaction-install selection-batch--session)
            (should (eq command (key-binding (kbd "t"))))
            (call-interactively command)
            (should selection-batch--session)
            (should (functionp
                     (selection-batch--session-transient-exit-function
                      selection-batch--session))))
        (define-key selection-batch--transaction-map (kbd "t")
                    (and (not (numberp old-t)) old-t))
        (fmakunbound command))
      (should (eq global-t (lookup-key global-map (kbd "t"))))
      (should-not (where-is-internal 'recursive-edit
                                     selection-batch--transaction-map)))))

(ert-deftest selection-batch-undocumented-key-is-unbound-and-collapses ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (should-not (lookup-key selection-batch--transaction-map (kbd "t")))
    (funcall (selection-batch--session-transient-exit-function
              selection-batch--session))
    (should-not selection-batch--session)))

(ert-deftest selection-batch-transaction-outside-command-collapses-first ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((exit (selection-batch--session-transient-exit-function
                 selection-batch--session))
          events)
      ;; This is the callback ordering used by the command loop for a key not
      ;; in the transient map; the real command remains untouched.
      (funcall exit)
      (push (if selection-batch--session 'session-live 'collapsed) events)
      (push 'normal-command events)
      (should (equal '(collapsed normal-command) (nreverse events)))
      (should mark-active))))

(ert-deftest selection-batch-prompt-suspends-validates-and-resumes ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((session selection-batch--session)
          (selection-batch--read-string-function
           (lambda (prompt initial)
             (should (equal "Value: " prompt))
             (should (equal "seed" initial))
             (should (selection-batch--session-suspending-p
                      selection-batch--session))
             (should-not (selection-batch--session-transient-exit-function
                          selection-batch--session))
             "done")))
      (should (equal "done" (selection-batch-read-string "Value: " "seed")))
      (should (eq session selection-batch--session))
      (should-not (selection-batch--session-suspending-p session))
      (should (functionp
               (selection-batch--session-transient-exit-function session))))))

(ert-deftest selection-batch-regexp-commands-use-safe-suspended-prompt ()
  (dolist (command '(selection-batch-gather-regexp
                     selection-batch-keep selection-batch-drop))
    (selection-batch-ui-test--with-session
        "aa bb" '((primary 1 3) (secondary 4 6)) 'primary
      (selection-batch--transaction-install selection-batch--session)
      (let* ((session selection-batch--session)
             (reads 0)
             (selection-batch--read-regexp-function
             (lambda (&rest _)
               (cl-incf reads)
               (should (selection-batch--session-suspending-p session))
               (should-not
                (selection-batch--session-transient-exit-function session))
               (pcase command
                 ('selection-batch-gather-regexp "[[:alpha:]]+")
                 ('selection-batch-keep "a")
                 (_ "z")))))
        (call-interactively command)
        (should (= 1 reads))
        (should (selection-batch-active-p))
        (should (functionp
                 (selection-batch--session-transient-exit-function
                  selection-batch--session)))))))

(ert-deftest selection-batch-regexp-prompt-quit-resumes-map ()
  (selection-batch-ui-test--with-session
      "aa bb" '((primary 1 3) (secondary 4 6)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((session selection-batch--session)
          (selection-batch--read-regexp-function
           (lambda (&rest _) (signal 'quit nil))))
      (let (quit-seen)
        (condition-case nil
            (call-interactively #'selection-batch-keep)
          (quit (setq quit-seen t)))
        (should quit-seen))
      (should (eq session selection-batch--session))
      (should (functionp
               (selection-batch--session-transient-exit-function session))))))

(ert-deftest selection-batch-prompt-quit-resumes-exactly-once ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((session selection-batch--session)
          (resumes 0)
          (real-install (symbol-function 'selection-batch--transaction-install))
          (selection-batch--read-string-function
           (lambda (&rest _arguments) (signal 'quit nil))))
      (let (quit-seen)
        (cl-letf (((symbol-function 'selection-batch--transaction-install)
                   (lambda (candidate)
                     (setq resumes (1+ resumes))
                     (funcall real-install candidate))))
          (condition-case nil
              (selection-batch-read-string "Quit: ")
            (quit (setq quit-seen t))))
        (should quit-seen))
      (should (= 1 resumes))
      (should (eq session selection-batch--session))
      (should (functionp
               (selection-batch--session-transient-exit-function session))))))

(ert-deftest selection-batch-prompt-generation-change-collapses-stale-session ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((selection-batch--read-string-function
           (lambda (&rest _arguments)
             (cl-incf (selection-batch--session-generation
                       selection-batch--session))
             "stale")))
      (should-error (selection-batch-read-string "Stale: ") :type 'user-error)
      (should-not selection-batch--session))))

(ert-deftest selection-batch-prompt-buffer-switch-collapses-stale-session ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((foreign (generate-new-buffer " *selection-prompt-foreign*")))
      (unwind-protect
          (let ((selection-batch--read-string-function
                 (lambda (&rest _arguments)
                   (set-buffer foreign)
                   "foreign")))
            (should-error (selection-batch-read-string "Switch: ")
                          :type 'user-error)
            (should-not selection-batch--session))
        (kill-buffer foreign)))))

(ert-deftest selection-batch-transaction-exit-is-idempotent ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (selection-batch--transaction-install selection-batch--session)
    (let ((exit (selection-batch--session-transient-exit-function
                 selection-batch--session)))
      (funcall exit)
      (funcall exit)
      (should-not selection-batch--session))))

(ert-deftest selection-batch-transaction-remaps-undo-to-whole-buffer-unit ()
  (with-temp-buffer
    (buffer-enable-undo)
    (insert "abc")
    (setq buffer-undo-list nil)
    (selection-batch-install-snapshot
     (selection-batch-ui-test--snapshot (current-buffer) '((primary 1 2)) 'primary))
    (let* ((source (selection-batch-current-snapshot))
           (edit (selection-batch-edit-create
                  :selection-id 'primary :logical-index 0
                  :beginning 1 :end 2 :replacement "X"
                  :result (selection-batch-snapshot-selection-create
                           :id 'primary :anchor 1 :cursor 2)))
           (plan (selection-batch-plan-create
                  :buffer (current-buffer)
                  :source-buffer-tick (selection-batch-snapshot-buffer-tick source)
                  :source-generation (selection-batch-snapshot-generation source)
                  :source-narrowing (selection-batch-snapshot-narrowing source)
                  :edits (vector edit)
                  :result-policy
                  (selection-batch-snapshot-create
                   :buffer (current-buffer) :buffer-tick 0 :generation 1
                   :primary-id 'primary :narrowing '(1 . 4)
                   :selections
                   (vector (selection-batch-snapshot-selection-create
                            :id 'primary :anchor 1 :cursor 2))))))
      (selection-batch-apply-plan plan)
      (selection-batch--transaction-install selection-batch--session)
      (should mark-active)
      (should (eq #'selection-batch-undo
                  (command-remapping 'undo nil selection-batch--transaction-map)))
      (should (eq #'selection-batch-undo
                  (command-remapping 'undo-only nil selection-batch--transaction-map)))
      (call-interactively (command-remapping 'undo))
      (should (equal "abc" (buffer-string)))
      (should-not selection-batch--session)
      (should-not mark-active))))

(ert-deftest selection-batch-transaction-undo-error-still-cleans-session ()
  (selection-batch-ui-test--with-session
      "abc" '((primary 1 2)) 'primary
    (buffer-enable-undo)
    (setq buffer-undo-list nil)
    (selection-batch--transaction-install selection-batch--session)
    (should-error (call-interactively (command-remapping 'undo))
                  :type 'user-error)
    (should-not selection-batch--session)
    (should-not mark-active)))

;;; selection-batch-ui-test.el ends here
