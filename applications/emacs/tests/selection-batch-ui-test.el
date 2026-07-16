;;; selection-batch-ui-test.el --- UI tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch-ui)

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

;;; selection-batch-ui-test.el ends here
