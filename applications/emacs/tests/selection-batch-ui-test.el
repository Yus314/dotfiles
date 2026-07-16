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

(ert-deftest selection-batch-view-renders-only-secondary-selections ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 3) (range 3 5) (caret 6 6)) 'primary
    (let* ((overlays (selection-batch--session-overlays selection-batch--session))
           (range (nth 0 overlays))
           (caret (nth 1 overlays)))
      (should (= 2 (length overlays)))
      (should (equal '(3 . 5) (cons (overlay-start range) (overlay-end range))))
      (should (eq 'selection-batch-secondary (overlay-get range 'face)))
      (should (equal selection-batch--overlay-priority
                     (overlay-get range 'priority)))
      (should (equal '(nil . 10) (overlay-get range 'priority)))
      (should (= 6 (overlay-start caret)))
      (should (= 6 (overlay-end caret)))
      (let ((cursor (overlay-get caret 'after-string)))
        (should (stringp cursor))
        (should (eq 'selection-batch-secondary-cursor
                    (get-text-property 0 'face cursor)))))))

(ert-deftest selection-batch-view-refresh-replaces-with-a-stable-count ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 3 5)) 'primary
    (let ((old (car (selection-batch--session-overlays selection-batch--session))))
      (selection-batch--view-refresh selection-batch--session)
      (should (= 1 (length (selection-batch--session-overlays
                            selection-batch--session))))
      (should-not (overlay-buffer old))
      (should-not (eq old (car (selection-batch--session-overlays
                                selection-batch--session)))))))

(ert-deftest selection-batch-empty-secondary-becomes-range-after-insertion ()
  (selection-batch-ui-test--with-session
      "abcdef" '((primary 1 2) (secondary 4 4)) 'primary
    (let ((overlay (car (selection-batch--session-overlays
                         selection-batch--session))))
      (goto-char 4)
      (insert "XY")
      (should (equal '(4 . 6) (cons (overlay-start overlay)
                                    (overlay-end overlay))))
      (should-not (overlay-get overlay 'after-string))
      (should (eq 'selection-batch-secondary (overlay-get overlay 'face)))
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
