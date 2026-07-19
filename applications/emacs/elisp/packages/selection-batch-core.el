;;; selection-batch-core.el --- Ordered selection transaction core -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Integer snapshots, live selection sessions, providers, and pure selection
;; transformations.  This file deliberately contains no display or text-edit
;; engine.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function selection-batch-read-regexp "selection-batch-ui" (prompt &optional initial history))

(defgroup selection-batch nil
  "Short-lived ordered selection sets."
  :group 'editing)

(defcustom selection-batch-history-limit 30
  "Maximum number of selection-only snapshots retained.
Only non-negative integers are accepted."
  :type 'natnum
  :safe (lambda (value) (and (integerp value) (>= value 0))))

(cl-defstruct (selection-batch--live-selection
               (:constructor selection-batch--live-selection-create))
  id anchor-marker cursor-marker)

(cl-defstruct (selection-batch-snapshot-selection
               (:constructor selection-batch--snapshot-selection-create)
               (:conc-name selection-batch--snapshot-selection-))
  (id nil :read-only t)
  (anchor nil :read-only t)
  (cursor nil :read-only t))

(cl-defstruct (selection-batch-snapshot
               (:constructor selection-batch--snapshot-create)
               (:conc-name selection-batch--snapshot-))
  (buffer nil :read-only t)
  (buffer-tick nil :read-only t)
  (generation nil :read-only t)
  (primary-id nil :read-only t)
  (narrowing nil :read-only t)
  (selections nil :read-only t))

(cl-defstruct (selection-batch-normalization
               (:constructor selection-batch--normalization-create))
  (snapshot nil :read-only t)
  (diagnostics nil :read-only t))

(cl-defstruct (selection-batch-provider-result
               (:constructor selection-batch-provider-result-create))
  (selections nil :read-only t)
  (primary-id nil :read-only t)
  (metadata nil :read-only t))

(cl-defstruct (selection-batch--session
               (:constructor selection-batch--session-create))
  buffer selections primary-id history redo generation state overlays
  transient-exit-function suspending-p exit-in-progress-p)

(defvar selection-batch--session nil
  "The sole live selection session, or nil.")

(defun selection-batch--prune-dead-owner ()
  "Destroy and clear a stale global session whose owner buffer is dead."
  (when (and selection-batch--session
             (not (buffer-live-p
                   (selection-batch--session-buffer selection-batch--session))))
    (let ((stale selection-batch--session))
      (condition-case nil
          (selection-batch--cleanup stale nil t)
        ((error quit) (setq selection-batch--session nil)))
      (when (eq selection-batch--session stale)
        (setq selection-batch--session nil))))
  selection-batch--session)

(defun selection-batch-active-p ()
  "Return non-nil when a live selection transaction exists."
  (selection-batch--prune-dead-owner)
  (and selection-batch--session
       (buffer-live-p (selection-batch--session-buffer selection-batch--session))
       (not (selection-batch--session-exit-in-progress-p selection-batch--session))))

(defun selection-batch-owner-buffer ()
  "Return the live session owner buffer, or nil when no session is active.
This is the public ownership query for frontends; callers need not inspect the
private session representation."
  (and (selection-batch-active-p)
       (selection-batch--session-buffer selection-batch--session)))

(defun selection-batch-owned-by-p (&optional buffer)
  "Return non-nil when BUFFER owns the live selection session.
BUFFER defaults to the current buffer."
  (eq (or buffer (current-buffer)) (selection-batch-owner-buffer)))

(defun selection-batch-current ()
  "Return the current immutable snapshot, or nil outside a transaction."
  (and (selection-batch-active-p) (selection-batch-current-snapshot)))

(defun selection-batch-count ()
  "Return the number of live selections, or zero outside a transaction."
  (if (selection-batch-active-p)
      (length (selection-batch--session-selections selection-batch--session))
    0))

(defun selection-batch-activation-allowed-p (&optional buffer)
  "Return non-nil when BUFFER supports an editable text transaction."
  (with-current-buffer (or buffer (current-buffer))
    (and (not buffer-read-only)
         (not (minibufferp))
         (not (derived-mode-p 'special-mode)))))

(defun selection-batch--assert-activation-allowed (&optional buffer)
  "Reject selection activation in unsupported BUFFER."
  (unless (selection-batch-activation-allowed-p buffer)
    (user-error "Selection batches require an editable text buffer")))

(defvar selection-batch--view-refresh-function nil
  "Optional function called with a session after a committed state change.
This is the narrow interface by which a replaceable view backend observes the
core.  The core never requires a particular UI implementation.")

(defvar selection-batch--view-destroy-function nil
  "Optional function called with a session while that session is cleaned up.")

(defun selection-batch--refresh-derived-view (session)
  "Refresh SESSION's derived view, when a backend is installed."
  (when (functionp selection-batch--view-refresh-function)
    (funcall selection-batch--view-refresh-function session)))

(defun selection-batch--destroy-derived-view (session)
  "Destroy SESSION's derived view, with a backend-independent fallback."
  (if (functionp selection-batch--view-destroy-function)
      (funcall selection-batch--view-destroy-function session)
    (dolist (overlay (selection-batch--session-overlays session))
      (when (overlayp overlay) (delete-overlay overlay)))
    (setf (selection-batch--session-overlays session) nil)))

(defun selection-batch--mark-position ()
  "Return the current buffer's mark position, or nil without asserting."
  (condition-case nil
      (mark t)
    (cl-assertion-failed nil)))

(defun selection-batch-selection-anchor (selection)
  "Return SELECTION's anchor as an integer.
SELECTION may be a snapshot value or an entry in the current live session."
  (cond
   ((selection-batch-snapshot-selection-p selection)
    (selection-batch-snapshot-selection-anchor selection))
   ((selection-batch--live-selection-p selection)
    (selection-batch--live-endpoint selection t))
   (t (signal 'wrong-type-argument (list 'selection-batch-selection selection)))))

(defun selection-batch-selection-cursor (selection)
  "Return SELECTION's cursor as an integer."
  (cond
   ((selection-batch-snapshot-selection-p selection)
    (selection-batch-snapshot-selection-cursor selection))
   ((selection-batch--live-selection-p selection)
    (selection-batch--live-endpoint selection nil))
   (t (signal 'wrong-type-argument (list 'selection-batch-selection selection)))))

(defun selection-batch-selection-beginning (selection)
  "Return the lesser endpoint of SELECTION."
  (min (selection-batch-selection-anchor selection)
       (selection-batch-selection-cursor selection)))

(defun selection-batch-selection-end (selection)
  "Return the greater endpoint of SELECTION."
  (max (selection-batch-selection-anchor selection)
       (selection-batch-selection-cursor selection)))

(defun selection-batch-selection-forward-p (selection)
  "Return non-nil when SELECTION points forward or is empty."
  (<= (selection-batch-selection-anchor selection)
      (selection-batch-selection-cursor selection)))

(defun selection-batch-selection-backward-p (selection)
  "Return non-nil when SELECTION points backward."
  (> (selection-batch-selection-anchor selection)
     (selection-batch-selection-cursor selection)))

(defun selection-batch-selection-empty-p (selection)
  "Return non-nil when SELECTION has equal endpoints."
  (= (selection-batch-selection-anchor selection)
     (selection-batch-selection-cursor selection)))

(defun selection-batch--copy-value (value)
  "Recursively copy mutable containers in VALUE."
  (cond
   ((stringp value) (copy-sequence value))
   ((consp value)
    (cons (selection-batch--copy-value (car value))
          (selection-batch--copy-value (cdr value))))
   ((vectorp value)
    (vconcat (mapcar #'selection-batch--copy-value (append value nil))))
   ((hash-table-p value)
    (let ((copy (copy-hash-table value)))
      (clrhash copy)
      (maphash (lambda (key item)
                 (puthash (selection-batch--copy-value key)
                          (selection-batch--copy-value item) copy))
               value)
      copy))
   (t value)))

(cl-defun selection-batch-snapshot-selection-create (&key id anchor cursor)
  "Create a selection value without retaining a mutable ID reference."
  (selection-batch--snapshot-selection-create
   :id (selection-batch--copy-value id) :anchor anchor :cursor cursor))

(defun selection-batch-snapshot-selection-id (selection)
  "Return a defensive copy of SELECTION's identifier."
  (selection-batch--copy-value
   (selection-batch--snapshot-selection-id selection)))

(defun selection-batch-snapshot-selection-anchor (selection)
  "Return SELECTION's integer anchor."
  (selection-batch--snapshot-selection-anchor selection))

(defun selection-batch-snapshot-selection-cursor (selection)
  "Return SELECTION's integer cursor."
  (selection-batch--snapshot-selection-cursor selection))

(defun selection-batch--copy-selection (selection)
  "Copy snapshot SELECTION by value."
  (selection-batch-snapshot-selection-create
   :id (selection-batch--copy-value
        (selection-batch-snapshot-selection-id selection))
   :anchor (selection-batch-snapshot-selection-anchor selection)
   :cursor (selection-batch-snapshot-selection-cursor selection)))

(defun selection-batch--copy-selections (selections)
  "Copy vector SELECTIONS and all of its values."
  (vconcat (mapcar #'selection-batch--copy-selection (append selections nil))))

(cl-defun selection-batch-snapshot-create
    (&key buffer buffer-tick generation primary-id narrowing selections)
  "Create a snapshot, defensively copying its compound values."
  (selection-batch--snapshot-create
   :buffer buffer :buffer-tick buffer-tick :generation generation
   :primary-id (selection-batch--copy-value primary-id)
   :narrowing (selection-batch--copy-value narrowing)
   :selections (selection-batch--copy-selections selections)))

(defun selection-batch-snapshot-buffer (snapshot)
  "Return SNAPSHOT's source buffer."
  (selection-batch--snapshot-buffer snapshot))

(defun selection-batch-snapshot-buffer-tick (snapshot)
  "Return SNAPSHOT's source buffer modification tick."
  (selection-batch--snapshot-buffer-tick snapshot))

(defun selection-batch-snapshot-generation (snapshot)
  "Return SNAPSHOT's generation."
  (selection-batch--snapshot-generation snapshot))

(defun selection-batch-snapshot-primary-id (snapshot)
  "Return a defensive copy of SNAPSHOT's primary selection ID."
  (selection-batch--copy-value (selection-batch--snapshot-primary-id snapshot)))

(defun selection-batch-snapshot-narrowing (snapshot)
  "Return a copy of SNAPSHOT's narrowing bounds."
  (selection-batch--copy-value (selection-batch--snapshot-narrowing snapshot)))

(defun selection-batch-snapshot-selections (snapshot)
  "Return a copy of SNAPSHOT's selections vector and values."
  (selection-batch--copy-selections
   (selection-batch--snapshot-selections snapshot)))

(cl-defun selection-batch-snapshot-with-selections
    (snapshot selections &optional (primary-id nil primary-id-supplied-p))
  "Copy SNAPSHOT while replacing its immutable SELECTIONS.
PRIMARY-ID defaults to SNAPSHOT's primary identifier when omitted.  Passing nil
explicitly selects a nil identifier.  The snapshot context is deliberately
preserved; callers must apply the value through
`selection-batch-apply-transform' or otherwise validate its generation, buffer
tick, and narrowing before install.
This public value-level operation lets frontends build pure transforms without
using private struct constructors or retaining mutable selection identifiers."
  (if primary-id-supplied-p
      (selection-batch--copy-snapshot snapshot selections primary-id)
    (selection-batch--copy-snapshot snapshot selections)))

(cl-defun selection-batch--copy-snapshot
    (snapshot &optional selections (primary-id nil primary-id-supplied-p))
  "Copy SNAPSHOT, optionally replacing SELECTIONS and PRIMARY-ID."
  (selection-batch--snapshot-create
   :buffer (selection-batch-snapshot-buffer snapshot)
   :buffer-tick (selection-batch-snapshot-buffer-tick snapshot)
   :generation (selection-batch-snapshot-generation snapshot)
   :primary-id (selection-batch--copy-value
                (if primary-id-supplied-p
                    primary-id
                  (selection-batch-snapshot-primary-id snapshot)))
   :narrowing (selection-batch--copy-value
               (selection-batch--snapshot-narrowing snapshot))
   :selections (selection-batch--copy-selections
                (or selections (selection-batch--snapshot-selections snapshot)))))

(defun selection-batch--selection-by-id (selections id)
  "Find selection ID in vector SELECTIONS."
  (cl-find id selections :key #'selection-batch-snapshot-selection-id :test #'equal))

(defun selection-batch--live-by-id (session id)
  "Find selection ID in SESSION."
  (cl-find id (selection-batch--session-selections session)
           :key #'selection-batch--live-selection-id :test #'equal))

(defun selection-batch--owner-session (&optional require-current)
  "Return a valid live session.
When REQUIRE-CURRENT is non-nil, reject calls outside its owner buffer."
  (let ((session selection-batch--session))
    (unless (and session (buffer-live-p (selection-batch--session-buffer session)))
      (when session (selection-batch--cleanup session nil t))
      (user-error "There is no live selection session"))
    (when (and require-current
               (not (eq (current-buffer) (selection-batch--session-buffer session))))
      (user-error "Selection session belongs to another buffer"))
    session))

(defun selection-batch--broken-invariant (session message)
  "Clean SESSION and signal MESSAGE as a user error."
  (selection-batch--cleanup session nil t)
  (user-error "Broken selection invariant: %s" message))

(defun selection-batch--live-endpoint (selection anchor-p)
  "Return live SELECTION endpoint, choosing anchor when ANCHOR-P."
  (let* ((session (selection-batch--owner-session))
         (id (selection-batch--live-selection-id selection)))
    (unless (memq selection (append (selection-batch--session-selections session) nil))
      (user-error "Selection is not in the live session"))
    (if (equal id (selection-batch--session-primary-id session))
        (with-current-buffer (selection-batch--session-buffer session)
          (if anchor-p
              (or (selection-batch--mark-position)
                  (selection-batch--broken-invariant session "primary mark is unset"))
            (point)))
      (let ((marker (if anchor-p
                        (selection-batch--live-selection-anchor-marker selection)
                      (selection-batch--live-selection-cursor-marker selection))))
        (if (and (markerp marker)
                 (marker-buffer marker)
                 (eq (marker-buffer marker) (selection-batch--session-buffer session)))
            (marker-position marker)
          (selection-batch--broken-invariant session "secondary marker is stale"))))))

(defun selection-batch--detach-selections (selections)
  "Detach every marker in live vector SELECTIONS."
  (dolist (selection (append selections nil))
    (dolist (marker (list (selection-batch--live-selection-anchor-marker selection)
                          (selection-batch--live-selection-cursor-marker selection)))
      (when (markerp marker) (set-marker marker nil)))))

(defun selection-batch--project-primary (session anchor cursor)
  "Project ANCHOR and CURSOR into SESSION's owner buffer."
  (unless (eq (current-buffer) (selection-batch--session-buffer session))
    (user-error "Refusing to project a selection into another buffer"))
  (goto-char cursor)
  (set-mark anchor)
  (setq mark-active t)
  (activate-mark))

(defun selection-batch--make-live-selections (buffer selections primary-id)
  "Create live entries for SELECTIONS in BUFFER with PRIMARY-ID marker-free.
Detach every marker already allocated if construction fails."
  (let (live)
    (condition-case err
        (progn
          (dolist (selection (append selections nil))
            (let ((id (selection-batch-snapshot-selection-id selection)))
              (push
               (if (equal id primary-id)
                   (selection-batch--live-selection-create :id id)
                 (selection-batch--live-selection-create
                  :id id
                  :anchor-marker
                  (set-marker (make-marker)
                              (selection-batch-snapshot-selection-anchor selection)
                              buffer)
                  :cursor-marker
                  (let ((marker (make-marker)))
                    (set-marker-insertion-type marker t)
                    (set-marker marker
                                (selection-batch-snapshot-selection-cursor selection)
                                buffer))))
               live)))
          (vconcat (nreverse live)))
      ((error quit)
       (selection-batch--detach-selections (vconcat live))
       (signal (car err) (cdr err))))))

(defun selection-batch--validate-snapshot (snapshot)
  "Validate integer-only SNAPSHOT and return it."
  (unless (selection-batch-snapshot-p snapshot)
    (signal 'wrong-type-argument (list 'selection-batch-snapshot snapshot)))
  (let ((buffer (selection-batch-snapshot-buffer snapshot))
        (selections (selection-batch--snapshot-selections snapshot))
        (primary-id (selection-batch-snapshot-primary-id snapshot)))
    (unless (buffer-live-p buffer) (user-error "Snapshot buffer is dead"))
    (unless (and (vectorp selections) (> (length selections) 0))
      (user-error "A selection set cannot be empty"))
    (unless (selection-batch--selection-by-id selections primary-id)
      (user-error "Primary selection is absent"))
    (let ((ids nil))
      (dolist (selection (append selections nil))
        (unless (and (selection-batch-snapshot-selection-p selection)
                     (integerp (selection-batch-snapshot-selection-anchor selection))
                     (integerp (selection-batch-snapshot-selection-cursor selection)))
          (user-error "Selection endpoints must be integers"))
        (when (member (selection-batch-snapshot-selection-id selection) ids)
          (user-error "Selection IDs must be unique"))
        (push (selection-batch-snapshot-selection-id selection) ids)
        (with-current-buffer buffer
          (unless (and (<= (point-min) (selection-batch-selection-beginning selection))
                       (<= (selection-batch-selection-end selection) (point-max)))
            (user-error "Selection %S is outside narrowing"
                        (selection-batch-snapshot-selection-id selection))))))
    snapshot))

(defun selection-batch--install-lifecycle-hooks (buffer)
  "Install the session lifecycle hooks locally in BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (add-hook 'kill-buffer-hook #'selection-batch--lifecycle-exit nil t)
      (add-hook 'before-revert-hook #'selection-batch--lifecycle-exit nil t)
      (add-hook 'change-major-mode-hook #'selection-batch--lifecycle-exit nil t))))

(defun selection-batch--remove-lifecycle-hooks (buffer)
  "Remove the session lifecycle hooks locally from BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (remove-hook 'kill-buffer-hook #'selection-batch--lifecycle-exit t)
      (remove-hook 'before-revert-hook #'selection-batch--lifecycle-exit t)
      (remove-hook 'change-major-mode-hook #'selection-batch--lifecycle-exit t))))

(defun selection-batch--project-snapshot-primary (session snapshot)
  "Project SNAPSHOT's primary endpoints for SESSION."
  (let ((primary (selection-batch--selection-by-id
                  (selection-batch--snapshot-selections snapshot)
                  (selection-batch-snapshot-primary-id snapshot))))
    (with-current-buffer (selection-batch--session-buffer session)
      (selection-batch--project-primary
       session
       (selection-batch-snapshot-selection-anchor primary)
       (selection-batch-snapshot-selection-cursor primary)))))

(defun selection-batch-install-snapshot (snapshot &optional _allow-empty-primary)
  "Transactionally install SNAPSHOT as the sole live session.
The candidate is fully allocated before global state changes.  If projection or
view creation fails, the previous owner is restored from an integer snapshot;
an initial failure leaves no session, hooks, markers, or derived artifacts."
  (selection-batch--prune-dead-owner)
  (selection-batch--validate-snapshot snapshot)
  (selection-batch--assert-activation-allowed
   (selection-batch-snapshot-buffer snapshot))
  (let* ((buffer (selection-batch-snapshot-buffer snapshot))
         (selections (selection-batch--snapshot-selections snapshot))
         (primary-id (selection-batch-snapshot-primary-id snapshot)))
    (unless (eq buffer (current-buffer))
      (user-error "Install must run in the snapshot buffer"))
    (let* ((old-session selection-batch--session)
           (old-snapshot (and old-session
                              (selection-batch-current-snapshot)))
           (saved-point (point))
           (saved-mark (selection-batch--mark-position))
           (saved-mark-active mark-active)
           (live (selection-batch--make-live-selections
                  buffer selections primary-id))
           (candidate (selection-batch--session-create
                       :buffer buffer :selections live :primary-id primary-id
                       :history nil :redo nil
                       :generation (selection-batch-snapshot-generation snapshot)
                       :state 'set :overlays nil))
           committed)
      (condition-case err
          (progn
            ;; The backend's validity check intentionally sees the candidate.
            ;; The old live markers and view remain available as compensation
            ;; until candidate projection and rendering have both succeeded.
            (setq selection-batch--session candidate)
            (selection-batch--install-lifecycle-hooks buffer)
            (selection-batch--project-snapshot-primary candidate snapshot)
            (selection-batch--refresh-derived-view candidate)
            (setq committed t)
            (when old-session
              (let (cleanup-error)
                (condition-case cleanup-err
                    (selection-batch--cleanup
                     old-session
                     (eq buffer (selection-batch--session-buffer old-session))
                     (not (eq buffer (selection-batch--session-buffer old-session))))
                  ((error quit) (setq cleanup-error cleanup-err)))
                ;; Same-buffer old cleanup removes shared local hooks.  It may
                ;; also run a hostile backend, so reassert the committed state.
                (setq selection-batch--session candidate)
                (selection-batch--install-lifecycle-hooks buffer)
                (selection-batch--project-snapshot-primary candidate snapshot)
                (when cleanup-error
                  (signal (car cleanup-error) (cdr cleanup-error)))))
            candidate)
        ((error quit)
         (if committed
             ;; Candidate rendering succeeded.  A later old-session teardown
             ;; error is reportable, but must not roll back to detached state.
             (progn
               (setq selection-batch--session candidate)
               (selection-batch--install-lifecycle-hooks buffer)
               (selection-batch--project-snapshot-primary candidate snapshot))
           ;; Cleanup itself is best-effort and can report a backend failure;
           ;; the installation error remains the useful caller condition.
           (ignore-errors (selection-batch--cleanup candidate nil t))
           (if old-session
               (progn
                 (setq selection-batch--session old-session)
                 (selection-batch--install-lifecycle-hooks
                  (selection-batch--session-buffer old-session))
                 (selection-batch--project-snapshot-primary
                  old-session old-snapshot)
                 ;; Transactional backends leave the old view intact.  This
                 ;; repairs a backend that replaced its view before signalling.
                 (ignore-errors
                   (selection-batch--refresh-derived-view old-session)))
             (setq selection-batch--session nil)
             (goto-char saved-point)
             (if saved-mark
                 (set-mark saved-mark)
               (set-marker (mark-marker) nil))
             (setq mark-active saved-mark-active)))
         (signal (car err) (cdr err)))))))

(defun selection-batch-current-snapshot ()
  "Return an integer-only snapshot of the current live session."
  (let* ((session (selection-batch--owner-session))
         (buffer (selection-batch--session-buffer session))
         values)
    (condition-case err
        (with-current-buffer buffer
          (dolist (selection (append (selection-batch--session-selections session) nil))
            (let* ((id (selection-batch--live-selection-id selection))
                   (primary-p (equal id (selection-batch--session-primary-id session)))
                   (anchor-marker
                    (selection-batch--live-selection-anchor-marker selection))
                   (cursor-marker
                    (selection-batch--live-selection-cursor-marker selection))
                   (anchor (if primary-p
                               (selection-batch--mark-position)
                             (and (markerp anchor-marker)
                                  (marker-position anchor-marker))))
                   (cursor (if primary-p
                               (point)
                             (and (markerp cursor-marker)
                                  (marker-position cursor-marker)))))
              ;; Iteration already proves membership; validate only the actual
              ;; endpoint storage instead of rescanning the whole vector twice.
              (unless (and anchor cursor)
                (selection-batch--broken-invariant
                 session "a snapshot endpoint is stale"))
              (push (selection-batch-snapshot-selection-create
                     :id (selection-batch--copy-value id)
                     :anchor anchor :cursor cursor)
                    values)))
          (selection-batch--snapshot-create
           :buffer buffer
           :buffer-tick (buffer-chars-modified-tick)
           :generation (selection-batch--session-generation session)
           :primary-id (selection-batch--copy-value
                        (selection-batch--session-primary-id session))
           :narrowing (cons (point-min) (point-max))
           :selections (vconcat (nreverse values))))
      ((error quit)
       ;; Endpoint helpers already clean invariant failures.  Preserve other
       ;; errors, such as a caller-provided quit.
       (signal (car err) (cdr err))))))

(defun selection-batch--cleanup (session preserve-primary deactivate-mark-p)
  "Idempotently clean SESSION, continuing after every teardown error.
Keep its primary projection when PRESERVE-PRIMARY is non-nil.  Deactivate the
mark when DEACTIVATE-MARK-P is non-nil.  The first teardown condition is
re-signalled only after views, markers, hooks, transient state, and the global
owner have all been cleared."
  (when (and session (not (selection-batch--session-exit-in-progress-p session)))
    (setf (selection-batch--session-exit-in-progress-p session) t)
    (let ((buffer (selection-batch--session-buffer session))
          first-error)
      (cl-labels ((attempt (function)
                    (condition-case err
                        (funcall function)
                      ((error quit)
                       (unless first-error (setq first-error err))))))
        (attempt
         (lambda ()
           (when (and preserve-primary (buffer-live-p buffer))
             (with-current-buffer buffer
               (when (selection-batch--mark-position) (setq mark-active t))))))
        (attempt (lambda () (selection-batch--destroy-derived-view session)))
        ;; A backend is not trusted to have deleted every artifact before it
        ;; failed.  The core-owned list is therefore always swept as fallback.
        (dolist (overlay (selection-batch--session-overlays session))
          (attempt (lambda ()
                     (when (overlayp overlay) (delete-overlay overlay)))))
        (setf (selection-batch--session-overlays session) nil)
        (attempt
         (lambda ()
           (selection-batch--detach-selections
            (selection-batch--session-selections session))))
        (attempt (lambda () (selection-batch--remove-lifecycle-hooks buffer)))
        (when (and deactivate-mark-p (buffer-live-p buffer))
          (attempt (lambda ()
                     (with-current-buffer buffer
                       (when (selection-batch--mark-position)
                         (deactivate-mark))))))
        (let ((exit (selection-batch--session-transient-exit-function session)))
          (setf (selection-batch--session-transient-exit-function session) nil)
          (when (functionp exit) (attempt exit)))
        (when (eq selection-batch--session session)
          (setq selection-batch--session nil))
        (when first-error
          (signal (car first-error) (cdr first-error)))))))

(defun selection-batch--lifecycle-exit ()
  "Exit the session owned by the current buffer."
  (when (and selection-batch--session
             (eq (current-buffer) (selection-batch--session-buffer selection-batch--session)))
    (selection-batch--cleanup selection-batch--session nil t)))

(defun selection-batch-collapse ()
  "End the live session while preserving its primary region.
Do nothing when no session exists.  A session owned by another buffer remains
an error, so this command cannot project point and mark across buffers."
  (interactive)
  (when selection-batch--session
    (let ((session (selection-batch--owner-session t)))
      (selection-batch--cleanup session t nil))))

(defun selection-batch-collapse-owner ()
  "Collapse whichever live buffer currently owns the selection session.
Return nil when no session is active.  This is an explicit cross-buffer
ownership handoff; dead owners are pruned by `selection-batch-owner-buffer'."
  (when-let* ((owner (selection-batch-owner-buffer)))
    (with-current-buffer owner
      (selection-batch-collapse))))

(defun selection-batch-cancel ()
  "Cancel the live session and deactivate its primary region.
Do nothing when no session exists."
  (interactive)
  (when selection-batch--session
    (let ((session (selection-batch--owner-session t)))
      (selection-batch--cleanup session nil t))))

(defun selection-batch--overlap-p (left right)
  "Return non-nil when nonempty LEFT and RIGHT overlap.
Adjacency and empty selections are not overlaps."
  (and (not (selection-batch-selection-empty-p left))
       (not (selection-batch-selection-empty-p right))
       (< (selection-batch-selection-beginning left)
          (selection-batch-selection-end right))
       (< (selection-batch-selection-beginning right)
          (selection-batch-selection-end left))))

(defun selection-batch--choose-primary (old-selections new-selections old-primary)
  "Choose a deterministic primary after filtering OLD-SELECTIONS.
Prefer OLD-PRIMARY, then the next retained logical selection, then previous."
  (if (selection-batch--selection-by-id new-selections old-primary)
      old-primary
    (let* ((old (append old-selections nil))
           (position (cl-position old-primary old
                                  :key #'selection-batch-snapshot-selection-id
                                  :test #'equal))
           (new-ids (mapcar #'selection-batch-snapshot-selection-id
                            (append new-selections nil)))
           next previous)
      (when position
        (cl-loop for selection in (nthcdr (1+ position) old)
                 when (member (selection-batch-snapshot-selection-id selection) new-ids)
                 do (setq next (selection-batch-snapshot-selection-id selection)) and return nil)
        (cl-loop for selection in (reverse (cl-subseq old 0 position))
                 when (member (selection-batch-snapshot-selection-id selection) new-ids)
                 do (setq previous (selection-batch-snapshot-selection-id selection)) and return nil))
      (or next previous
          (and (> (length new-selections) 0)
               (selection-batch-snapshot-selection-id (aref new-selections 0)))))))

(defun selection-batch--filtered-snapshot (snapshot selections)
  "Return SNAPSHOT with filtered SELECTIONS and inherited primary."
  (let ((new (vconcat selections)))
    (when (= (length new) 0) (user-error "A transform cannot remove every selection"))
    (selection-batch--copy-snapshot
     snapshot new
     (selection-batch--choose-primary
      (selection-batch--snapshot-selections snapshot) new
      (selection-batch-snapshot-primary-id snapshot)))))

(defun selection-batch-normalize (snapshot &optional overlap-policy)
  "Purely normalize SNAPSHOT according to OVERLAP-POLICY.
POLICY is `reject' (the default) or `merge'.  Exact endpoint duplicates are
always removed.  Return a `selection-batch-normalization' containing a fresh
snapshot and diagnostics."
  (selection-batch--validate-snapshot snapshot)
  (setq overlap-policy (or overlap-policy 'reject))
  (unless (memq overlap-policy '(reject merge))
    (user-error "Unknown overlap policy: %S" overlap-policy))
  (let* ((original (selection-batch--snapshot-selections snapshot))
         (primary-id (selection-batch-snapshot-primary-id snapshot))
         (indexed (cl-loop for selection across original for index from 0
                           collect (cons index selection)))
         (duplicate-ids nil)
         unique)
    ;; Dedupe by directed endpoints.  If a duplicate group contains primary,
    ;; that value occupies the first group's logical position.
    (dolist (item indexed)
      (let* ((selection (cdr item))
             (existing (cl-find-if
                        (lambda (pair)
                          (let ((other (cdr pair)))
                            (and (= (selection-batch-selection-anchor selection)
                                    (selection-batch-selection-anchor other))
                                 (= (selection-batch-selection-cursor selection)
                                    (selection-batch-selection-cursor other)))))
                        unique)))
        (if existing
            (progn
              (push (selection-batch-snapshot-selection-id selection) duplicate-ids)
              (when (equal (selection-batch-snapshot-selection-id selection) primary-id)
                (setcdr existing selection)))
          (setq unique (append unique (list (cons (car item) selection)))))))
    (let* ((sorted (sort (copy-sequence unique)
                         (lambda (a b)
                           (let ((sa (cdr a)) (sb (cdr b)))
                             (or (< (selection-batch-selection-beginning sa)
                                    (selection-batch-selection-beginning sb))
                                 (and (= (selection-batch-selection-beginning sa)
                                         (selection-batch-selection-beginning sb))
                                      (< (selection-batch-selection-end sa)
                                         (selection-batch-selection-end sb))))))))
           groups current)
      (dolist (item sorted)
        (cond
         ;; Empty selections are singleton groups, but cannot terminate an
         ;; active nonempty overlap component.
         ((selection-batch-selection-empty-p (cdr item))
          (push (list item) groups))
         ((and current
               (cl-some (lambda (member)
                          (selection-batch--overlap-p (cdr member) (cdr item)))
                        current))
          (setq current (append current (list item))))
         (t
          (when current (push current groups))
          (setq current (list item)))))
      (when current (push current groups))
      (setq groups (nreverse groups))
      (when (and (eq overlap-policy 'reject)
                 (cl-some (lambda (group) (> (length group) 1)) groups))
        (user-error "Overlapping selections are not allowed"))
      (let (merged-ids output)
        (dolist (group groups)
          (if (= (length group) 1)
              (push (car group) output)
            (let* ((members (mapcar #'cdr group))
                   (primary (cl-find primary-id members
                                     :key #'selection-batch-snapshot-selection-id
                                     :test #'equal))
                   (inherit (or primary (car members)))
                   (id (selection-batch-snapshot-selection-id inherit))
                   (begin (apply #'min (mapcar #'selection-batch-selection-beginning members)))
                   (end (apply #'max (mapcar #'selection-batch-selection-end members)))
                   (forward (selection-batch-selection-forward-p inherit))
                   (index (apply #'min (mapcar #'car group))))
              (setq merged-ids
                    (append merged-ids
                            (mapcar #'selection-batch-snapshot-selection-id members)))
              (push (cons index
                          (selection-batch-snapshot-selection-create
                           :id id :anchor (if forward begin end)
                           :cursor (if forward end begin)))
                    output))))
        (setq output (sort output (lambda (a b) (< (car a) (car b)))))
        (let* ((values (vconcat (mapcar (lambda (item)
                                         (selection-batch--copy-selection (cdr item)))
                                       output)))
               (new-primary
                (or (and (selection-batch--selection-by-id values primary-id) primary-id)
                    (cl-loop for group in groups
                             when (cl-find primary-id group :key (lambda (item)
                                                                  (selection-batch-snapshot-selection-id
                                                                   (cdr item)))
                                           :test #'equal)
                             return (selection-batch-snapshot-selection-id
                                     (cdr (car (last group)))))
                    (selection-batch--choose-primary original values primary-id))))
          (selection-batch--normalization-create
           :snapshot (selection-batch--copy-snapshot snapshot values new-primary)
           :diagnostics (list :duplicate-ids (nreverse duplicate-ids)
                              :merged-ids merged-ids)))))))

(defun selection-batch-normalize-snapshot (snapshot &optional overlap-policy)
  "Return only the normalized SNAPSHOT value."
  (selection-batch-normalization-snapshot
   (selection-batch-normalize snapshot overlap-policy)))

(defun selection-batch--provider-result (selections &optional primary-id metadata)
  "Build a provider result from SELECTIONS."
  (let ((values (vconcat selections)))
    (selection-batch-provider-result-create
     :selections values
     :primary-id (or primary-id
                     (and (> (length values) 0)
                          (selection-batch-snapshot-selection-id (aref values 0))))
     :metadata metadata)))

(defun selection-batch-provider-region (&optional allow-empty)
  "Discover the active region, or an empty caret when ALLOW-EMPTY is non-nil."
  (cond
   ((and mark-active (selection-batch--mark-position))
    (selection-batch--provider-result
     (list (selection-batch-snapshot-selection-create
            :id 0 :anchor (selection-batch--mark-position) :cursor (point)))
     0 '(:provider region)))
   (allow-empty
    (selection-batch--provider-result
     (list (selection-batch-snapshot-selection-create
            :id 0 :anchor (point) :cursor (point)))
     0 '(:provider region :empty t)))
   (t (user-error "No active region"))))

(defun selection-batch--search-literal (text beginning end)
  "Return forward selection values matching TEXT between BEGINNING and END."
  (when (string-empty-p text) (user-error "Same-text search cannot use an empty string"))
  (save-excursion
    (goto-char beginning)
    (let ((case-fold-search nil) values (id 0))
      (while (search-forward text end t)
        (push (selection-batch-snapshot-selection-create
               :id id :anchor (match-beginning 0) :cursor (match-end 0)) values)
        (setq id (1+ id)))
      (nreverse values))))

(defun selection-batch-provider-same-text (text &optional direction origin)
  "Discover occurrences of TEXT in the accessible buffer.
DIRECTION is `all', `next', or `previous'.  ORIGIN defaults to point and is
used to select one match for directional discovery."
  (setq direction (or direction 'all)
        origin (or origin (point)))
  (let* ((values (selection-batch--search-literal text (point-min) (point-max)))
         (chosen
          (pcase direction
            ('all values)
            ('next (let ((match (cl-find-if
                                 (lambda (selection)
                                   (>= (selection-batch-selection-beginning selection) origin))
                                 values)))
                     (and match (list match))))
            ('previous (let ((match (car (last
                                          (cl-remove-if-not
                                           (lambda (selection)
                                             (<= (selection-batch-selection-end selection) origin))
                                           values)))))
                         (and match (list match))))
            (_ (user-error "Unknown same-text direction: %S" direction)))))
    (selection-batch--provider-result chosen nil
                                      (list :provider 'same-text :text (copy-sequence text)
                                            :direction direction))))

(defun selection-batch-provider-regexp (regexp &optional scope)
  "Discover REGEXP matches in SCOPE.
SCOPE is `accessible' (default), `region', or a (BEGINNING . END) pair.  Empty
matches become empty selections and search always makes progress."
  (let* ((bounds
          (pcase (or scope 'accessible)
            ('accessible (cons (point-min) (point-max)))
            ('region (unless (and mark-active (selection-batch--mark-position))
                       (user-error "No active region"))
                     (cons (region-beginning) (region-end)))
            ((and `(,beginning . ,end) (guard (and (integerp beginning)
                                                   (integerp end))))
             (cons beginning end))
            (_ (user-error "Unknown regexp scope: %S" scope))))
         (limit (min (cdr bounds) (point-max)))
         values (id 0) done)
    (save-excursion
      (goto-char (max (car bounds) (point-min)))
      (while (and (not done) (<= (point) limit)
                  (re-search-forward regexp limit t))
        (let ((beginning (match-beginning 0))
              (end (match-end 0)))
          (push (selection-batch-snapshot-selection-create
                 :id id :anchor beginning :cursor end) values)
          (setq id (1+ id))
          ;; Emacs normally advances repeated empty matches itself.  The
          ;; explicit guard also makes this true for boundary-only regexps.
          (when (and (= beginning end) (= (point) beginning))
            (if (< (point) limit)
                (forward-char 1)
              (setq done t))))))
    (selection-batch--provider-result
     (nreverse values) nil (list :provider 'regexp :regexp (copy-sequence regexp)
                                 :scope scope))))

(defun selection-batch-provider-lines (&optional beginning end)
  "Discover content ranges for lines intersecting BEGINNING through END.
The final line is included even when it has no terminating newline."
  (let ((active (and mark-active (selection-batch--mark-position))))
    (setq beginning (or beginning (if active (region-beginning) (point-min)))
          end (or end (if active (region-end) (point-max)))))
  (setq beginning (max beginning (point-min))
        end (min end (point-max)))
  (save-excursion
    (goto-char beginning)
    (let (values (id 0) done)
      (while (not done)
        (let ((line-beginning (max beginning (line-beginning-position)))
              (line-end (min end (line-end-position))))
          (push (selection-batch-snapshot-selection-create
                 :id id :anchor line-beginning :cursor line-end) values)
          (setq id (1+ id)))
        (if (or (>= (line-end-position) end) (= (line-end-position) (point-max)))
            (setq done t)
          (forward-line 1)))
      (selection-batch--provider-result
       (nreverse values) nil (list :provider 'lines :bounds (cons beginning end))))))

(defun selection-batch-provider-snapshot (result &optional buffer generation)
  "Convert provider RESULT to a fresh snapshot in BUFFER."
  (setq buffer (or buffer (current-buffer)))
  (unless (> (length (selection-batch-provider-result-selections result)) 0)
    (user-error "Provider found no selections"))
  (with-current-buffer buffer
    (selection-batch--snapshot-create
     :buffer buffer :buffer-tick (buffer-chars-modified-tick)
     :generation (or generation 0)
     :primary-id (selection-batch-provider-result-primary-id result)
     :narrowing (cons (point-min) (point-max))
     :selections (selection-batch--copy-selections
                  (selection-batch-provider-result-selections result)))))

(defun selection-batch-use-provider (provider &rest arguments)
  "Run PROVIDER with ARGUMENTS and install its nonempty discovery result."
  (let* ((result (apply provider arguments))
         (snapshot (selection-batch-provider-snapshot result)))
    (selection-batch-install-snapshot snapshot t)))

(defun selection-batch--selection-text (snapshot selection)
  "Return SELECTION text from SNAPSHOT's buffer without properties."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (buffer-substring-no-properties (selection-batch-selection-beginning selection)
                                    (selection-batch-selection-end selection))))

(defun selection-batch-transform-keep-regexp (snapshot regexp)
  "Keep SNAPSHOT selections whose text matches REGEXP."
  (selection-batch--filtered-snapshot
   snapshot
   (cl-remove-if-not (lambda (selection)
                       (string-match-p regexp
                                       (selection-batch--selection-text snapshot selection)))
                     (append (selection-batch--snapshot-selections snapshot) nil))))

(defun selection-batch-transform-drop-regexp (snapshot regexp)
  "Drop SNAPSHOT selections whose text matches REGEXP."
  (selection-batch--filtered-snapshot
   snapshot
   (cl-remove-if (lambda (selection)
                   (string-match-p regexp
                                   (selection-batch--selection-text snapshot selection)))
                 (append (selection-batch--snapshot-selections snapshot) nil))))

(defun selection-batch-transform-add-same (snapshot direction)
  "Add one unselected same-text occurrence to SNAPSHOT in DIRECTION.
DIRECTION is `next' or `previous'.  The newly added occurrence becomes primary;
existing selections keep their IDs and direction, and output is in buffer order."
  (unless (memq direction '(next previous))
    (user-error "Unknown same-text direction: %S" direction))
  (selection-batch--validate-snapshot snapshot)
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (unless (= (selection-batch-snapshot-buffer-tick snapshot)
               (buffer-chars-modified-tick))
      (user-error "Selection snapshot is stale"))
    (unless (equal (selection-batch-snapshot-narrowing snapshot)
                   (cons (point-min) (point-max)))
      (user-error "Selection snapshot narrowing changed"))
    (let* ((selections
            (append (selection-batch--snapshot-selections snapshot) nil))
           (primary
            (selection-batch--selection-by-id
             (selection-batch--snapshot-selections snapshot)
             (selection-batch-snapshot-primary-id snapshot)))
           (text (selection-batch--selection-text snapshot primary)))
      (when (string-empty-p text)
        (user-error "Same-text search cannot use an empty selection"))
      (unless (cl-every
               (lambda (selection)
                 (string= text
                          (selection-batch--selection-text snapshot selection)))
               selections)
        (user-error "Incremental same-text gather requires equal selections"))
      (let* ((all
              (append
               (selection-batch-provider-result-selections
                (selection-batch-provider-same-text text 'all))
               nil))
             (same-endpoints-p
              (lambda (left right)
                (and (= (selection-batch-selection-beginning left)
                        (selection-batch-selection-beginning right))
                     (= (selection-batch-selection-end left)
                        (selection-batch-selection-end right)))))
             (selected-p
              (lambda (match)
                (cl-some (lambda (selection)
                           (funcall same-endpoints-p selection match))
                         selections))))
        (unless (cl-every
                 (lambda (selection)
                   (cl-some (lambda (match)
                              (funcall same-endpoints-p selection match))
                            all))
                 selections)
          (user-error "Selection set contains a non-occurrence range"))
        (let* ((origin (selection-batch-selection-beginning primary))
               (eligible
                (cl-remove-if-not
                 (lambda (match)
                   (and (not (funcall selected-p match))
                        (if (eq direction 'next)
                            (> (selection-batch-selection-beginning match) origin)
                          (< (selection-batch-selection-beginning match) origin))))
                 all))
               (candidate
                (if (eq direction 'next) (car eligible) (car (last eligible)))))
          (unless candidate
            (user-error "No unselected %s occurrence" direction))
          (let ((serial 0) id)
            (while (progn
                     (setq id (format "occurrence-%d" serial))
                     (setq serial (1+ serial))
                     (selection-batch--selection-by-id
                      (selection-batch--snapshot-selections snapshot) id)))
            (let* ((added
                    (selection-batch-snapshot-selection-create
                     :id id
                     :anchor (selection-batch-snapshot-selection-anchor candidate)
                     :cursor (selection-batch-snapshot-selection-cursor candidate)))
                   (ordered
                    (sort (append selections (list added))
                          (lambda (left right)
                            (or (< (selection-batch-selection-beginning left)
                                   (selection-batch-selection-beginning right))
                                (and (= (selection-batch-selection-beginning left)
                                        (selection-batch-selection-beginning right))
                                     (< (selection-batch-selection-end left)
                                        (selection-batch-selection-end right))))))))
              (selection-batch--copy-snapshot snapshot (vconcat ordered) id))))))))

(defun selection-batch-transform-split-lines (snapshot)
  "Split each SNAPSHOT selection into per-line content selections."
  (let ((original-selections (selection-batch--snapshot-selections snapshot))
        output (next-id 0))
    (dolist (selection (append original-selections nil))
      (let ((beginning (selection-batch-selection-beginning selection))
            (end (selection-batch-selection-end selection))
            pieces (piece-index 0))
        (with-current-buffer (selection-batch-snapshot-buffer snapshot)
          (setq pieces (selection-batch-provider-result-selections
                        (selection-batch-provider-lines beginning end))))
        ;; Provider line bounds are inclusive enough to represent an empty
        ;; final line.  A nonempty selection is half-open, however, so a line
        ;; beginning exactly at END does not intersect it.
        (when (< beginning end)
          (setq pieces
                (cl-remove-if
                 (lambda (piece)
                   (and (selection-batch-selection-empty-p piece)
                        (= (selection-batch-selection-beginning piece) end)))
                 (append pieces nil))))
        (dolist (piece (append pieces nil))
          (let ((id (if (= piece-index 0)
                        (selection-batch-snapshot-selection-id selection)
                      (while (or (selection-batch--selection-by-id
                                  original-selections (format "split-%d" next-id))
                                 (selection-batch--selection-by-id
                                  (vconcat output) (format "split-%d" next-id)))
                        (setq next-id (1+ next-id)))
                      (prog1 (format "split-%d" next-id)
                        (setq next-id (1+ next-id))))))
            (let ((piece-beginning
                   (selection-batch-snapshot-selection-anchor piece))
                  (piece-end (selection-batch-snapshot-selection-cursor piece)))
              (push (selection-batch-snapshot-selection-create
                     :id id
                     :anchor (if (selection-batch-selection-forward-p selection)
                                 piece-beginning piece-end)
                     :cursor (if (selection-batch-selection-forward-p selection)
                                 piece-end piece-beginning))
                    output)
              (setq piece-index (1+ piece-index)))))))
    (selection-batch--filtered-snapshot snapshot (nreverse output))))

(defun selection-batch-transform-reverse (snapshot)
  "Reverse every selection direction in SNAPSHOT."
  (selection-batch--copy-snapshot
   snapshot
   (vconcat
    (mapcar (lambda (selection)
              (selection-batch-snapshot-selection-create
               :id (selection-batch-snapshot-selection-id selection)
               :anchor (selection-batch-snapshot-selection-cursor selection)
               :cursor (selection-batch-snapshot-selection-anchor selection)))
            (append (selection-batch--snapshot-selections snapshot) nil)))))

(defun selection-batch-transform-merge (snapshot)
  "Merge overlapping selections in SNAPSHOT."
  (selection-batch-normalize-snapshot snapshot 'merge))

(defun selection-batch-transform-rotate-primary (snapshot &optional backward)
  "Rotate SNAPSHOT primary one logical step, BACKWARD when non-nil."
  (let* ((selections (selection-batch--snapshot-selections snapshot))
         (length (length selections))
         (index (cl-position (selection-batch-snapshot-primary-id snapshot)
                             (append selections nil)
                             :key #'selection-batch-snapshot-selection-id :test #'equal))
         (next (mod (+ index (if backward -1 1)) length)))
    (selection-batch--copy-snapshot
     snapshot selections (selection-batch-snapshot-selection-id (aref selections next)))))

(defun selection-batch--replace-with-snapshot (session snapshot)
  "Transactionally replace SESSION's live state with SNAPSHOT once.
Old live markers remain attached as compensation until the candidate view has
been validated.  Any failure restores the old integer primary projection,
model slots, generation, and derived view before the candidate is detached."
  (selection-batch--validate-snapshot snapshot)
  (unless (and (eq session selection-batch--session)
               (eq (current-buffer) (selection-batch--session-buffer session))
               (eq (selection-batch-snapshot-buffer snapshot)
                   (selection-batch--session-buffer session)))
    (user-error "Cannot replace a stale or foreign session"))
  (let* ((selections (selection-batch--snapshot-selections snapshot))
         (primary-id (selection-batch-snapshot-primary-id snapshot))
         (before (selection-batch-current-snapshot))
         (old-live (selection-batch--session-selections session))
         (old-primary-id (selection-batch--session-primary-id session))
         (old-generation (selection-batch--session-generation session))
         (new-live (selection-batch--make-live-selections
                    (current-buffer) selections primary-id)))
    (condition-case err
        (progn
          (setf (selection-batch--session-selections session) new-live
                (selection-batch--session-primary-id session) primary-id
                (selection-batch--session-generation session)
                (1+ old-generation))
          (selection-batch--project-snapshot-primary session snapshot)
          (selection-batch--refresh-derived-view session)
          ;; The candidate model and view are now both valid; only now may the
          ;; compensation markers be detached.
          (selection-batch--detach-selections old-live)
          session)
      ((error quit)
       (setf (selection-batch--session-selections session) old-live
             (selection-batch--session-primary-id session) old-primary-id
             (selection-batch--session-generation session) old-generation)
       (selection-batch--project-snapshot-primary session before)
       ;; A transactional backend still has the old view.  Calling refresh also
       ;; repairs wrappers that completed rendering and then signalled.
       (ignore-errors (selection-batch--refresh-derived-view session))
       (selection-batch--detach-selections new-live)
       (signal (car err) (cdr err))))))

(defun selection-batch--valid-history-limit ()
  "Return the validated integer history limit."
  (unless (and (integerp selection-batch-history-limit)
               (>= selection-batch-history-limit 0))
    (user-error "`selection-batch-history-limit' must be a non-negative integer"))
  selection-batch-history-limit)

(defun selection-batch--history-push (snapshot history)
  "Push integer SNAPSHOT onto HISTORY and enforce the configured bound."
  (let ((limit (selection-batch--valid-history-limit)))
    (if (= limit 0) nil
      (cl-subseq (cons (selection-batch--copy-snapshot snapshot) history)
                 0 (min limit (1+ (length history)))))))

(defun selection-batch-apply-transform (transform &rest arguments)
  "Apply pure TRANSFORM with ARGUMENTS to the current selection session."
  (let* ((session (selection-batch--owner-session t))
         (before (selection-batch-current-snapshot))
         (candidate (apply transform before arguments))
         (after (selection-batch-normalize-snapshot candidate 'reject)))
    (unless (equal before after)
      (let ((new-history (selection-batch--history-push
                          before (selection-batch--session-history session))))
        (selection-batch--replace-with-snapshot session after)
        (setf (selection-batch--session-history session) new-history
              (selection-batch--session-redo session) nil)))
    (selection-batch-current-snapshot)))

(defun selection-batch-selection-undo ()
  "Undo one selection-only transformation."
  (interactive)
  (let* ((session (selection-batch--owner-session t))
         (history (selection-batch--session-history session)))
    (unless history (user-error "No selection history"))
    (let ((current (selection-batch-current-snapshot))
          (target (car history))
          (old-redo (selection-batch--session-redo session)))
      (selection-batch--replace-with-snapshot session target)
      (setf (selection-batch--session-history session) (cdr history)
            (selection-batch--session-redo session)
            (selection-batch--history-push current old-redo))
      (selection-batch-current-snapshot))))

(defun selection-batch-selection-redo ()
  "Redo one selection-only transformation."
  (interactive)
  (let* ((session (selection-batch--owner-session t))
         (redo (selection-batch--session-redo session)))
    (unless redo (user-error "No selection redo"))
    (let ((current (selection-batch-current-snapshot))
          (target (car redo))
          (old-history (selection-batch--session-history session)))
      (selection-batch--replace-with-snapshot session target)
      (setf (selection-batch--session-redo session) (cdr redo)
            (selection-batch--session-history session)
            (selection-batch--history-push current old-history))
      (selection-batch-current-snapshot))))

;; Public frontend commands are defined below the model so they can compose the
;; pure provider and transformer protocols without exposing live markers.

(defun selection-batch--source-selection ()
  "Return the primary selection used by gather commands."
  (if (selection-batch-active-p)
      (let ((snapshot (selection-batch-current-snapshot)))
        (selection-batch--selection-by-id
         (selection-batch-snapshot-selections snapshot)
         (selection-batch-snapshot-primary-id snapshot)))
    (aref (selection-batch-provider-result-selections
           (selection-batch-provider-region)) 0)))

(defun selection-batch--project-single-result (selection)
  "Leave SELECTION as an ordinary point/mark region without a session."
  (when (selection-batch-active-p) (selection-batch-collapse))
  (goto-char (selection-batch-snapshot-selection-cursor selection))
  (set-mark (selection-batch-snapshot-selection-anchor selection))
  (setq mark-active t)
  (activate-mark)
  nil)

(defun selection-batch--promote-provider-result (result)
  "Install RESULT only at cardinality two or greater."
  (selection-batch--assert-activation-allowed)
  (let* ((selections (selection-batch-provider-result-selections result))
         (count (length selections)))
    (cond
     ((= count 0) (user-error "Provider found no selections"))
     ((= count 1) (selection-batch--project-single-result (aref selections 0)))
     (t
      (selection-batch-install-snapshot
       (selection-batch-provider-snapshot result) t)
      (when (fboundp 'selection-batch--transaction-install)
        (selection-batch--transaction-install selection-batch--session))
      (selection-batch-current-snapshot)))))

(defun selection-batch--same-result (direction)
  "Build same-text gather result for DIRECTION, retaining source primary."
  (let* ((source (selection-batch--source-selection))
         (beginning (selection-batch-selection-beginning source))
         (end (selection-batch-selection-end source))
         (text (buffer-substring-no-properties beginning end))
         (all (selection-batch-provider-result-selections
               (selection-batch-provider-same-text text 'all)))
         (source-match
          (cl-find-if (lambda (selection)
                        (and (= beginning (selection-batch-selection-beginning selection))
                             (= end (selection-batch-selection-end selection))))
                      (append all nil)))
         selected)
    (unless source-match (user-error "Current selection is not a same-text match"))
    (setq selected
          (pcase direction
            ('all (append all nil))
            ('next
             (let ((other (cl-find-if
                           (lambda (selection)
                             (> (selection-batch-selection-beginning selection) beginning))
                           (append all nil))))
               (delq nil (list source-match other))))
            ('previous
             (let ((other (car (last
                                (cl-remove-if-not
                                 (lambda (selection)
                                   (< (selection-batch-selection-beginning selection) beginning))
                                 (append all nil))))))
               (delq nil (list other source-match))))
            (_ (user-error "Unknown gather direction: %S" direction))))
    (setq selected
          (mapcar (lambda (selection)
                    (if (eq selection source-match)
                        (selection-batch-snapshot-selection-create
                         :id (selection-batch-snapshot-selection-id selection)
                         :anchor (selection-batch-selection-anchor source)
                         :cursor (selection-batch-selection-cursor source))
                      selection))
                  selected))
    (selection-batch-provider-result-create
     :selections (vconcat selected)
     :primary-id (selection-batch-snapshot-selection-id source-match)
     :metadata (list :provider 'same-text :direction direction))))

(defun selection-batch-provider-current-same-text (direction)
  "Return a same-text provider result around the current primary selection.
DIRECTION is `all', `next', or `previous'.  The result retains the current
primary selection's direction while exposing no live session representation."
  (selection-batch--same-result direction))

(defun selection-batch-gather-same-next ()
  "Gather the current selection and its next equal occurrence."
  (interactive)
  (selection-batch--promote-provider-result (selection-batch--same-result 'next)))

(defun selection-batch-gather-same-previous ()
  "Gather the current selection and its previous equal occurrence."
  (interactive)
  (selection-batch--promote-provider-result (selection-batch--same-result 'previous)))

(defun selection-batch-gather-same-all ()
  "Gather every occurrence equal to the current selection."
  (interactive)
  (selection-batch--promote-provider-result (selection-batch--same-result 'all)))

(defun selection-batch-gather-regexp (regexp &optional scope)
  "Gather REGEXP in accessible text or optional SCOPE."
  (interactive (list (selection-batch-read-regexp "Gather regexp: ") 'accessible))
  (selection-batch--promote-provider-result
   (selection-batch-provider-regexp regexp (or scope 'accessible))))

(defun selection-batch-split-lines ()
  "Split selections into line ranges.
An ordinary region is discovered without installing a session unless it
produces at least two lines; an existing transaction uses the pure transform."
  (interactive)
  (if (selection-batch-active-p)
      (selection-batch-apply-transform #'selection-batch-transform-split-lines)
    (selection-batch--promote-provider-result
     (selection-batch-provider-lines))))

(defun selection-batch-keep (regexp)
  "Keep live selections whose text matches REGEXP."
  (interactive (list (selection-batch-read-regexp "Keep selections matching: ")))
  (selection-batch-apply-transform #'selection-batch-transform-keep-regexp regexp))

(defun selection-batch-drop (regexp)
  "Drop live selections whose text matches REGEXP."
  (interactive (list (selection-batch-read-regexp "Drop selections matching: ")))
  (selection-batch-apply-transform #'selection-batch-transform-drop-regexp regexp))

(defun selection-batch-merge ()
  "Merge overlapping live selections."
  (interactive)
  (selection-batch-apply-transform #'selection-batch-transform-merge))

(defun selection-batch-rotate-primary-next ()
  "Rotate the primary selection forward."
  (interactive)
  (selection-batch-apply-transform #'selection-batch-transform-rotate-primary nil))

(defun selection-batch-rotate-primary-previous ()
  "Rotate the primary selection backward."
  (interactive)
  (selection-batch-apply-transform #'selection-batch-transform-rotate-primary t))

(provide 'selection-batch-core)
;;; selection-batch-core.el ends here
