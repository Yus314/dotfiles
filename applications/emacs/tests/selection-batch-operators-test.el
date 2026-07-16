;;; selection-batch-operators-test.el --- Fixed operator tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'selection-batch-operators)

(defun selection-batch-operators-test--snapshot (buffer triples primary)
  (with-current-buffer buffer
    (selection-batch-snapshot-create
     :buffer buffer :buffer-tick (buffer-chars-modified-tick) :generation 0
     :primary-id primary :narrowing (cons (point-min) (point-max))
     :selections
     (vconcat
      (mapcar (lambda (triple)
                (apply #'selection-batch-snapshot-selection-create
                       (cl-mapcan #'list '(:id :anchor :cursor) triple)))
              triples)))))

(defmacro selection-batch-operators-test--with-session (text triples primary &rest body)
  (declare (indent 3) (debug t))
  `(with-temp-buffer
     (buffer-enable-undo)
     (insert ,text)
     (setq buffer-undo-list nil)
     (goto-char (point-min))
     (let ((selection-batch-register nil)
           (selection-batch-last-recipe nil))
       (unwind-protect
           (progn
             (selection-batch-install-snapshot
              (selection-batch-operators-test--snapshot
               (current-buffer) ,triples ,primary))
             ,@body)
         (when selection-batch--session
           (ignore-errors
             (selection-batch--cleanup selection-batch--session nil t)))))))

(defun selection-batch-operators-test--ranges ()
  (mapcar (lambda (selection)
            (list (selection-batch-snapshot-selection-id selection)
                  (selection-batch-snapshot-selection-anchor selection)
                  (selection-batch-snapshot-selection-cursor selection)))
          (append (selection-batch-snapshot-selections
                   (selection-batch-current-snapshot)) nil)))

(ert-deftest selection-batch-copy-preserves-order-direction-empty-multibyte-and-text ()
  (selection-batch-operators-test--with-session
      "ab日本z" '((ascii 1 3) (jp 5 3) (empty 6 6)) 'jp
    (let ((before (buffer-string))
          (tick (buffer-chars-modified-tick)))
      (selection-batch-copy)
      (should (equal before (buffer-string)))
      (should (= tick (buffer-chars-modified-tick)))
      (should (selection-batch-text-vector-p selection-batch-register))
      (should (equal ["ab" "日本" ""]
                     (selection-batch-text-vector-values selection-batch-register)))
      (should (= 1 (selection-batch-text-vector-primary-index
                    selection-batch-register))))))

(ert-deftest selection-batch-delete-keeps-adjacent-separate-and-merges-overlap ()
  (selection-batch-operators-test--with-session
      "abcdef" '((a 1 3) (b 3 5)) 'a
    (selection-batch-delete)
    (should (equal "ef" (buffer-string)))
    (should (equal '((a 1 1) (b 1 1))
                   (selection-batch-operators-test--ranges))))
  (selection-batch-operators-test--with-session
      "abcdef" '((a 1 4) (b 3 6)) 'b
    (selection-batch-delete)
    (should (equal "f" (buffer-string)))
    (should (equal '((b 1 1)) (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-delete-empty-is-defined-no-op-caret ()
  (selection-batch-operators-test--with-session "abc" '((a 2 2)) 'a
    (selection-batch-delete)
    (should (equal "abc" (buffer-string)))
    (should (equal '((a 2 2)) (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-replace-preserves-direction-and-selects-multibyte-result ()
  (selection-batch-operators-test--with-session
      "ab cd" '((forward 1 3) (backward 6 4)) 'forward
    (selection-batch-replace "日本")
    (should (equal "日本 日本" (buffer-string)))
    (should (equal '((forward 1 3) (backward 6 4))
                   (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-replace-overlap-rejects-before-mutation ()
  (selection-batch-operators-test--with-session
      "abcdef" '((a 1 4) (b 3 6)) 'a
    (let ((before (selection-batch-current-snapshot)))
      (should-error (selection-batch-replace "X") :type 'user-error)
      (should (equal "abcdef" (buffer-string)))
      (should (equal before (selection-batch-current-snapshot))))))

(ert-deftest selection-batch-replace-interactive-prompts-exactly-once ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (let ((calls 0))
      (cl-letf (((symbol-function 'selection-batch-read-string)
                 (lambda (&rest _) (cl-incf calls) "X")))
        (call-interactively #'selection-batch-replace))
      (should (= calls 1))
      (should (equal "X X" (buffer-string))))))

(ert-deftest selection-batch-case-operators-cover-properties-and-capitalization ()
  (dolist (case '((selection-batch-uppercase "AB CD")
                  (selection-batch-lowercase "ab cd")
                  (selection-batch-capitalize "Ab Cd")))
    (selection-batch-operators-test--with-session
        "ab CD" '((a 1 3) (b 4 6)) 'a
      (put-text-property 1 3 'selection-batch-test 'kept)
      (funcall (car case))
      (should (equal (cadr case) (buffer-string)))
      (should-not (get-text-property 1 'selection-batch-test)))))

(ert-deftest selection-batch-fixed-insertion-handles-direction-empty-and-results ()
  (selection-batch-operators-test--with-session
      "abcd" '((back 3 1) (empty 5 5)) 'back
    (selection-batch-insert-before "日")
    (should (equal "日abcd日" (buffer-string)))
    (should (equal '((back 2 1) (empty 6 7))
                   (selection-batch-operators-test--ranges))))
  (selection-batch-operators-test--with-session "abcd" '((back 3 1)) 'back
    (selection-batch-insert-after "Z")
    (should (equal "abZcd" (buffer-string)))
    (should (equal '((back 4 3)) (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-same-position-pairwise-paste-follows-logical-order ()
  (selection-batch-operators-test--with-session "x" '((a 1 1) (b 1 1)) 'a
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["A" "B"] :primary-index 0 :metadata nil))
    (selection-batch-paste)
    (should (equal "ABx" (buffer-string)))
    (should (equal '((a 1 2) (b 2 3))
                   (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-register-is-defensive-and-preserves-properties ()
  (let* ((text (propertize "x" 'face 'bold))
         (values (vector text))
         (metadata (list :nested (vector "safe")))
         (register (selection-batch-text-vector-create
                    :values values :primary-index 0 :metadata metadata)))
    (aset text 0 ?y)
    (aset values 0 "bad")
    (aset (cadr metadata) 0 "bad")
    (let ((out (aref (selection-batch-text-vector-values register) 0)))
      (should (equal "x" out))
      (should (eq 'bold (get-text-property 0 'face out))))
    (should (equal '(:nested ["safe"])
                   (selection-batch-text-vector-metadata register)))
    (should-error (selection-batch-text-vector-create
                   :values '("not-vector") :primary-index 0))))

(ert-deftest selection-batch-paste-broadcasts-one-and-pairs-n ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (selection-batch-import-scalar "日")
    (selection-batch-paste)
    (should (equal "日 日" (buffer-string))))
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["X" "YZ"] :primary-index 1 :metadata nil))
    (selection-batch-paste)
    (should (equal "X YZ" (buffer-string)))))

(ert-deftest selection-batch-paste-preserves-register-text-properties ()
  (selection-batch-operators-test--with-session "a" '((a 1 2)) 'a
    (selection-batch-import-scalar
     (propertize "X" 'selection-batch-test 'kept))
    (selection-batch-paste)
    (should (eq 'kept (get-text-property 1 'selection-batch-test)))))

(ert-deftest selection-batch-paste-rejects-other-cardinality-before-planning-or-mutation ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["1" "2" "3"] :primary-index 0 :metadata nil))
    (let ((before (selection-batch-current-snapshot)))
      (should-error (selection-batch-paste) :type 'user-error)
      (should (equal "aa bb" (buffer-string)))
      (should (equal before (selection-batch-current-snapshot))))))

(ert-deftest selection-batch-scalar-import-never-splits-and-bridge-joins-explicitly ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (selection-batch-import-scalar "x\ny")
    (selection-batch-paste)
    (should (equal "x\ny x\ny" (buffer-string)))
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["a" "b"] :primary-index 0 :metadata nil))
    (let ((kill-ring nil))
      (should (equal "a|b" (selection-batch-register-to-kill-ring "|")))
      (should (equal "a|b" (current-kill 0))))))

(ert-deftest selection-batch-recipe-is-defensive-and-position-free ()
  (let* ((argument (copy-sequence "x"))
         (recipe (selection-batch-recipe-create
                  :operator 'replace :arguments (list argument)
                  :cardinality-policy 'one-per-selection :result-policy 'select
                  :adapter-id 'fixed)))
    (aset argument 0 ?y)
    (should (equal '("x") (selection-batch-recipe-arguments recipe)))
    (should-not
     (cl-labels ((unsafe (value)
                   (cond ((markerp value) t)
                         ((selection-batch-snapshot-selection-p value) t)
                         ((consp value) (or (unsafe (car value)) (unsafe (cdr value))))
                         ((vectorp value) (cl-some #'unsafe (append value nil))))))
       (unsafe recipe)))))

(ert-deftest selection-batch-repeat-replans-current-selections ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (selection-batch-replace "X")
    (selection-batch-apply-transform
     (lambda (snapshot)
       (selection-batch-snapshot-create
        :buffer (current-buffer) :buffer-tick (buffer-chars-modified-tick)
        :generation (selection-batch-snapshot-generation snapshot)
        :primary-id 'a :narrowing (cons (point-min) (point-max))
        :selections (vector
                     (selection-batch-snapshot-selection-create
                      :id 'a :anchor 3 :cursor 4)))))
    (selection-batch-repeat)
    (should (equal "X X" (buffer-string)))
    (should (equal '((a 3 4)) (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-repeat-revalidates-paste-cardinality ()
  (selection-batch-operators-test--with-session "aa bb" '((a 1 3) (b 4 6)) 'a
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["X" "Y"] :primary-index 0 :metadata nil))
    (selection-batch-paste)
    (selection-batch-apply-transform
     (lambda (snapshot)
       (selection-batch-snapshot-create
        :buffer (current-buffer) :buffer-tick (buffer-chars-modified-tick)
        :generation (selection-batch-snapshot-generation snapshot)
        :primary-id 'a :narrowing (cons (point-min) (point-max))
        :selections (vector
                     (selection-batch-snapshot-selection-create
                      :id 'a :anchor 1 :cursor 2)))))
    (let ((before (buffer-string)))
      (should-error (selection-batch-repeat) :type 'user-error)
      (should (equal before (buffer-string))))))

(ert-deftest selection-batch-selection-undo-never-undoes-text ()
  (selection-batch-operators-test--with-session "abc" '((a 1 2) (b 2 3)) 'a
    (selection-batch-apply-transform #'selection-batch-transform-reverse)
    (selection-batch-selection-undo)
    (should (equal "abc" (buffer-string)))
    (should (equal '((a 1 2) (b 2 3))
                   (selection-batch-operators-test--ranges)))))

(ert-deftest selection-batch-safe-text-undo-collapses-stale-secondary-state ()
  (selection-batch-operators-test--with-session "abc" '((a 1 2) (b 2 3)) 'a
    (selection-batch-replace "X")
    (selection-batch-undo)
    (should (equal "abc" (buffer-string)))
    (should-not selection-batch--session)))

(ert-deftest selection-batch-operator-failure-rolls-back-text-register-and-recipe ()
  (selection-batch-operators-test--with-session "abc" '((a 1 2)) 'a
    (setq selection-batch-register
          (selection-batch-text-vector-create
           :values ["old"] :primary-index 0 :metadata nil)
          selection-batch-last-recipe
          (selection-batch-recipe-create :operator 'copy))
    (let ((old-register selection-batch-register)
          (old-recipe selection-batch-last-recipe)
          (selection-batch--plan-refresh-view-function
           (lambda (&rest _) (error "injected operator failure"))))
      (should-error (selection-batch-replace "X"))
      (should (equal "abc" (buffer-string)))
      (should (equal old-register selection-batch-register))
      (should (equal old-recipe selection-batch-last-recipe)))))

(ert-deftest selection-batch-supported-operators-are-remapped-without-final-keys ()
  (dolist (command '(selection-batch-copy selection-batch-delete
                     selection-batch-replace selection-batch-uppercase
                     selection-batch-lowercase selection-batch-capitalize
                     selection-batch-insert-before selection-batch-insert-after
                     selection-batch-paste selection-batch-repeat))
    (should (eq command
                (lookup-key selection-batch--transaction-map
                            (vector 'remap command))))))

(provide 'selection-batch-operators-test)
;;; selection-batch-operators-test.el ends here
