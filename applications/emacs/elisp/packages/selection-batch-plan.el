;;; selection-batch-plan.el --- Immutable atomic edit plans -*- lexical-binding: t; -*-

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

(defun selection-batch--plan-copy-value (value)
  "Recursively copy mutable containers in VALUE.
Buffer and marker objects retain identity.  Strings retain text properties."
  (cond
   ((stringp value) (copy-sequence value))
   ((consp value)
    (cons (selection-batch--plan-copy-value (car value))
          (selection-batch--plan-copy-value (cdr value))))
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
          (recipe selection-batch-no-update))
  "Create an immutable plan with copied edits in deterministic apply order."
  (let ((copied (mapcar #'selection-batch--copy-edit (append edits nil))))
    (selection-batch--plan-create
     :buffer buffer :source-buffer-tick source-buffer-tick
     :source-generation source-generation
     :source-narrowing (selection-batch--plan-copy-value source-narrowing)
     :edits (vconcat (sort copied #'selection-batch--edit-before-p))
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
      (or (and (< beginning (point-max))
               (get-char-property beginning 'read-only))
          (and (> beginning (point-min))
               (get-char-property (1- beginning) 'read-only))))))

(defun selection-batch--validate-result (plan source expected-max)
  "Validate PLAN's explicit result against SOURCE and EXPECTED-MAX."
  (let* ((result (selection-batch--plan-result-policy plan))
         (source-selections (selection-batch-snapshot-selections source))
         (result-selections (selection-batch-snapshot-selections result))
         (edits (selection-batch--plan-edits plan))
         (minimum (car (selection-batch--plan-source-narrowing plan))))
    (unless (and (eq (selection-batch-snapshot-buffer result)
                     (selection-batch--plan-buffer plan))
                 (= (length source-selections) (length edits))
                 (= (length result-selections) (length edits)))
      (user-error "Plan edit/source/result cardinality mismatch"))
    (dolist (edit (append edits nil))
      (let* ((index (selection-batch--edit-logical-index edit))
             (id (selection-batch--edit-selection-id edit)))
        (unless (and (integerp index) (<= 0 index) (< index (length edits)))
          (selection-batch--plan-error edit "invalid logical index"))
        (unless (and (equal id (selection-batch-snapshot-selection-id
                                (aref source-selections index)))
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
          (edits (selection-batch--plan-edits plan)) seen-indices)
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
        (when (member (selection-batch--edit-logical-index edit) seen-indices)
          (selection-batch--plan-error edit "logical index is duplicated"))
        (push (selection-batch--edit-logical-index edit) seen-indices)
        (when (selection-batch--edit-read-only-p edit)
          (selection-batch--plan-error edit "range has a read-only text property"))
        (cl-incf delta (- (length (selection-batch--edit-replacement edit))
                          (- (selection-batch--edit-end edit)
                             (selection-batch--edit-beginning edit)))))
      (cl-loop for tail on (append edits nil)
               for left = (car tail)
               when (< (selection-batch--edit-beginning left)
                       (selection-batch--edit-end left))
               do (dolist (right (cdr tail))
                    (when (and (< (selection-batch--edit-beginning right)
                                  (selection-batch--edit-end right))
                               (< (selection-batch--edit-beginning left)
                                  (selection-batch--edit-end right))
                               (< (selection-batch--edit-beginning right)
                                  (selection-batch--edit-end left)))
                      (selection-batch--plan-error
                       left "nonempty range overlaps selection %S"
                       (selection-batch--edit-selection-id right)))))
      (selection-batch--validate-result plan source (+ maximum delta)))
    plan))

(defun selection-batch--plan-primitive-edit (edit)
  "Apply one already validated EDIT and expose ordinary change hooks."
  (let ((beginning (selection-batch--edit-beginning edit))
        (end (selection-batch--edit-end edit))
        (replacement (selection-batch--edit-replacement edit)))
    (delete-region beginning end)
    (goto-char beginning)
    (insert replacement)))

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

(defun selection-batch-apply-plan (plan)
  "Validate and atomically apply PLAN as one ordinary undo unit.
Every failure, including `quit', first rolls text back and then compensates all
package state from integer values.  Command hooks are never replayed."
  (let* ((session (selection-batch--owner-session t)))
    ;; Reentry is checked before stale tick diagnostics so callers receive the
    ;; useful lifecycle error even after an outer primitive changed text.
    (when (eq (selection-batch--session-state session) 'applying)
      (user-error "A selection plan is already being applied"))
    (selection-batch-validate-plan plan)
    (let* ((before (selection-batch-current-snapshot))
           (old-live (selection-batch--session-selections session))
           (old-primary (selection-batch--session-primary-id session))
           (old-history (selection-batch--session-history session))
           (old-redo (selection-batch--session-redo session))
           (old-generation (selection-batch--session-generation session))
           (old-state (selection-batch--session-state session))
           (old-register selection-batch-register)
           (old-recipe selection-batch-last-recipe)
           (old-refresh selection-batch--view-refresh-function)
           (old-destroy selection-batch--view-destroy-function)
           ;; Copy every replacement before setting applying or touching text.
           (edits (vconcat (mapcar #'selection-batch--copy-edit
                                   (append (selection-batch--plan-edits plan) nil))))
           (future-register
            (selection-batch--apply-update
             selection-batch-register (selection-batch--plan-register-update plan)))
           (future-recipe
            (selection-batch--apply-update
             selection-batch-last-recipe (selection-batch--plan-recipe plan)))
           condition)
      (setf (selection-batch--session-state session) 'applying)
      (undo-boundary)
      (condition-case err
          (atomic-change-group
            (dolist (edit (append edits nil))
              (funcall selection-batch--plan-primitive-edit-function edit))
            (let ((result (selection-batch--plan-result-snapshot plan)))
              (funcall selection-batch--plan-install-result-function
                       session result)
              (funcall selection-batch--plan-refresh-view-function session))
            (selection-batch--detach-selections old-live))
        ((error quit) (setq condition err)))
      (if condition
          (let (restoration-error)
            ;; `atomic-change-group' has aborted before this handler continues.
            (condition-case restore
                (progn
                  (when (and (selection-batch--session-selections session)
                             (not (eq (selection-batch--session-selections session)
                                      old-live)))
                    (selection-batch--detach-selections
                     (selection-batch--session-selections session)))
                  (selection-batch--restore-live-markers session before old-live)
                  (setf (selection-batch--session-history session) old-history
                        (selection-batch--session-redo session) old-redo
                        (selection-batch--session-generation session) old-generation
                        (selection-batch--session-state session) old-state
                        (selection-batch--session-primary-id session) old-primary)
                  (setq selection-batch-register old-register
                        selection-batch-last-recipe old-recipe
                        selection-batch--view-refresh-function old-refresh
                        selection-batch--view-destroy-function old-destroy)
                  (when (functionp old-refresh) (funcall old-refresh session)))
              ((error quit) (setq restoration-error restore)))
            (when restoration-error
              (ignore-errors (selection-batch--cleanup session nil t))
              (setq selection-batch--session nil)
              (error "Plan failed (%S); compensation failed (%S)"
                     condition restoration-error))
            (signal (car condition) (cdr condition)))
        (setf (selection-batch--session-history session)
              (selection-batch--history-push before old-history)
              (selection-batch--session-redo session) nil
              (selection-batch--session-state session) 'set)
        (setq selection-batch-register future-register
              selection-batch-last-recipe future-recipe)
        (undo-boundary)
        (selection-batch-current-snapshot)))))

(provide 'selection-batch-plan)
;;; selection-batch-plan.el ends here
