;;; selection-batch-ui.el --- Selection batch user interface -*- lexical-binding: t; -*-

;;; Commentary:
;; Replaceable derived views and the short-lived transaction keymap.  No
;; overlay is part of the selection model; deleting every overlay cannot alter
;; a session or its integer snapshot.

;;; Code:

(require 'cl-lib)
(require 'selection-batch-core)

(defface selection-batch-secondary
  '((t :inherit region))
  "Face for secondary selections."
  :group 'selection-batch)

(defface selection-batch-secondary-cursor
  '((t :inherit cursor :box t))
  "Face for empty secondary selections."
  :group 'selection-batch)

(defconst selection-batch--overlay-priority '(nil . 10)
  "Non-invasive overlay priority used by the default view backend.")

(defun selection-batch--view-delete-overlays (overlays)
  "Delete every overlay in OVERLAYS."
  (dolist (overlay overlays)
    (when (overlayp overlay) (delete-overlay overlay))))

(defun selection-batch--view-configure-overlay (overlay beginning end)
  "Move OVERLAY to BEGINNING and END and configure its current shape."
  (move-overlay overlay beginning end)
  (overlay-put overlay 'after-string nil)
  (overlay-put overlay 'face nil)
  ;; Do not evaporate a range that can become an empty live selection after a
  ;; buffer edit; the markers, not the overlay, decide its next shape.
  (overlay-put overlay 'evaporate nil)
  (if (= beginning end)
      (overlay-put
       overlay 'after-string
       (propertize " " 'face 'selection-batch-secondary-cursor 'cursor t))
    (overlay-put overlay 'face 'selection-batch-secondary)))

(defun selection-batch--view-after-modification
    (overlay after _beginning _end &optional _old-length)
  "Reconcile OVERLAY with its live markers AFTER a buffer modification."
  (when after
    (let ((session (overlay-get overlay 'selection-batch-session))
          (selection (overlay-get overlay 'selection-batch-selection)))
      (when (and (eq session selection-batch--session)
                 (overlay-buffer overlay)
                 (memq selection
                       (append (selection-batch--session-selections session) nil)))
        (let ((anchor (selection-batch--live-selection-anchor-marker selection))
              (cursor (selection-batch--live-selection-cursor-marker selection)))
          (when (and (marker-buffer anchor) (marker-buffer cursor))
            (selection-batch--view-configure-overlay
             overlay (min (marker-position anchor) (marker-position cursor))
             (max (marker-position anchor) (marker-position cursor)))))))))

(defun selection-batch--view-destroy (session)
  "Delete all derived view objects belonging to SESSION.
This operation is idempotent."
  (selection-batch--view-delete-overlays
   (selection-batch--session-overlays session))
  (setf (selection-batch--session-overlays session) nil))

(defun selection-batch--view-refresh (session)
  "Transactionally replace SESSION's view from its live selection model."
  (unless (and (eq session selection-batch--session)
               (buffer-live-p (selection-batch--session-buffer session)))
    (user-error "Cannot render a stale selection session"))
  (let ((buffer (selection-batch--session-buffer session))
        (primary-id (selection-batch--session-primary-id session))
        (old-overlays (selection-batch--session-overlays session))
        overlays completed)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (dolist (selection
                     (append (selection-batch--session-selections session) nil))
              (unless (equal (selection-batch--live-selection-id selection)
                             primary-id)
                (let* ((beginning (selection-batch-selection-beginning selection))
                       (end (selection-batch-selection-end selection))
                       (overlay (make-overlay beginning end buffer nil t)))
                  (push overlay overlays)
                  (overlay-put overlay 'selection-batch-view t)
                  (overlay-put overlay 'selection-batch-session session)
                  (overlay-put overlay 'selection-batch-selection selection)
                  (overlay-put overlay 'priority selection-batch--overlay-priority)
                  (overlay-put overlay 'modification-hooks
                               '(selection-batch--view-after-modification))
                  (overlay-put overlay 'insert-in-front-hooks
                               '(selection-batch--view-after-modification))
                  (overlay-put overlay 'insert-behind-hooks
                               '(selection-batch--view-after-modification))
                  (selection-batch--view-configure-overlay
                   overlay beginning end)))))
          (setq overlays (nreverse overlays))
          (setf (selection-batch--session-overlays session) overlays)
          (selection-batch--view-delete-overlays old-overlays)
          (setq completed t))
      (unless completed
        (selection-batch--view-delete-overlays overlays)))))

(defun selection-batch--view-create (session)
  "Create the default derived view for SESSION."
  (selection-batch--view-refresh session))

;; The core owns commit ordering and calls only this narrow backend interface.
(setq selection-batch--view-refresh-function #'selection-batch--view-refresh
      selection-batch--view-destroy-function #'selection-batch--view-destroy)

(defvar selection-batch--read-string-function #'read-string
  "Function used by `selection-batch-read-string'.
Kept indirect so batch tests can model completion, quit, and stale sessions
without claiming to exercise a real minibuffer command loop.")

(defun selection-batch--transaction-test-supported ()
  "Private no-op command used to characterize supported transaction keys."
  (interactive))

(defvar selection-batch--transaction-map
  (let ((map (make-sparse-keymap)))
    ;; These bindings are active only in a transaction.  Frontend/user keys
    ;; are deliberately deferred; no global or major-mode keymap is changed.
    (define-key map (kbd "t") #'selection-batch--transaction-test-supported)
    (define-key map (kbd "q") #'selection-batch-collapse)
    (define-key map (kbd "C-g") #'selection-batch-cancel)
    (define-key map [remap undo] #'selection-batch-undo)
    (define-key map [remap undo-only] #'selection-batch-undo)
    map)
  "Private transient map for an active selection transaction.")

(defun selection-batch-undo ()
  "End the selection transaction, then undo one whole-buffer unit.
The live primary region is deliberately deactivated before `undo-only' so it
cannot silently turn the operation into undo-in-region.  Teardown happens
first, hence an undo error cannot leave a stale session or transient map."
  (interactive)
  (let ((session (selection-batch--owner-session t)))
    (selection-batch--cleanup session nil t))
  (let ((mark-active nil))
    (undo-only 1)))

(defun selection-batch--transaction-on-exit (session)
  "Collapse SESSION when its map exits outside a supported command."
  (when (eq session selection-batch--session)
    (setf (selection-batch--session-transient-exit-function session) nil)
    (unless (or (selection-batch--session-suspending-p session)
                (selection-batch--session-exit-in-progress-p session))
      ;; `on-exit' runs before the command whose key was outside the map.
      (selection-batch--cleanup session t nil))))

(defun selection-batch--transaction-deactivate (session)
  "Deactivate SESSION's current transaction map at most once."
  (let ((exit (selection-batch--session-transient-exit-function session)))
    (setf (selection-batch--session-transient-exit-function session) nil)
    (when (functionp exit)
      (funcall exit))))

(defun selection-batch--transaction-install (session)
  "Install a fresh transaction map for the valid owner SESSION."
  (unless (and (eq session selection-batch--session)
               (buffer-live-p (selection-batch--session-buffer session))
               (eq (current-buffer) (selection-batch--session-buffer session))
               (not (selection-batch--session-exit-in-progress-p session)))
    (user-error "Cannot install a map for a stale selection session"))
  (when (selection-batch--session-transient-exit-function session)
    (setf (selection-batch--session-suspending-p session) t)
    (unwind-protect
        (selection-batch--transaction-deactivate session)
      (setf (selection-batch--session-suspending-p session) nil)))
  (setf (selection-batch--session-transient-exit-function session)
        (set-transient-map
         selection-batch--transaction-map t
         (lambda () (selection-batch--transaction-on-exit session))))
  session)

(defun selection-batch--prompt-session-valid-p (session owner generation)
  "Return non-nil if SESSION still has OWNER and GENERATION."
  (and (eq session selection-batch--session)
       (buffer-live-p owner)
       (eq owner (selection-batch--session-buffer session))
       (eq owner (current-buffer))
       (= generation (selection-batch--session-generation session))
       (not (selection-batch--session-exit-in-progress-p session))))

(defun selection-batch--prompt-resume (session owner generation)
  "Validate a suspended prompt and resume SESSION, or clean stale state."
  (if (selection-batch--prompt-session-valid-p session owner generation)
      (progn
        (setf (selection-batch--session-suspending-p session) nil)
        (condition-case err
            (selection-batch--transaction-install session)
          ((error quit)
           (selection-batch--cleanup session t nil)
           (signal (car err) (cdr err)))))
    (when (and (eq session selection-batch--session)
               (not (selection-batch--session-exit-in-progress-p session)))
      (setf (selection-batch--session-suspending-p session) nil)
      (selection-batch--cleanup session t nil))
    (user-error "Selection session became stale while prompting")))

(defun selection-batch-read-string (prompt &optional initial-input)
  "Read one string while safely suspending the transaction map.
PROMPT and INITIAL-INPUT have the same meaning as for `read-string'.  A valid
completion or quit resumes a fresh map.  A changed owner, current buffer, or
generation collapses stale state instead."
  (let* ((session (selection-batch--owner-session t))
         (owner (selection-batch--session-buffer session))
         (generation (selection-batch--session-generation session))
         value condition)
    (setf (selection-batch--session-suspending-p session) t)
    (condition-case err
        (selection-batch--transaction-deactivate session)
      ((error quit)
       (setf (selection-batch--session-suspending-p session) nil)
       (selection-batch--cleanup session t nil)
       (signal (car err) (cdr err))))
    (unwind-protect
        (condition-case err
            (setq value (funcall selection-batch--read-string-function
                                 prompt initial-input))
          ((error quit) (setq condition err)))
      (selection-batch--prompt-resume session owner generation))
    (when condition
      (signal (car condition) (cdr condition)))
    value))

(provide 'selection-batch-ui)
;;; selection-batch-ui.el ends here
