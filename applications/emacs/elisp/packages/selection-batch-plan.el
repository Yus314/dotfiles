;;; selection-batch-plan.el --- Immutable edit planning -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Pure, defensively copied edit descriptors and the single-buffer transaction
;; engine.  This layer depends only on the core's narrow session/view interface;
;; it never requires a concrete UI backend and never replays commands.

;;; Code:

(require 'cl-lib)
(require 'selection-batch-core)

(defconst selection-batch-no-update 'selection-batch-no-update
  "Plan slot value meaning that a package global must not be changed.")

(defvar selection-batch-register nil
  "Package-local typed register value (defined fully by the operators layer).")

(defvar selection-batch-last-recipe nil
  "Last semantic operator recipe, or nil.")

(cl-defstruct (selection-batch-recipe
               (:constructor selection-batch--recipe-create)
               (:conc-name selection-batch--recipe-))
  (operator nil :read-only t)
  (arguments nil :read-only t)
  (cardinality-policy nil :read-only t)
  (result-policy nil :read-only t)
  (adapter-id nil :read-only t))

(cl-defstruct (selection-batch-edit
               (:constructor selection-batch--edit-create)
               (:conc-name selection-batch--edit-))
  (selection-id nil :read-only t)
  (logical-index nil :read-only t)
  (beginning nil :read-only t)
  (end nil :read-only t)
  (replacement nil :read-only t)
  (result nil :read-only t)
  (tie-break nil :read-only t))

(cl-defstruct (selection-batch-plan
               (:constructor selection-batch--plan-create)
               (:conc-name selection-batch--plan-))
  (buffer nil :read-only t)
  (source-buffer-tick nil :read-only t)
  (source-generation nil :read-only t)
  (source-narrowing nil :read-only t)
  (edits nil :read-only t)
  (result-policy nil :read-only t)
  (register-update selection-batch-no-update :read-only t)
  (recipe selection-batch-no-update :read-only t))

(defun selection-batch--plan-copy-string (string)
  "Deep-copy STRING, including mutable text-property values."
  (let ((copy (copy-sequence string))
        (position 0))
    (while (< position (length copy))
      (let ((next (or (next-property-change position copy) (length copy)))
            (properties (text-properties-at position copy)))
        (while properties
          (put-text-property position next (pop properties)
                             (selection-batch--plan-copy-value (pop properties))
                             copy))
        (setq position next)))
    copy))

(defun selection-batch--plan-copy-value (value)
  "Recursively copy mutable containers in VALUE.
Buffer and marker objects retain identity.  Strings retain text properties."
  (cond
   ((stringp value) (selection-batch--plan-copy-string value))
   ((consp value)
    (cons (selection-batch--plan-copy-value (car value))
          (selection-batch--plan-copy-value (cdr value))))
   ;; `cl-defstruct' values are records, not ordinary vectors on current Emacs.
   ;; Rebuilding one with `vconcat' loses its type tag and public accessors.
   ((recordp value)
    (let ((copy (copy-sequence value)))
      (dotimes (index (length value))
        (aset copy index
              (selection-batch--plan-copy-value (aref value index))))
      copy))
   ((vectorp value)
    (vconcat (mapcar #'selection-batch--plan-copy-value (append value nil))))
   ((hash-table-p value)
    (let ((copy (copy-hash-table value)))
      (clrhash copy)
      (maphash (lambda (key item)
                 (puthash (selection-batch--plan-copy-value key)
                          (selection-batch--plan-copy-value item) copy))
               value)
      copy))
   (t value)))

(defun selection-batch--recipe-unsafe-value-p (value)
  "Return non-nil when VALUE recursively retains live selection position state."
  (cond
   ((or (markerp value)
        (selection-batch-snapshot-selection-p value)
        (selection-batch-snapshot-p value)
        (selection-batch--live-selection-p value))
    t)
   ((stringp value)
    (let ((position 0) unsafe)
      (while (and (< position (length value)) (not unsafe))
        (let ((properties (text-properties-at position value)))
          (while properties
            (pop properties)
            (when (selection-batch--recipe-unsafe-value-p (pop properties))
              (setq unsafe t))))
        (setq position (or (next-property-change position value)
                           (length value))))
      unsafe))
   ((consp value)
    (or (selection-batch--recipe-unsafe-value-p (car value))
        (selection-batch--recipe-unsafe-value-p (cdr value))))
   ((recordp value)
    (let (unsafe)
      (dotimes (index (length value))
        (when (selection-batch--recipe-unsafe-value-p (aref value index))
          (setq unsafe t)))
      unsafe))
   ((vectorp value)
    (cl-some #'selection-batch--recipe-unsafe-value-p (append value nil)))
   ((hash-table-p value)
    (let (unsafe)
      (maphash
       (lambda (key item)
         (when (or (selection-batch--recipe-unsafe-value-p key)
                   (selection-batch--recipe-unsafe-value-p item))
           (setq unsafe t)))
       value)
      unsafe))))

(defun selection-batch--recipe-check-value (value)
  "Return VALUE, or reject recursively retained markers/selections."
  (when (selection-batch--recipe-unsafe-value-p value)
    (user-error "A semantic recipe cannot retain markers or selection state"))
  value)

(defun selection-batch--recipe-check (recipe)
  "Return valid position-free RECIPE, including its private stored slots."
  (unless (selection-batch-recipe-p recipe)
    (signal 'wrong-type-argument (list 'selection-batch-recipe recipe)))
  (dolist (value (list (selection-batch--recipe-operator recipe)
                       (selection-batch--recipe-arguments recipe)
                       (selection-batch--recipe-cardinality-policy recipe)
                       (selection-batch--recipe-result-policy recipe)
                       (selection-batch--recipe-adapter-id recipe)))
    (selection-batch--recipe-check-value value))
  recipe)

(cl-defun selection-batch-recipe-create
    (&key operator arguments cardinality-policy result-policy adapter-id)
  "Create an immutable semantic recipe with no live positions or markers."
  (unless (symbolp operator)
    (signal 'wrong-type-argument (list 'symbolp operator)))
  (dolist (value (list operator arguments cardinality-policy result-policy adapter-id))
    (selection-batch--recipe-check-value value))
  (selection-batch--recipe-create
   :operator operator
   :arguments (selection-batch--plan-copy-value arguments)
   :cardinality-policy (selection-batch--plan-copy-value cardinality-policy)
   :result-policy (selection-batch--plan-copy-value result-policy)
   :adapter-id (selection-batch--plan-copy-value adapter-id)))

(defun selection-batch-recipe-operator (recipe)
  "Return RECIPE's operator."
  (selection-batch--recipe-check recipe)
  (selection-batch--recipe-operator recipe))
(defun selection-batch-recipe-arguments (recipe)
  "Return a defensive copy of RECIPE's arguments."
  (selection-batch--recipe-check recipe)
  (selection-batch--plan-copy-value (selection-batch--recipe-arguments recipe)))
(defun selection-batch-recipe-cardinality-policy (recipe)
  "Return a defensive copy of RECIPE's cardinality policy."
  (selection-batch--recipe-check recipe)
  (selection-batch--plan-copy-value
   (selection-batch--recipe-cardinality-policy recipe)))
(defun selection-batch-recipe-result-policy (recipe)
  "Return a defensive copy of RECIPE's result policy."
  (selection-batch--recipe-check recipe)
  (selection-batch--plan-copy-value (selection-batch--recipe-result-policy recipe)))
(defun selection-batch-recipe-adapter-id (recipe)
  "Return a defensive copy of RECIPE's adapter identifier."
  (selection-batch--recipe-check recipe)
  (selection-batch--plan-copy-value (selection-batch--recipe-adapter-id recipe)))

(defun selection-batch--copy-result-selection (selection)
  "Return a fresh integer value copied from result SELECTION."
  (unless (selection-batch-snapshot-selection-p selection)
    (user-error "An edit result must be a snapshot selection"))
  (selection-batch-snapshot-selection-create
   :id (selection-batch--plan-copy-value
        (selection-batch-snapshot-selection-id selection))
   :anchor (selection-batch-snapshot-selection-anchor selection)
   :cursor (selection-batch-snapshot-selection-cursor selection)))

(cl-defun selection-batch-edit-create
    (&key selection-id logical-index beginning end replacement result tie-break)
  "Create an immutable edit, defensively copying every compound value."
  (selection-batch--edit-create
   :selection-id (selection-batch--plan-copy-value selection-id)
   :logical-index logical-index :beginning beginning :end end
   :replacement (and (stringp replacement) (copy-sequence replacement))
   :result (and result (selection-batch--copy-result-selection result))
   :tie-break (if (null tie-break) logical-index tie-break)))

(defun selection-batch-edit-selection-id (edit)
  "Return a defensive copy of EDIT's source selection ID."
  (selection-batch--plan-copy-value (selection-batch--edit-selection-id edit)))

(defun selection-batch-edit-logical-index (edit)
  "Return EDIT's source logical index."
  (selection-batch--edit-logical-index edit))

(defun selection-batch-edit-beginning (edit)
  "Return EDIT's source beginning."
  (selection-batch--edit-beginning edit))

(defun selection-batch-edit-end (edit)
  "Return EDIT's source end."
  (selection-batch--edit-end edit))

(defun selection-batch-edit-replacement (edit)
  "Return a copy of EDIT's replacement string."
  (copy-sequence (selection-batch--edit-replacement edit)))

(defun selection-batch-edit-result (edit)
  "Return a copy of EDIT's explicit result selection."
  (selection-batch--copy-result-selection (selection-batch--edit-result edit)))

(defun selection-batch-edit-tie-break (edit)
  "Return EDIT's deterministic same-position tie-break."
  (selection-batch--edit-tie-break edit))

(defun selection-batch--copy-edit (edit)
  "Return an immutable value copy of EDIT."
  (unless (selection-batch-edit-p edit)
    (signal 'wrong-type-argument (list 'selection-batch-edit edit)))
  (selection-batch--edit-create
   :selection-id (selection-batch--plan-copy-value
                  (selection-batch--edit-selection-id edit))
   :logical-index (selection-batch--edit-logical-index edit)
   :beginning (selection-batch--edit-beginning edit)
   :end (selection-batch--edit-end edit)
   :replacement (and (stringp (selection-batch--edit-replacement edit))
                     (copy-sequence (selection-batch--edit-replacement edit)))
   :result (and (selection-batch--edit-result edit)
                (selection-batch--copy-result-selection
                 (selection-batch--edit-result edit)))
   :tie-break (selection-batch--edit-tie-break edit)))

(defun selection-batch--edit-before-p (left right)
  "Return non-nil when LEFT precedes RIGHT in bottom-up application order."
  (let ((lb (selection-batch--edit-beginning left))
        (rb (selection-batch--edit-beginning right))
        (lt (selection-batch--edit-tie-break left))
        (rt (selection-batch--edit-tie-break right)))
    (or (> lb rb)
        (and (= lb rb)
             (or (> lt rt)
                 (and (= lt rt)
                      (> (selection-batch--edit-logical-index left)
                         (selection-batch--edit-logical-index right))))))))

(defun selection-batch--copy-result-snapshot (snapshot)
  "Return a defensive copy of result SNAPSHOT."
  (unless (selection-batch-snapshot-p snapshot)
    (user-error "A plan requires an explicit result snapshot"))
  (selection-batch-snapshot-create
   :buffer (selection-batch-snapshot-buffer snapshot)
   :buffer-tick (selection-batch-snapshot-buffer-tick snapshot)
   :generation (selection-batch-snapshot-generation snapshot)
   :primary-id (selection-batch--plan-copy-value
                (selection-batch-snapshot-primary-id snapshot))
   :narrowing (selection-batch-snapshot-narrowing snapshot)
   :selections (selection-batch-snapshot-selections snapshot)))

(cl-defun selection-batch-plan-create
    (&key buffer source-buffer-tick source-generation source-narrowing edits
          result-policy (register-update selection-batch-no-update)
          (recipe selection-batch-no-update) edits-ordered-p)
  "Create an immutable plan with copied edits in deterministic apply order."
  (let ((copied (mapcar #'selection-batch--copy-edit (append edits nil))))
    (when edits-ordered-p
      (cl-loop for left on copied while (cdr left)
               unless (selection-batch--edit-before-p (car left) (cadr left))
               do (user-error "Preordered plan edits are out of order")))
    (selection-batch--plan-create
     :buffer buffer :source-buffer-tick source-buffer-tick
     :source-generation source-generation
     :source-narrowing (selection-batch--plan-copy-value source-narrowing)
     :edits (vconcat (if edits-ordered-p
                         copied
                       (sort copied #'selection-batch--edit-before-p)))
     :result-policy (selection-batch--copy-result-snapshot result-policy)
     :register-update (selection-batch--plan-copy-value register-update)
     :recipe (selection-batch--plan-copy-value recipe))))

(defun selection-batch-plan-buffer (plan) (selection-batch--plan-buffer plan))
(defun selection-batch-plan-source-buffer-tick (plan)
  (selection-batch--plan-source-buffer-tick plan))
(defun selection-batch-plan-source-generation (plan)
  (selection-batch--plan-source-generation plan))
(defun selection-batch-plan-source-narrowing (plan)
  (selection-batch--plan-copy-value (selection-batch--plan-source-narrowing plan)))
(defun selection-batch-plan-edits (plan)
  (vconcat (mapcar #'selection-batch--copy-edit
                   (append (selection-batch--plan-edits plan) nil))))
(defun selection-batch-plan-result-policy (plan)
  (selection-batch--copy-result-snapshot
   (selection-batch--plan-result-policy plan)))
(defun selection-batch-plan-register-update (plan)
  (selection-batch--plan-copy-value (selection-batch--plan-register-update plan)))
(defun selection-batch-plan-recipe (plan)
  (selection-batch--plan-copy-value (selection-batch--plan-recipe plan)))

(defun selection-batch--plan-error (edit format-string &rest arguments)
  "Signal a structured user error naming EDIT and its invalid reason."
  (apply #'user-error
         (concat "Selection %S: " format-string)
         (selection-batch--edit-selection-id edit) arguments))

(defun selection-batch--edit-read-only-p (edit)
  "Return non-nil if EDIT touches read-only text properties."
  (let ((beginning (selection-batch--edit-beginning edit))
        (end (selection-batch--edit-end edit)))
    (if (< beginning end)
        (text-property-not-all beginning end 'read-only nil)
      (let* ((left (and (> beginning (point-min)) (1- beginning)))
             (right (and (< beginning (point-max)) beginning))
             (rear-nonsticky
              (and left (get-text-property left 'rear-nonsticky)))
             (front-sticky
              (and right (get-text-property right 'front-sticky))))
        ;; Insertion properties are rear-sticky and front-nonsticky by default.
        (or (and left (get-text-property left 'read-only)
                 (not (or (eq rear-nonsticky t)
                          (and (listp rear-nonsticky)
                               (memq 'read-only rear-nonsticky)))))
            (and right (get-text-property right 'read-only)
                 (or (eq front-sticky t)
                     (and (listp front-sticky)
                          (memq 'read-only front-sticky)))))))))

(defun selection-batch--edits-collide-p (left right)
  "Return non-nil when LEFT and RIGHT do not denote independent edits.
Nonempty ranges are half-open.  An insertion at a range's beginning or in its
interior collides; insertion at its end is adjacent and is allowed."
  (let ((lb (selection-batch--edit-beginning left))
        (le (selection-batch--edit-end left))
        (rb (selection-batch--edit-beginning right))
        (re (selection-batch--edit-end right)))
    (cond
     ((= lb le) (and (< rb re) (<= rb lb) (< lb re)))
     ((= rb re) (and (<= lb rb) (< rb le)))
     (t (and (< lb re) (< rb le))))))

(defun selection-batch--validate-result (plan source expected-max)
  "Validate PLAN's explicit result against SOURCE and EXPECTED-MAX."
  (let* ((result (selection-batch--plan-result-policy plan))
         (source-selections (selection-batch-snapshot-selections source))
         (result-selections (selection-batch-snapshot-selections result))
         (edits (selection-batch--plan-edits plan))
         (minimum (car (selection-batch--plan-source-narrowing plan)))
         (source-ids (make-hash-table :test #'equal)))
    (dolist (selection (append source-selections nil))
      (puthash (selection-batch-snapshot-selection-id selection) t source-ids))
    (unless (and (eq (selection-batch-snapshot-buffer result)
                     (selection-batch--plan-buffer plan))
                 (or (= (length result-selections) (length edits))
                     (and (= (length edits) 0)
                          (not (eq (selection-batch--plan-register-update plan)
                                   selection-batch-no-update))
                          (equal source-selections result-selections))))
      (user-error "Plan edit/source/result cardinality mismatch"))
    (dolist (edit (append edits nil))
      (let* ((index (selection-batch--edit-logical-index edit))
             (id (selection-batch--edit-selection-id edit)))
        (unless (and (integerp index) (<= 0 index)
                     (< index (length result-selections)))
          (selection-batch--plan-error edit "invalid logical index"))
        (unless (and (gethash id source-ids)
                     (equal id (selection-batch-snapshot-selection-id
                                (aref result-selections index)))
                     (equal (selection-batch--edit-result edit)
                            (aref result-selections index)))
          (selection-batch--plan-error edit "source/result identity mismatch"))))
    (dolist (selection (append result-selections nil))
      (unless (and (integerp (selection-batch-snapshot-selection-anchor selection))
                   (integerp (selection-batch-snapshot-selection-cursor selection))
                   (<= minimum (selection-batch-selection-beginning selection))
                   (<= (selection-batch-selection-end selection) expected-max))
        (user-error "Selection %S: result is outside post-edit narrowing"
                    (selection-batch-snapshot-selection-id selection))))))

(defun selection-batch-validate-plan (plan &optional source)
  "Purely validate PLAN against SOURCE and live buffer/session state.
Return PLAN without modifying text, markers, globals, history, or views."
  (unless (selection-batch-plan-p plan)
    (signal 'wrong-type-argument (list 'selection-batch-plan plan)))
  (let* ((buffer (selection-batch--plan-buffer plan))
         (session selection-batch--session))
    (unless (buffer-live-p buffer) (user-error "Plan buffer is dead"))
    (unless (eq buffer (current-buffer)) (user-error "Plan belongs to another buffer"))
    (when (and session (eq (selection-batch--session-state session) 'applying))
      (user-error "A selection plan is already being applied"))
    (setq source (or source (selection-batch-current-snapshot)))
    (unless (and (selection-batch-snapshot-p source)
                 (eq buffer (selection-batch-snapshot-buffer source)))
      (user-error "Plan source belongs to another buffer"))
    (unless (equal (selection-batch--plan-source-narrowing plan)
                   (selection-batch-snapshot-narrowing source))
      (user-error "Plan source narrowing is stale"))
    (unless (equal (selection-batch--plan-source-narrowing plan)
                   (cons (point-min) (point-max)))
      (user-error "Buffer narrowing changed after planning"))
    (unless (and (= (selection-batch--plan-source-buffer-tick plan)
                    (selection-batch-snapshot-buffer-tick source))
                 (= (selection-batch--plan-source-buffer-tick plan)
                    (buffer-chars-modified-tick)))
      (user-error "Buffer changed after planning"))
    (unless (and (= (selection-batch--plan-source-generation plan)
                    (selection-batch-snapshot-generation source))
                 session (eq session selection-batch--session)
                 (= (selection-batch--plan-source-generation plan)
                    (selection-batch--session-generation session)))
      (user-error "Selection generation changed after planning"))
    (when buffer-read-only (user-error "Plan buffer is read-only"))
    (let ((minimum (point-min)) (maximum (point-max)) (delta 0)
          (edits (selection-batch--plan-edits plan))
          (seen-indices (make-hash-table :test #'eql)))
      (dolist (edit (append edits nil))
        (unless (and (integerp (selection-batch--edit-beginning edit))
                     (integerp (selection-batch--edit-end edit))
                     (<= minimum (selection-batch--edit-beginning edit))
                     (<= (selection-batch--edit-beginning edit)
                         (selection-batch--edit-end edit))
                     (<= (selection-batch--edit-end edit) maximum))
          (selection-batch--plan-error edit "range is outside narrowing"))
        (unless (stringp (selection-batch--edit-replacement edit))
          (selection-batch--plan-error edit "replacement is not a string"))
        (unless (and (integerp (selection-batch--edit-tie-break edit))
                     (integerp (selection-batch--edit-logical-index edit)))
          (selection-batch--plan-error edit "tie-break/index is not an integer"))
        (when (gethash (selection-batch--edit-logical-index edit) seen-indices)
          (selection-batch--plan-error edit "logical index is duplicated"))
        (puthash (selection-batch--edit-logical-index edit) t seen-indices)
        (when (selection-batch--edit-read-only-p edit)
          (selection-batch--plan-error edit "range has a read-only text property"))
        (cl-incf delta (- (length (selection-batch--edit-replacement edit))
                          (- (selection-batch--edit-end edit)
                             (selection-batch--edit-beginning edit)))))
      ;; PLAN stores edits by descending beginning.  Reverse once, then validate
      ;; all overlap and insertion/range collisions in one ordered interval pass.
      (let ((furthest-end minimum) active same-begin insert-at-begin)
        (dolist (edit (reverse (append edits nil)))
          (let ((beginning (selection-batch--edit-beginning edit))
                (end (selection-batch--edit-end edit)))
            (unless (equal beginning same-begin)
              (setq same-begin beginning insert-at-begin nil))
            (when (< beginning furthest-end)
              (selection-batch--plan-error
               edit "edit collides with selection %S"
               (selection-batch--edit-selection-id active)))
            (if (= beginning end)
                (setq insert-at-begin edit)
              (when insert-at-begin
                (selection-batch--plan-error
                 edit "edit collides with selection %S"
                 (selection-batch--edit-selection-id insert-at-begin)))
              (when (> end furthest-end)
                (setq furthest-end end active edit))))))
      (selection-batch--validate-result plan source (+ maximum delta)))
    plan))

(defvar-local selection-batch--change-ledger nil
  "Dynamically bound expected change notification for plan application.")

(defvar-local selection-batch--trusted-property-rollbacks nil
  "Rollback refresh functions registered by trusted property adapters.")

(cl-defstruct (selection-batch--property-adapter
               (:constructor selection-batch--property-adapter-create))
  "Capability for one exact trusted property refresher and its rollback."
  function rollback validator)

(defvar selection-batch--property-adapters nil
  "Registered trusted property-refresh capabilities.")

(defvar selection-batch--plan-application-active nil
  "Non-nil throughout a selection plan application lifecycle.")

(defun selection-batch--ensure-property-adapters-mutable ()
  "Reject property-adapter mutation during plan application."
  (when selection-batch--plan-application-active
    (error "Cannot mutate property adapters during plan application")))

(defun selection-batch--register-property-adapter
    (function rollback &optional validator)
  "Register exact FUNCTION with ROLLBACK and optional VALIDATOR capability."
  (selection-batch--ensure-property-adapters-mutable)
  (unless (functionp function)
    (signal 'wrong-type-argument (list 'functionp function)))
  (unless (functionp rollback)
    (signal 'wrong-type-argument (list 'functionp rollback)))
  (when (and validator (not (functionp validator)))
    (signal 'wrong-type-argument (list 'functionp validator)))
  (let ((adapter (selection-batch--property-adapter-create
                  :function function :rollback rollback
                  :validator validator)))
    (push adapter selection-batch--property-adapters)
    adapter))

(defun selection-batch--unregister-property-adapter (adapter)
  "Revoke trusted property-refresh capability ADAPTER."
  (selection-batch--ensure-property-adapters-mutable)
  (setq selection-batch--property-adapters
        (delq adapter selection-batch--property-adapters)))

(defun selection-batch--validate-property-adapters ()
  "Fail before mutation when any registered adapter has become unsafe."
  (dolist (adapter selection-batch--property-adapters)
    (let ((validator (selection-batch--property-adapter-validator adapter)))
      (when validator (funcall validator adapter)))))

(defun selection-batch--change-ledger-before (beginning end)
  "Open the expected change notification at BEGINNING and END."
  ;; Emacs normally inhibits recursive modification hooks while calling a
  ;; change hook.  Re-enable them before ordinary hooks run so their nested
  ;; edits cannot be silent to this transaction guard.
  (setq inhibit-modification-hooks nil)
  (unless (and selection-batch--change-ledger
               (eq (plist-get selection-batch--change-ledger :phase) 'before)
               (= beginning (plist-get selection-batch--change-ledger :beginning))
               (= end (plist-get selection-batch--change-ledger :before-end)))
    (error "Unexpected or nested buffer change before (%S %S)" beginning end))
  (setf (plist-get selection-batch--change-ledger :phase) 'before-hooks
        (plist-get selection-batch--change-ledger :modified-tick)
        (buffer-modified-tick)
        (plist-get selection-batch--change-ledger :chars-tick)
        (buffer-chars-modified-tick)))

(defun selection-batch--change-ledger-before-last (&rest _)
  "Close the before-change phase after every ordinary hook has run."
  (unless (and (eq (plist-get selection-batch--change-ledger :phase)
                   'before-hooks)
               (equal (cons (point-min) (point-max))
                      (plist-get selection-batch--change-ledger :narrowing))
               (= (buffer-modified-tick)
                  (plist-get selection-batch--change-ledger :modified-tick))
               (= (buffer-chars-modified-tick)
                  (plist-get selection-batch--change-ledger :chars-tick)))
    (error "A before-change hook performed an unexpected buffer change"))
  (setf (plist-get selection-batch--change-ledger :phase) 'after))

(defun selection-batch--change-ledger-after-first (beginning end old-length)
  "Validate the leading after-change notification arguments."
  (setq inhibit-modification-hooks nil)
  (unless (and selection-batch--change-ledger
               (eq (plist-get selection-batch--change-ledger :phase) 'after)
               (= beginning (plist-get selection-batch--change-ledger :beginning))
               (= end (plist-get selection-batch--change-ledger :after-end))
               (= old-length (plist-get selection-batch--change-ledger :old-length)))
    (error "Unexpected buffer change after (%S %S %S)"
           beginning end old-length))
  (setf (plist-get selection-batch--change-ledger :phase) 'after-hooks
        (plist-get selection-batch--change-ledger :modified-tick)
        (buffer-modified-tick)
        (plist-get selection-batch--change-ledger :chars-tick)
        (buffer-chars-modified-tick)))

(defun selection-batch--call-trusted-property-refresh
    (adapter function arguments)
  "Call ADAPTER's trusted property FUNCTION with ARGUMENTS.

Outside an active plan notification, call FUNCTION normally.  During one,
FUNCTION may change only undo-suppressed properties: characters, narrowing,
modified state, undo ownership, buffer ownership, and ledger phase must stay
unchanged.  ADAPTER must be a registered capability for this exact FUNCTION;
ordinary change hooks cannot nominate arbitrary functions during a plan."
  (unless (and (memq adapter selection-batch--property-adapters)
               (eq function
                   (selection-batch--property-adapter-function adapter)))
    (error "Unregistered or mismatched trusted property adapter"))
  (if (not (and selection-batch--change-ledger
                (eq (plist-get selection-batch--change-ledger :phase)
                    'after-hooks)))
      (apply function arguments)
    (let ((buffer (current-buffer))
          (ledger selection-batch--change-ledger)
          (narrowing (cons (point-min) (point-max)))
          (modified-p (buffer-modified-p))
          (undo-list buffer-undo-list)
          (modified-tick (buffer-modified-tick))
          (chars-tick (buffer-chars-modified-tick)))
      (unless (and
               (equal narrowing
                      (plist-get selection-batch--change-ledger
                                 :after-narrowing))
               (= modified-tick
                  (plist-get selection-batch--change-ledger :modified-tick))
               (= chars-tick
                  (plist-get selection-batch--change-ledger :chars-tick)))
        (error "Dirty ledger before trusted property refresh"))
      ;; Register compensation before calling the trusted refresher.  It may
      ;; signal after a partial undo-suppressed property mutation.
      (cl-pushnew (selection-batch--property-adapter-rollback adapter)
                  selection-batch--trusted-property-rollbacks
                  :test #'eq)
      (prog1
          (save-current-buffer
            (unwind-protect
                (apply function arguments)
              (unless (and (eq buffer (current-buffer))
                           (buffer-live-p buffer)
                           (with-current-buffer buffer
                             (and (eq ledger selection-batch--change-ledger)
                                  (eq (plist-get ledger :phase) 'after-hooks)
                                  (equal narrowing
                                         (cons (point-min) (point-max)))
                                  (= chars-tick (buffer-chars-modified-tick))
                                  (eq undo-list buffer-undo-list)
                                  (equal modified-p (buffer-modified-p)))))
                (error "Trusted property refresh changed protected state"))))
        ;; Approve only the property tick produced by this exact wrapper.
        ;; Any silent mutation in an earlier or later ordinary hook remains
        ;; visible to this wrapper or the trailing ledger sentinel.
        (setf (plist-get ledger :modified-tick) (buffer-modified-tick))))))

(defun selection-batch--change-ledger-after-last (&rest _)
  "Close a notification after every ordinary after-change hook has run."
  (unless (and (eq (plist-get selection-batch--change-ledger :phase) 'after-hooks)
               (equal (cons (point-min) (point-max))
                      (plist-get selection-batch--change-ledger
                                 :after-narrowing))
               (= (buffer-modified-tick)
                  (plist-get selection-batch--change-ledger :modified-tick))
               (= (buffer-chars-modified-tick)
                  (plist-get selection-batch--change-ledger :chars-tick)))
    (error "Missing or nested buffer change notification"))
  (setf (plist-get selection-batch--change-ledger :phase) 'done))

(defun selection-batch--run-trusted-property-rollbacks ()
  "Run every registered derived-property rollback refresh, then clear them."
  (let (condition)
    (dolist (function (prog1 selection-batch--trusted-property-rollbacks
                        (setq selection-batch--trusted-property-rollbacks nil)))
      (condition-case err
          (funcall function)
        ((error quit) (unless condition (setq condition err)))))
    (when condition
      (signal (car condition) (cdr condition)))))

(defun selection-batch--change-ledger-call (function expected)
  "Call FUNCTION while accepting exactly EXPECTED, or no notification if nil."
  (let* ((narrowing (cons (point-min) (point-max)))
         (after-narrowing
          (and expected
               (cons (car narrowing)
                     (+ (cdr narrowing)
                        (- (plist-get expected :after-end)
                           (plist-get expected :beginning)
                           (plist-get expected :old-length))))))
         (selection-batch--change-ledger
          (and expected
               (append expected
                       (list :phase 'before :narrowing narrowing
                             :after-narrowing after-narrowing))))
         (modified-tick (buffer-modified-tick))
         (chars-tick (buffer-chars-modified-tick)))
    ;; A hook is not allowed to transfer ownership of the accessible portion.
    ;; Restore it even when the hook signals before the ledger can reject it.
    (save-restriction (funcall function))
    (unless (if expected
                (and (eq (plist-get selection-batch--change-ledger :phase) 'done)
                     (equal after-narrowing (cons (point-min) (point-max))))
              (and (null selection-batch--change-ledger)
                   (equal narrowing (cons (point-min) (point-max)))
                   (= (buffer-modified-tick) modified-tick)
                   (= (buffer-chars-modified-tick) chars-tick)))
      (error "Invalid change ledger phase=%S modified-delta=%S chars-delta=%S"
             (and selection-batch--change-ledger
                  (plist-get selection-batch--change-ledger :phase))
             (- (buffer-modified-tick) modified-tick)
             (- (buffer-chars-modified-tick) chars-tick)))))

(defun selection-batch--plan-primitive-edit (edit)
  "Apply one already validated EDIT and expose guarded ordinary change hooks."
  (let* ((beginning (selection-batch--edit-beginning edit))
         (end (selection-batch--edit-end edit))
         (replacement (selection-batch--edit-replacement edit))
         (deleted (- end beginning))
         (inserted (length replacement)))
    (selection-batch--change-ledger-call
     (lambda () (delete-region beginning end))
     (and (> deleted 0)
          (list :beginning beginning :before-end end :after-end beginning
                :old-length deleted)))
    (goto-char beginning)
    (selection-batch--change-ledger-call
     (lambda () (insert replacement))
     (and (> inserted 0)
          (list :beginning beginning :before-end beginning
                :after-end (+ beginning inserted) :old-length 0)))))

(defvar selection-batch--plan-primitive-edit-function
  #'selection-batch--plan-primitive-edit
  "Dynamically bindable primitive-edit failure injection point.")

(defun selection-batch--plan-result-snapshot (plan)
  "Materialize PLAN's explicit result for the now-edited accessible buffer."
  (let ((declared (selection-batch--plan-result-policy plan)))
    (selection-batch-snapshot-create
     :buffer (current-buffer) :buffer-tick (buffer-chars-modified-tick)
     :generation (1+ (selection-batch--plan-source-generation plan))
     :primary-id (selection-batch-snapshot-primary-id declared)
     :narrowing (cons (point-min) (point-max))
     :selections (selection-batch-snapshot-selections declared))))

(defun selection-batch--plan-install-result (session result)
  "Install RESULT's integer model in SESSION, retaining old live markers."
  (let* ((selections (selection-batch-snapshot-selections result))
         (primary (selection-batch-snapshot-primary-id result))
         (new-live (selection-batch--make-live-selections
                    (current-buffer) selections primary)))
    (setf (selection-batch--session-selections session) new-live
          (selection-batch--session-primary-id session) primary
          (selection-batch--session-generation session)
          (selection-batch-snapshot-generation result))
    (selection-batch--project-snapshot-primary session result)
    new-live))

(defvar selection-batch--plan-install-result-function
  #'selection-batch--plan-install-result
  "Dynamically bindable result-install failure injection point.")

(defun selection-batch--plan-refresh-view (session)
  "Refresh SESSION through the core's current narrow view interface."
  (selection-batch--refresh-derived-view session))

(defvar selection-batch--plan-refresh-view-function
  #'selection-batch--plan-refresh-view
  "Dynamically bindable view failure injection point.")

(defun selection-batch--restore-live-markers (session snapshot live)
  "Restore LIVE marker objects and primary projection from integer SNAPSHOT."
  (setf (selection-batch--session-selections session) live
        (selection-batch--session-primary-id session)
        (selection-batch-snapshot-primary-id snapshot))
  (dolist (selection (append live nil))
    (unless (equal (selection-batch--live-selection-id selection)
                   (selection-batch-snapshot-primary-id snapshot))
      (let ((value (selection-batch--selection-by-id
                    (selection-batch-snapshot-selections snapshot)
                    (selection-batch--live-selection-id selection))))
        (unless value (error "Compensation selection is absent"))
        (set-marker (selection-batch--live-selection-anchor-marker selection)
                    (selection-batch-snapshot-selection-anchor value)
                    (selection-batch--session-buffer session))
        (set-marker (selection-batch--live-selection-cursor-marker selection)
                    (selection-batch-snapshot-selection-cursor value)
                    (selection-batch--session-buffer session)))))
  (selection-batch--project-snapshot-primary session snapshot))

(defun selection-batch--apply-update (current update)
  "Return CURRENT or a defensive copy of UPDATE according to sentinel policy."
  (if (eq update selection-batch-no-update)
      current
    (selection-batch--plan-copy-value update)))

(defun selection-batch--commit-watched-globals
    (prepared-register prepared-recipe)
  "Assign prepared globals, then reject silent watcher mutation."
  (setq selection-batch-register
        (selection-batch--plan-copy-value prepared-register)
        selection-batch-last-recipe
        (selection-batch--plan-copy-value prepared-recipe))
  (unless (and (equal selection-batch-register prepared-register)
               (equal selection-batch-last-recipe prepared-recipe))
    (error "A variable watcher mutated selection-batch committed state")))

(defun selection-batch--restore-watched-global (symbol value)
  "Restore SYMBOL to a copy of VALUE without watcher re-corruption."
  (let ((watchers (and (fboundp 'get-variable-watchers)
                       (get-variable-watchers symbol))))
    (unwind-protect
        (progn
          (dolist (watcher watchers)
            (remove-variable-watcher symbol watcher))
          (set symbol (selection-batch--plan-copy-value value)))
      (dolist (watcher watchers)
        (add-variable-watcher symbol watcher)))))

(defun selection-batch-apply-plan (plan)
  "Validate and atomically apply PLAN as one ordinary undo unit.
Every failure, including `quit', first rolls text back and then compensates all
package state from copied values.  Command hooks are never replayed."
  (let* ((session (selection-batch--owner-session t)))
    ;; Reentry is checked before stale tick diagnostics so callers receive the
    ;; useful lifecycle error even after an outer primitive changed text.
    (when (eq (selection-batch--session-state session) 'applying)
      (user-error "A selection plan is already being applied"))
    (let ((selection-batch--plan-application-active t))
      (selection-batch-validate-plan plan)
      (selection-batch--validate-property-adapters)
      (let* ((before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (old-primary (selection-batch--plan-copy-value
                         (selection-batch--session-primary-id session)))
           (old-history (selection-batch--session-history session))
           (old-redo (selection-batch--session-redo session))
           (old-generation (selection-batch--session-generation session))
           (old-state (selection-batch--session-state session))
           ;; Change hooks and variable watchers are untrusted.  Compensation
           ;; must not share their mutable register/recipe containers.
           (old-register (selection-batch--plan-copy-value
                          selection-batch-register))
           (old-recipe (selection-batch--plan-copy-value
                        selection-batch-last-recipe))
           (old-refresh selection-batch--view-refresh-function)
           (old-destroy selection-batch--view-destroy-function)
           (selection-batch--trusted-property-rollbacks nil)
           ;; Prepare every value that can fail validation before touching text.
           (edits (vconcat (mapcar #'selection-batch--copy-edit
                                   (append (selection-batch--plan-edits plan) nil))))
           (future-register
            (selection-batch--apply-update
             selection-batch-register (selection-batch--plan-register-update plan)))
           (future-recipe
            (selection-batch--apply-update
             selection-batch-last-recipe (selection-batch--plan-recipe plan)))
           condition completed compensation-attempted result
           (restore
            (lambda ()
              (let (restoration-error)
                (condition-case err
                    (progn
                      (when (and (selection-batch--session-selections session)
                                 (not (eq (selection-batch--session-selections
                                           session)
                                          old-live)))
                        (selection-batch--detach-selections
                         (selection-batch--session-selections session)))
                      (selection-batch--restore-live-markers
                       session before old-live)
                      (setf (selection-batch--session-history session) old-history
                            (selection-batch--session-redo session) old-redo
                            (selection-batch--session-generation session)
                            old-generation
                            (selection-batch--session-state session) old-state
                            (selection-batch--session-primary-id session)
                            old-primary)
                      (selection-batch--restore-watched-global
                       'selection-batch-register old-register)
                      (selection-batch--restore-watched-global
                       'selection-batch-last-recipe old-recipe)
                      (setq selection-batch--view-refresh-function old-refresh
                            selection-batch--view-destroy-function old-destroy)
                      (selection-batch--run-trusted-property-rollbacks)
                      (when (functionp old-refresh)
                        (funcall old-refresh session)))
                  ((error quit) (setq restoration-error err)))
                restoration-error)))
           (compensate
            (lambda ()
              (let (returned restoration-error)
                (unwind-protect
                    (progn
                      (setq restoration-error (funcall restore)
                            returned t)
                      restoration-error)
                  (unless returned
                    ;; Publish the fail-closed state before invoking any
                    ;; potentially hostile teardown callback.  Direct marker
                    ;; detachment also makes the abandoned session unusable if
                    ;; callback cleanup itself exits nonlocally.
                    (setq selection-batch--session nil)
                    (selection-batch--detach-selections
                     (selection-batch--session-selections session))
                    (unwind-protect
                        (ignore-errors
                          (selection-batch--cleanup session nil t))
                      (error "Plan compensation exited nonlocally"))))))))
      (undo-boundary)
      (unwind-protect
          (progn
            (condition-case err
                (setq result
                      (atomic-change-group
            (setf (selection-batch--session-state session) 'applying)
            ;; Original-coordinate edits must not pay for shifting every
            ;; secondary marker and overlay after every primitive mutation.
            ;; BEFORE retains all integer positions for compensation.
            (selection-batch--destroy-derived-view session)
            (selection-batch--detach-selections old-live)
            (add-hook 'before-change-functions
                        #'selection-batch--change-ledger-before
                        most-negative-fixnum t)
              (add-hook 'before-change-functions
                        #'selection-batch--change-ledger-before-last
                        most-positive-fixnum t)
              (add-hook 'after-change-functions
                        #'selection-batch--change-ledger-after-first
                        most-negative-fixnum t)
              (add-hook 'after-change-functions
                        #'selection-batch--change-ledger-after-last
                        most-positive-fixnum t)
              ;; Remove the sentinels before `atomic-change-group' performs
              ;; rollback: compensation changes are not plan primitives.
              (unwind-protect
                  (dolist (edit (append edits nil))
                    (funcall selection-batch--plan-primitive-edit-function edit))
                (remove-hook 'before-change-functions
                             #'selection-batch--change-ledger-before t)
                (remove-hook 'before-change-functions
                             #'selection-batch--change-ledger-before-last t)
                (remove-hook 'after-change-functions
                             #'selection-batch--change-ledger-after-first t)
                (remove-hook 'after-change-functions
                             #'selection-batch--change-ledger-after-last t))
            (let ((result (selection-batch--plan-result-snapshot plan)))
              (funcall selection-batch--plan-install-result-function
                       session result)
              (funcall selection-batch--plan-refresh-view-function session))
            ;; All package commits, especially watcher-capable globals, remain
            ;; inside both the text rollback and state compensation boundary.
            ;; Text edits invalidate integer-only selection history.  Treat every
            ;; successful plan as a barrier while rollback still restores both.
            (setf (selection-batch--session-history session) nil
                  (selection-batch--session-redo session) nil
                  (selection-batch--session-state session) 'set)
                        (selection-batch--commit-watched-globals
                         future-register future-recipe)
                        (selection-batch--detach-selections old-live)
                        ;; These operations can run hooks or validate live
                        ;; state, so they must precede transaction commit.
                        (undo-boundary)
                        (selection-batch-current-snapshot))
                      completed t)
              ((error quit) (setq condition err)))
            (if condition
                (let ((restoration-error
                       (progn
                         (setq compensation-attempted t)
                         (funcall compensate))))
                  (when restoration-error
                    (setq selection-batch--session nil)
                    (selection-batch--detach-selections
                     (selection-batch--session-selections session))
                    (ignore-errors (selection-batch--cleanup session nil t))
                    (error "Plan failed (%S); compensation failed (%S)"
                           condition restoration-error))
                  (signal (car condition) (cdr condition)))
              result))
        ;; This cleanup also runs for a clean `throw', after the atomic change
        ;; group has restored text but before the original throw propagates.
        (unless (or completed compensation-attempted)
          (setq compensation-attempted t)
          (let ((restoration-error (funcall compensate)))
            (when restoration-error
              (setq selection-batch--session nil)
              (selection-batch--detach-selections
               (selection-batch--session-selections session))
              (ignore-errors (selection-batch--cleanup session nil t))
              (error "Plan compensation failed during nonlocal exit (%S)"
                     restoration-error)))))))))

(provide 'selection-batch-plan)
;;; selection-batch-plan.el ends here
