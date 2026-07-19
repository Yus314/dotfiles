;;; selection-batch-ui.el --- Selection batch user interface -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Replaceable derived views and the short-lived transaction keymap.  No
;; overlay is part of the selection model; deleting every overlay cannot alter
;; a session or its integer snapshot.

;;; Code:

(require 'cl-lib)
(require 'selection-batch-core)

;; Optional Emacs primitive, feature-detected at runtime.
(declare-function set-window-extra-cursors nil (window cursors))
(declare-function set-window-cursor-type nil (window type))
(declare-function window-cursor-type nil (&optional window))

(defface selection-batch-secondary
  '((t :inherit region))
  "Face for secondary selections."
  :group 'selection-batch)

(defface selection-batch-secondary-cursor
  '((t :inherit cursor :inverse-video t))
  "Face for secondary cursor endpoints in the portable backend."
  :group 'selection-batch)

(defconst selection-batch--overlay-priority '(nil . 10)
  "Non-invasive overlay priority used by the default view backend.")

(defvar selection-batch--installed-window-cursors nil
  "Native cursor ledger entries.
Each entry is (WINDOW BUFFER SESSION CURSORS OLD-TYPE INSTALLED-TYPE).
CURSORS is retained so a signalling setter can be compensated.  OLD-TYPE and
INSTALLED-TYPE provide compare-and-restore ownership of the primary cursor.")

(defvar selection-batch--reconciling-window-cursors nil)

(defvar selection-batch--window-cursor-hooks-installed-p nil)

(defun selection-batch--native-cursors-available-p ()
  "Return non-nil when this Emacs provides the native extra-cursor API."
  (fboundp 'set-window-extra-cursors))

(defun selection-batch--native-session-live-p ()
  "Return non-nil while a live session can use native window cursors."
  (and selection-batch--session
       (selection-batch--native-cursors-available-p)
       (buffer-live-p
        (selection-batch--session-buffer selection-batch--session))
       (not (selection-batch--session-exit-in-progress-p
             selection-batch--session))))

(defun selection-batch--install-window-cursor-hooks ()
  "Install the hooks that track native cursor window ownership."
  (unless selection-batch--window-cursor-hooks-installed-p
    (add-hook 'post-command-hook #'selection-batch--reconcile-window-cursors)
    (add-hook 'window-configuration-change-hook
              #'selection-batch--reconcile-window-cursors)
    (add-hook 'window-buffer-change-functions
              #'selection-batch--reconcile-window-cursors)
    (setq selection-batch--window-cursor-hooks-installed-p t)))

(defun selection-batch--remove-window-cursor-hooks ()
  "Remove reconciliation hooks when no native-capable session is live."
  (unless (selection-batch--native-session-live-p)
    (remove-hook 'post-command-hook #'selection-batch--reconcile-window-cursors)
    (remove-hook 'window-configuration-change-hook
                 #'selection-batch--reconcile-window-cursors)
    (remove-hook 'window-buffer-change-functions
                 #'selection-batch--reconcile-window-cursors)
    (setq selection-batch--window-cursor-hooks-installed-p nil)))

(defun selection-batch--clear-native-entry (entry)
  "Clear the native cursor state represented by ledger ENTRY."
  (let ((window (nth 0 entry)) first-error)
    (when (and (window-live-p window)
               (selection-batch--native-cursors-available-p))
      (condition-case err
          (set-window-extra-cursors window nil)
        ((error quit) (setq first-error err)))
      ;; Restore only while our exact installed value remains.  An intervening
      ;; user or package setting transfers ownership away from us.
      (when (equal (window-cursor-type window) (nth 5 entry))
        (condition-case err
            (set-window-cursor-type window (nth 4 entry))
          ((error quit) (unless first-error (setq first-error err)))))
      (when first-error
        (signal (car first-error) (cdr first-error))))))

(defun selection-batch--uninstall-native-cursors (&optional session)
  "Uninstall native cursors, restricted to SESSION when it is non-nil."
  (let (kept first-error)
    (dolist (entry selection-batch--installed-window-cursors)
      (if (or (null session) (eq session (nth 2 entry)))
          (condition-case err
              (selection-batch--clear-native-entry entry)
            ((error quit) (unless first-error (setq first-error err))))
        (push entry kept)))
    ;; Forget ownership even if the optional primitive failed.  This prevents
    ;; later sessions from treating uncertain window-local state as theirs.
    (setq selection-batch--installed-window-cursors (nreverse kept))
    (selection-batch--remove-window-cursor-hooks)
    (when first-error
      (signal (car first-error) (cdr first-error)))))

(defun selection-batch--secondary-cursor-markers (session)
  "Return SESSION's directed secondary cursor endpoint markers."
  (let ((primary-id (selection-batch--session-primary-id session)) markers)
    (dolist (selection (append (selection-batch--session-selections session) nil))
      (unless (equal primary-id (selection-batch--live-selection-id selection))
        (push (selection-batch--live-selection-cursor-marker selection) markers)))
    (nreverse markers)))

(defun selection-batch--install-native-cursors (session)
  "Install SESSION's secondary endpoint cursors in the selected window.
The ownership ledger is changed only after the native setter succeeds."
  (let ((window (selected-window))
        (buffer (selection-batch--session-buffer session)))
    (when (and (window-live-p window) (eq (window-buffer window) buffer))
      (let* ((cursors (selection-batch--secondary-cursor-markers session))
             (old-ledger selection-batch--installed-window-cursors)
             (old-here (cl-find window old-ledger :key #'car :test #'eq))
             (old-type (if old-here (nth 4 old-here)
                         (window-cursor-type window)))
             (installed-type (if old-here (nth 5 old-here) 'box))
             (entry (list window buffer session cursors
                          old-type installed-type)))
        ;; In the common refresh case this replaces the cursor vector directly;
        ;; do not clear the same window first and force two redisplays.
        (condition-case err
            (set-window-extra-cursors window cursors)
          ((error quit)
           ;; A hostile optional setter may mutate and then signal.  Reapply
           ;; the last successfully installed marker vector before propagating.
           (when old-here
             (condition-case nil
                 (set-window-extra-cursors window (nth 3 old-here))
               ((error quit) nil)))
           (signal (car err) (cdr err))))
        (unless old-here
          (condition-case err
              (set-window-cursor-type window installed-type)
            ((error quit)
             ;; Both optional setters are allowed to mutate and then signal.
             ;; Recover the primary setting only if our mutation is visible,
             ;; and remove the just-installed secondary cursors.
             (when (equal (window-cursor-type window) installed-type)
               (condition-case nil
                   (set-window-cursor-type window old-type)
                 ((error quit) nil)))
             (condition-case nil
                 (set-window-extra-cursors window nil)
               ((error quit) nil))
             (signal (car err) (cdr err)))))
        (condition-case err
            (dolist (old old-ledger)
              (unless (eq window (nth 0 old))
                (selection-batch--clear-native-entry old)))
          ((error quit)
           ;; The old ledger still describes its native state.  Best-effort
           ;; removal prevents the newly installed owner from becoming orphaned.
           (condition-case nil
               (set-window-extra-cursors window nil)
             ((error quit) nil))
           (unless old-here
             (when (equal (window-cursor-type window) installed-type)
               (condition-case nil
                   (set-window-cursor-type window old-type)
                 ((error quit) nil))))
           (signal (car err) (cdr err))))
        (setq selection-batch--installed-window-cursors (list entry))
        (selection-batch--install-window-cursor-hooks)
        entry))))

(defun selection-batch--reconcile-window-cursors (&rest _ignored)
  "Reconcile native state with the selected owner window.
The stable (window, buffer, session) case is a constant-time no-op, so the
post-command hook does not allocate a cursor vector or invoke the setter."
  (unless selection-batch--reconciling-window-cursors
    (let* ((selection-batch--reconciling-window-cursors t)
           (session selection-batch--session)
           (live (selection-batch--native-session-live-p))
           (buffer (and live (selection-batch--session-buffer session)))
           (window (and buffer (selected-window)))
           (owner-window-p (and (window-live-p window)
                                (eq (window-buffer window) buffer)))
           (current (car selection-batch--installed-window-cursors)))
      ;; Compare the ledger fields directly: the post-command stable path does
      ;; not cons a desired entry or walk the (normally singleton) ledger.
      (unless (and owner-window-p
                   current
                   (null (cdr selection-batch--installed-window-cursors))
                   (eq window (nth 0 current))
                   (eq buffer (nth 1 current))
                   (eq session (nth 2 current)))
        (when selection-batch--installed-window-cursors
          (selection-batch--uninstall-native-cursors))
        (when owner-window-p
          (selection-batch--install-native-cursors session)))
      (if live
          (selection-batch--install-window-cursor-hooks)
        (selection-batch--remove-window-cursor-hooks)))))

(defun selection-batch--view-delete-overlays (overlays)
  "Delete every overlay in OVERLAYS."
  (dolist (overlay overlays)
    (when (overlayp overlay) (delete-overlay overlay))))

(defun selection-batch--view-configure-overlay (overlay beginning end cursor)
  "Configure OVERLAY for its role using BEGINNING, END, and CURSOR endpoint."
  (overlay-put overlay 'after-string nil)
  (overlay-put overlay 'face nil)
  ;; Do not evaporate a range that can become an empty live selection after a
  ;; buffer edit; the markers, not the overlay, decide its next shape.
  (overlay-put overlay 'evaporate nil)
  (pcase (overlay-get overlay 'selection-batch-role)
    ('range
     (move-overlay overlay beginning end)
     (overlay-put overlay 'face 'selection-batch-secondary))
    ('cursor
     ;; At EOL and EOF there is no glyph cell to cover.  Everywhere else the
     ;; fallback covers the actual character rather than appending a fake cell.
     (if (and (< cursor (point-max))
              (not (eq (char-after cursor) ?\n)))
         (progn
           (move-overlay overlay cursor (1+ cursor))
           (overlay-put overlay 'face 'selection-batch-secondary-cursor))
       (move-overlay overlay cursor cursor)
       (overlay-put
        overlay 'after-string
        (propertize " " 'face 'selection-batch-secondary-cursor 'cursor t))))))

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
             (max (marker-position anchor) (marker-position cursor))
             (marker-position cursor))
            ;; An empty fallback owns only a cursor overlay.  If an insertion
            ;; separates its markers, add the newly needed range view without
            ;; waiting for a command-level refresh.
            (let ((beginning (min (marker-position anchor) (marker-position cursor)))
                  (end (max (marker-position anchor) (marker-position cursor))))
              (when (and (< beginning end)
                         (eq 'cursor (overlay-get overlay 'selection-batch-role))
                         (not (cl-find-if
                               (lambda (candidate)
                                 (and (eq 'range (overlay-get candidate
                                                              'selection-batch-role))
                                      (eq selection (overlay-get candidate
                                                                 'selection-batch-selection))))
                               (selection-batch--session-overlays session))))
                (let ((range (make-overlay beginning end (overlay-buffer overlay)
                                           nil t)))
                  (dolist (property '(selection-batch-view selection-batch-session
                                      selection-batch-selection priority
                                      modification-hooks insert-in-front-hooks
                                      insert-behind-hooks))
                    (overlay-put range property (overlay-get overlay property)))
                  (overlay-put range 'selection-batch-role 'range)
                  (selection-batch--view-configure-overlay
                   range beginning end (marker-position cursor))
                  (push range (selection-batch--session-overlays session)))))))))))

(defun selection-batch--view-destroy (session)
  "Delete all derived view objects belonging to SESSION.
This operation is idempotent."
  (selection-batch--view-delete-overlays
   (selection-batch--session-overlays session))
  (setf (selection-batch--session-overlays session) nil)
  (selection-batch--uninstall-native-cursors session))

(defun selection-batch--view-refresh (session)
  "Transactionally replace SESSION's view from its live selection model."
  (unless (and (eq session selection-batch--session)
               (buffer-live-p (selection-batch--session-buffer session)))
    (user-error "Cannot render a stale selection session"))
  (let* ((buffer (selection-batch--session-buffer session))
         (primary-id (selection-batch--session-primary-id session))
         (old-overlays (selection-batch--session-overlays session))
         (use-native (and (selection-batch--native-cursors-available-p)
                          (eq (window-buffer (selected-window)) buffer)))
         overlays completed)
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (dolist (selection
                     (append (selection-batch--session-selections session) nil))
              (unless (equal (selection-batch--live-selection-id selection)
                             primary-id)
                (let* ((anchor (selection-batch--live-selection-anchor-marker
                                selection))
                       (cursor (selection-batch--live-selection-cursor-marker
                                selection))
                       (cursor-position (marker-position cursor))
                       (beginning (min (marker-position anchor) cursor-position))
                       (end (max (marker-position anchor) cursor-position)))
                  ;; Native cursors provide endpoints only; nonempty selection
                  ;; highlighting remains an ordinary derived overlay.
                  (dolist (role (append (and (< beginning end) '(range))
                                        (and (not use-native) '(cursor))))
                    (let ((overlay (make-overlay beginning end buffer nil t)))
                      (push overlay overlays)
                      (overlay-put overlay 'selection-batch-view t)
                      (overlay-put overlay 'selection-batch-role role)
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
                       overlay beginning end cursor-position)))))))
          (setq overlays (nreverse overlays))
          ;; The native setter is part of the view transaction.  Until it has
          ;; succeeded, the session continues to own OLD-OVERLAYS and the old
          ;; native ledger; unwind cleanup owns only the new local list.
          (if use-native
              (selection-batch--install-native-cursors session)
            (when (selection-batch--native-cursors-available-p)
              (selection-batch--install-window-cursor-hooks)
              (selection-batch--reconcile-window-cursors)))
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
  "Indirect string reader used by transaction prompt tests.")

(defvar selection-batch--read-regexp-function #'read-regexp
  "Indirect regexp reader used by transaction prompt tests.")

(defvar selection-batch--transaction-map
  (let ((map (make-sparse-keymap)))
    ;; These bindings are active only in a transaction.  Frontend/user keys
    ;; are deliberately deferred; no global or major-mode keymap is changed.
    (define-key map (kbd "q") #'selection-batch-collapse)
    (define-key map (kbd "C-g") #'selection-batch-cancel)
    (define-key map [remap undo] #'selection-batch-undo)
    (define-key map [remap undo-only] #'selection-batch-undo)
    map)
  "Private transient map for an active selection transaction.")

(defun selection-batch-register-transaction-command (command)
  "Treat COMMAND as supported in the private transaction map.
A remapping entry records command capability without selecting a final frontend
or Meow key."
  (unless (commandp command)
    (signal 'wrong-type-argument (list 'commandp command)))
  (define-key selection-batch--transaction-map (vector 'remap command) command)
  command)

(defun selection-batch-undo ()
  "End the selection transaction, then undo one whole-buffer unit.
The live primary region is deliberately deactivated before `undo-only' so it
cannot silently turn the operation into undo-in-region.  Teardown happens
first, hence an undo error cannot leave a stale session or transient map."
  (interactive)
  (let ((session (selection-batch--owner-session t)))
    (selection-batch--cleanup session nil t))
  (let ((mark-active nil)
        ;; This command always begins its own one-unit undo operation, even
        ;; when a previous buffer's test or command left global undo identity.
        (last-command nil))
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

(defun selection-batch-safe-prompt (reader &rest arguments)
  "Call READER with ARGUMENTS while safely suspending the transaction map.
A completion, error, or `quit' resumes a fresh map.  A changed owner, current
buffer, or generation collapses stale state instead."
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
            (setq value (apply reader arguments))
          ((error quit) (setq condition err)))
      (selection-batch--prompt-resume session owner generation))
    (when condition
      (signal (car condition) (cdr condition)))
    value))

(defun selection-batch-read-string (prompt &optional initial-input)
  "Read a string through `selection-batch-safe-prompt'."
  (selection-batch-safe-prompt selection-batch--read-string-function
                               prompt initial-input))

(defun selection-batch-read-regexp (prompt)
  "Read a regexp through `selection-batch-safe-prompt'."
  (selection-batch-safe-prompt selection-batch--read-regexp-function prompt))

(provide 'selection-batch-ui)
;;; selection-batch-ui.el ends here
