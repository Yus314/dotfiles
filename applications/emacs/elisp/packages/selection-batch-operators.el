;;; selection-batch-operators.el --- Typed selection batch operators -*- lexical-binding: t; -*-

;;; Commentary:
;; Pure planners for fixed batch operations.  Public text commands snapshot once,
;; plan every integer range and replacement, and delegate all buffer mutation to
;; `selection-batch-apply-plan'.  Copy, fixed insertion, replacement, and paste
;; preserve supplied text properties; case conversion uses Emacs string case
;; functions and intentionally adopts their property-stripping result.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'selection-batch-core)
(require 'selection-batch-plan)
(require 'selection-batch-ui)

(cl-defstruct (selection-batch-text-vector
               (:constructor selection-batch--text-vector-create)
               (:conc-name selection-batch--text-vector-))
  (values nil :read-only t)
  (primary-index nil :read-only t)
  (metadata nil :read-only t))

(cl-defun selection-batch-text-vector-create (&key values primary-index metadata)
  "Create a defensive typed text vector.
VALUES must be a nonempty vector of strings.  Text properties are preserved.
PRIMARY-INDEX must name one value; METADATA must contain no required shape."
  (unless (and (vectorp values) (> (length values) 0)
               (cl-every #'stringp (append values nil)))
    (signal 'wrong-type-argument (list 'selection-batch-text-values values)))
  (unless (and (integerp primary-index)
               (<= 0 primary-index) (< primary-index (length values)))
    (user-error "Text vector primary index is outside its values"))
  (selection-batch--text-vector-create
   :values (vconcat (mapcar #'copy-sequence (append values nil)))
   :primary-index primary-index
   :metadata (selection-batch--plan-copy-value metadata)))

(defun selection-batch-text-vector-values (register)
  "Return defensive string copies from typed REGISTER."
  (vconcat (mapcar #'copy-sequence
                   (append (selection-batch--text-vector-values register) nil))))

(defun selection-batch-text-vector-primary-index (register)
  "Return REGISTER's primary logical index."
  (selection-batch--text-vector-primary-index register))

(defun selection-batch-text-vector-metadata (register)
  "Return a defensive copy of REGISTER's metadata."
  (selection-batch--plan-copy-value
   (selection-batch--text-vector-metadata register)))

(defun selection-batch--operator-selections (snapshot)
  "Return SNAPSHOT selections in logical order."
  (append (selection-batch-snapshot-selections snapshot) nil))

(defun selection-batch--operator-primary-index (snapshot)
  "Return SNAPSHOT's primary logical index."
  (or (cl-position (selection-batch-snapshot-primary-id snapshot)
                   (selection-batch--operator-selections snapshot)
                   :key #'selection-batch-snapshot-selection-id :test #'equal)
      (user-error "Primary selection is absent")))

(defun selection-batch--operator-text (snapshot selection)
  "Extract SELECTION text from SNAPSHOT, retaining text properties."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (buffer-substring (selection-batch-selection-beginning selection)
                      (selection-batch-selection-end selection))))

(defun selection-batch--operator-recipe (operator arguments cardinality result)
  "Build a position-free recipe for OPERATOR."
  (selection-batch-recipe-create
   :operator operator :arguments arguments :cardinality-policy cardinality
   :result-policy result :adapter-id 'selection-batch-fixed))

(defun selection-batch--operator-result-snapshot (source selections primary-id)
  "Build a declared result snapshot for SOURCE."
  (selection-batch-snapshot-create
   :buffer (selection-batch-snapshot-buffer source)
   :buffer-tick (selection-batch-snapshot-buffer-tick source)
   :generation (1+ (selection-batch-snapshot-generation source))
   :primary-id primary-id :narrowing (selection-batch-snapshot-narrowing source)
   :selections (vconcat selections)))

(defun selection-batch--operator-plan (source edits results primary recipe
                                              &optional register-update)
  "Build a validated immutable operator plan from SOURCE."
  (selection-batch-plan-create
   :buffer (selection-batch-snapshot-buffer source)
   :source-buffer-tick (selection-batch-snapshot-buffer-tick source)
   :source-generation (selection-batch-snapshot-generation source)
   :source-narrowing (selection-batch-snapshot-narrowing source)
   :edits (vconcat edits)
   :result-policy (selection-batch--operator-result-snapshot
                   source results primary)
   :register-update (if (null register-update)
                        selection-batch-no-update register-update)
   :recipe recipe))

(defun selection-batch--operator-entry-results (entries result-kind)
  "Return explicit result selections for ENTRIES under RESULT-KIND.
Each entry is (SELECTION INDEX BEGIN END REPLACEMENT FORWARD-P).
Positions account for all edits to the left and same-position insertions in
logical order."
  (mapcar
   (lambda (entry)
     (pcase-let ((`(,selection ,index ,beginning ,end ,replacement ,forward) entry))
       (let ((start beginning))
         (dolist (other entries)
           (pcase-let ((`(,_ ,other-index ,other-begin ,other-end ,other-text ,_)
                         other))
             (when (or (< other-begin beginning)
                       (and (= other-begin beginning)
                            (= other-begin other-end) (= beginning end)
                            (< other-index index)))
               (cl-incf start (- (length other-text)
                                 (- other-end other-begin))))))
         (let* ((finish (+ start (length replacement)))
                (anchor (pcase result-kind
                          ('caret start)
                          (_ (if forward start finish))))
                (cursor (pcase result-kind
                          ('caret start)
                          (_ (if forward finish start)))))
           (selection-batch-snapshot-selection-create
            :id (selection-batch-snapshot-selection-id selection)
            :anchor anchor :cursor cursor)))))
   entries))

(defun selection-batch--operator-edit-plan
    (source selections replacements operator arguments result-kind
            &optional cardinality-policy result-directions)
  "Plan replacements for SELECTIONS in SOURCE without mutating the buffer."
  (unless (= (length selections) (length replacements))
    (user-error "Operator replacement cardinality mismatch"))
  (let ((entries
         (cl-loop for selection in selections
                  for replacement in replacements
                  for direction in (or result-directions selections)
                  for index from 0
                  collect (list selection index
                                (selection-batch-selection-beginning selection)
                                (selection-batch-selection-end selection)
                                (copy-sequence replacement)
                                (selection-batch-selection-forward-p direction))))
        edits)
    (let ((results (selection-batch--operator-entry-results entries result-kind)))
      (setq edits
            (cl-loop for entry in entries
                     for result in results
                     collect
                     (pcase-let ((`(,selection ,index ,beginning ,end ,replacement ,_)
                                   entry))
                       (selection-batch-edit-create
                        :selection-id
                        (selection-batch-snapshot-selection-id selection)
                        :logical-index index :beginning beginning :end end
                        :replacement replacement :result result :tie-break index))))
      (selection-batch--operator-plan
       source edits results
       (selection-batch-snapshot-primary-id source)
       (selection-batch--operator-recipe
        operator arguments (or cardinality-policy 'one-per-selection) result-kind)))))

(defun selection-batch--plan-copy (source)
  "Plan a property-preserving vector copy from SOURCE."
  (let* ((selections (selection-batch--operator-selections source))
         (register
          (selection-batch-text-vector-create
           :values (vconcat (mapcar (lambda (selection)
                                      (selection-batch--operator-text source selection))
                                    selections))
           :primary-index (selection-batch--operator-primary-index source)
           :metadata '(:text-properties preserve :source selection-batch-copy)))
         (recipe (selection-batch--operator-recipe
                  'copy nil 'one-per-selection 'unchanged)))
    (selection-batch--operator-plan
     source nil selections (selection-batch-snapshot-primary-id source)
     recipe register)))

(defun selection-batch-copy ()
  "Copy all current selections to the typed package register.
The buffer is not modified.  Use `selection-batch-register-to-kill-ring' for an
explicit scalar kill-ring bridge."
  (interactive)
  (selection-batch-apply-plan
   (selection-batch--plan-copy (selection-batch-current-snapshot))))

(defun selection-batch--plan-delete (source)
  "Plan deletion from SOURCE, coalescing only overlapping ranges."
  (let* ((normalized (selection-batch-normalize-snapshot source 'merge))
         (selections (selection-batch--operator-selections normalized))
         (replacements (make-list (length selections) "")))
    (selection-batch--operator-edit-plan
     source selections replacements 'delete nil 'caret 'merge-overlaps)))

(defun selection-batch-delete ()
  "Delete selections atomically and leave carets at their starts."
  (interactive)
  (selection-batch-apply-plan
   (selection-batch--plan-delete (selection-batch-current-snapshot))))

(defun selection-batch--plan-fixed-replace (source string)
  "Plan replacement of every SOURCE selection with STRING."
  (unless (stringp string) (signal 'wrong-type-argument (list 'stringp string)))
  (let ((selections (selection-batch--operator-selections source)))
    (selection-batch--operator-edit-plan
     source selections (make-list (length selections) string)
     'replace (list (copy-sequence string)) 'select)))

(defun selection-batch-replace (string)
  "Replace every selection with fixed STRING, selecting each replacement."
  (interactive (list (selection-batch-read-string "Replace with: ")))
  (selection-batch-apply-plan
   (selection-batch--plan-fixed-replace
    (selection-batch-current-snapshot) string)))

(defun selection-batch--plan-case (source operator function)
  "Plan case OPERATOR by applying string FUNCTION to snapshot text."
  (let* ((selections (selection-batch--operator-selections source))
         (replacements
          (mapcar (lambda (selection)
                    (funcall function (selection-batch--operator-text source selection)))
                  selections)))
    (selection-batch--operator-edit-plan
     source selections replacements operator nil 'select)))

(defun selection-batch-uppercase ()
  "Uppercase each selected string without command replay."
  (interactive)
  (selection-batch-apply-plan
   (selection-batch--plan-case (selection-batch-current-snapshot)
                               'uppercase #'upcase)))

(defun selection-batch-lowercase ()
  "Lowercase each selected string without command replay."
  (interactive)
  (selection-batch-apply-plan
   (selection-batch--plan-case (selection-batch-current-snapshot)
                               'lowercase #'downcase)))

(defun selection-batch-capitalize ()
  "Capitalize each selected string without command replay."
  (interactive)
  (selection-batch-apply-plan
   (selection-batch--plan-case (selection-batch-current-snapshot)
                               'capitalize #'capitalize)))

(defun selection-batch--plan-insert (source string after-p)
  "Plan fixed STRING insertion before or AFTER-P each SOURCE selection."
  (unless (stringp string) (signal 'wrong-type-argument (list 'stringp string)))
  (let* ((original (selection-batch--operator-selections source))
         (points
         (mapcar
          (lambda (selection)
            (let ((position (if after-p
                                (selection-batch-selection-end selection)
                              (selection-batch-selection-beginning selection))))
              (selection-batch-snapshot-selection-create
               :id (selection-batch-snapshot-selection-id selection)
               :anchor position :cursor position)))
          original)))
    (selection-batch--operator-edit-plan
     source points (make-list (length points) string)
     (if after-p 'insert-after 'insert-before)
     (list (copy-sequence string)) 'select nil original)))

(defun selection-batch-insert-before (string)
  "Insert fixed STRING before every selection in deterministic logical order."
  (interactive (list (selection-batch-read-string "Insert before: ")))
  (selection-batch-apply-plan
   (selection-batch--plan-insert
    (selection-batch-current-snapshot) string nil)))

(defun selection-batch-insert-after (string)
  "Insert fixed STRING after every selection in deterministic logical order."
  (interactive (list (selection-batch-read-string "Insert after: ")))
  (selection-batch-apply-plan
   (selection-batch--plan-insert
    (selection-batch-current-snapshot) string t)))

(defun selection-batch--require-text-vector ()
  "Return the valid package register or signal before planning edits."
  (unless (selection-batch-text-vector-p selection-batch-register)
    (user-error "Selection batch register does not contain a text vector"))
  ;; Reconstruct through the checked public constructor.  This catches corrupt
  ;; private values and prevents later cardinality checks from trusting them.
  (selection-batch-text-vector-create
   :values (selection-batch-text-vector-values selection-batch-register)
   :primary-index
   (selection-batch-text-vector-primary-index selection-batch-register)
   :metadata (selection-batch-text-vector-metadata selection-batch-register)))

(defun selection-batch--plan-paste (source register)
  "Plan broadcast or pairwise paste of typed REGISTER over SOURCE."
  (let* ((selections (selection-batch--operator-selections source))
         (values (append (selection-batch-text-vector-values register) nil))
         (source-count (length selections))
         (value-count (length values))
         replacements policy)
    ;; Resolve cardinality before constructing even one edit descriptor.
    (cond
     ((= value-count 1)
      (setq replacements (make-list source-count (car values))
            policy 'broadcast))
     ((= value-count source-count)
      (setq replacements values policy 'pairwise))
     (t (user-error "Cannot paste %d values into %d selections"
                    value-count source-count)))
    (selection-batch--operator-edit-plan
     source selections replacements 'paste nil 'select policy)))

(defun selection-batch-paste ()
  "Broadcast one register value or pair N values with N selections."
  (interactive)
  (let ((source (selection-batch-current-snapshot))
        (register (selection-batch--require-text-vector)))
    (selection-batch-apply-plan
     (selection-batch--plan-paste source register))))

(defun selection-batch-import-scalar (string)
  "Import STRING explicitly as a one-element typed vector.
No newline splitting or kill-ring inference is performed."
  (interactive (list (selection-batch-read-string "Import scalar: ")))
  (unless (stringp string) (signal 'wrong-type-argument (list 'stringp string)))
  (setq selection-batch-register
        (selection-batch-text-vector-create
         :values (vector string) :primary-index 0
         :metadata '(:text-properties preserve :source explicit-scalar))))

(defun selection-batch-register-to-kill-ring (separator)
  "Join the typed register with explicit SEPARATOR and call `kill-new' once.
This is the only kill-ring bridge; selection boundaries are otherwise retained."
  (interactive (list (read-string "Join register with: " "\n")))
  (unless (stringp separator)
    (signal 'wrong-type-argument (list 'stringp separator)))
  (let* ((register (selection-batch--require-text-vector))
         (scalar (mapconcat #'identity
                            (append (selection-batch-text-vector-values register) nil)
                            separator)))
    (kill-new scalar)
    scalar))

(defun selection-batch--plan-from-recipe (source recipe)
  "Replan semantic RECIPE against current SOURCE selections."
  (pcase (selection-batch-recipe-operator recipe)
    ('copy (selection-batch--plan-copy source))
    ('delete (selection-batch--plan-delete source))
    ('replace (selection-batch--plan-fixed-replace
               source (car (selection-batch-recipe-arguments recipe))))
    ('uppercase (selection-batch--plan-case source 'uppercase #'upcase))
    ('lowercase (selection-batch--plan-case source 'lowercase #'downcase))
    ('capitalize (selection-batch--plan-case source 'capitalize #'capitalize))
    ('insert-before (selection-batch--plan-insert
                     source (car (selection-batch-recipe-arguments recipe)) nil))
    ('insert-after (selection-batch--plan-insert
                    source (car (selection-batch-recipe-arguments recipe)) t))
    ('paste (selection-batch--plan-paste source
                                         (selection-batch--require-text-vector)))
    (_ (user-error "Unsupported selection batch recipe: %S"
                   (selection-batch-recipe-operator recipe)))))

(defun selection-batch-repeat ()
  "Replan the last semantic recipe against the current live selections."
  (interactive)
  (unless (selection-batch-recipe-p selection-batch-last-recipe)
    (user-error "There is no semantic selection batch recipe"))
  (let ((source (selection-batch-current-snapshot))
        (recipe (selection-batch--plan-copy-value selection-batch-last-recipe)))
    (selection-batch-apply-plan
     (selection-batch--plan-from-recipe source recipe))))

(dolist (command '(selection-batch-copy selection-batch-delete
                    selection-batch-replace selection-batch-uppercase
                    selection-batch-lowercase selection-batch-capitalize
                    selection-batch-insert-before selection-batch-insert-after
                    selection-batch-paste selection-batch-repeat
                    selection-batch-register-to-kill-ring
                    selection-batch-import-scalar))
  (selection-batch-register-transaction-command command))

(provide 'selection-batch-operators)
;;; selection-batch-operators.el ends here
