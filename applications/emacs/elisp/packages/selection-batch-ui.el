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

(defun selection-batch--view-destroy (session)
  "Delete all derived view objects belonging to SESSION.
This operation is idempotent."
  (dolist (overlay (selection-batch--session-overlays session))
    (when (overlayp overlay)
      (delete-overlay overlay)))
  (setf (selection-batch--session-overlays session) nil))

(defun selection-batch--view-refresh (session)
  "Replace SESSION's view from its live selection model."
  (unless (and (eq session selection-batch--session)
               (buffer-live-p (selection-batch--session-buffer session)))
    (user-error "Cannot render a stale selection session"))
  (selection-batch--view-destroy session)
  (let ((buffer (selection-batch--session-buffer session))
        (primary-id (selection-batch--session-primary-id session))
        overlays)
    (with-current-buffer buffer
      (dolist (selection (append (selection-batch--session-selections session) nil))
        (unless (equal (selection-batch--live-selection-id selection) primary-id)
          (let* ((beginning (selection-batch-selection-beginning selection))
                 (end (selection-batch-selection-end selection))
                 (overlay (make-overlay beginning end buffer nil t)))
            (overlay-put overlay 'selection-batch-view t)
            (overlay-put overlay 'priority selection-batch--overlay-priority)
            (if (= beginning end)
                (overlay-put
                 overlay 'after-string
                 (propertize " " 'face 'selection-batch-secondary-cursor
                             'cursor t))
              (overlay-put overlay 'evaporate t)
              (overlay-put overlay 'face 'selection-batch-secondary))
            (push overlay overlays)))))
    (setf (selection-batch--session-overlays session) (nreverse overlays))))

(defun selection-batch--view-create (session)
  "Create the default derived view for SESSION."
  (selection-batch--view-refresh session))

;; The core owns commit ordering and calls only this narrow backend interface.
(setq selection-batch--view-refresh-function #'selection-batch--view-refresh
      selection-batch--view-destroy-function #'selection-batch--view-destroy)

(provide 'selection-batch-ui)
;;; selection-batch-ui.el ends here
