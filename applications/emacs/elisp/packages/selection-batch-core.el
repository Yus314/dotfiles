;;; selection-batch-core.el --- Selection batch state -*- lexical-binding: t; -*-

;;; Commentary:
;; Integer snapshots, live selection sessions, providers, and pure selection
;; transformations.  This file deliberately contains no display or text-edit
;; engine.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

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
               (:constructor selection-batch-snapshot-selection-create))
  (id nil :read-only t)
  (anchor nil :read-only t)
  (cursor nil :read-only t))

(cl-defstruct (selection-batch-snapshot
               (:constructor selection-batch-snapshot-create))
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

(defun selection-batch--copy-selection (selection)
  "Copy snapshot SELECTION by value."
  (selection-batch-snapshot-selection-create
   :id (selection-batch-snapshot-selection-id selection)
   :anchor (selection-batch-snapshot-selection-anchor selection)
   :cursor (selection-batch-snapshot-selection-cursor selection)))

(defun selection-batch--copy-selections (selections)
  "Copy vector SELECTIONS and all of its values."
  (vconcat (mapcar #'selection-batch--copy-selection (append selections nil))))

(defun selection-batch--copy-snapshot (snapshot &optional selections primary-id)
  "Copy SNAPSHOT, optionally replacing SELECTIONS and PRIMARY-ID."
  (selection-batch-snapshot-create
   :buffer (selection-batch-snapshot-buffer snapshot)
   :buffer-tick (selection-batch-snapshot-buffer-tick snapshot)
   :generation (selection-batch-snapshot-generation snapshot)
   :primary-id (or primary-id (selection-batch-snapshot-primary-id snapshot))
   :narrowing (copy-tree (selection-batch-snapshot-narrowing snapshot))
   :selections (selection-batch--copy-selections
                (or selections (selection-batch-snapshot-selections snapshot)))))

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
  "Create live entries for SELECTIONS in BUFFER with PRIMARY-ID marker-free."
  (vconcat
   (mapcar
    (lambda (selection)
      (let ((id (selection-batch-snapshot-selection-id selection)))
        (if (equal id primary-id)
            (selection-batch--live-selection-create :id id)
          (selection-batch--live-selection-create
           :id id
           :anchor-marker (set-marker
                           (make-marker)
                           (selection-batch-snapshot-selection-anchor selection)
                           buffer)
           :cursor-marker (let ((marker (make-marker)))
                            (set-marker-insertion-type marker t)
                            (set-marker marker
                                        (selection-batch-snapshot-selection-cursor selection)
                                        buffer))))))
    (append selections nil))))

(defun selection-batch--validate-snapshot (snapshot)
  "Validate integer-only SNAPSHOT and return it."
  (unless (selection-batch-snapshot-p snapshot)
    (signal 'wrong-type-argument (list 'selection-batch-snapshot snapshot)))
  (let ((buffer (selection-batch-snapshot-buffer snapshot))
        (selections (selection-batch-snapshot-selections snapshot))
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

(defun selection-batch-install-snapshot (snapshot &optional allow-empty-primary)
  "Install SNAPSHOT as the sole live session.
When ALLOW-EMPTY-PRIMARY is non-nil, an initially unset mark is explicitly
initialized at point before installation.  SNAPSHOT itself always supplies the
projected primary endpoints."
  (selection-batch--validate-snapshot snapshot)
  (let* ((buffer (selection-batch-snapshot-buffer snapshot))
         (selections (selection-batch-snapshot-selections snapshot))
         (primary-id (selection-batch-snapshot-primary-id snapshot))
         (primary (selection-batch--selection-by-id selections primary-id)))
    (unless (eq buffer (current-buffer))
      (user-error "Install must run in the snapshot buffer"))
    (when (and allow-empty-primary
               (selection-batch-selection-empty-p primary)
               (null (selection-batch--mark-position)))
      (set-mark (point))
      (setq mark-active t))
    (when selection-batch--session
      (selection-batch--cleanup selection-batch--session nil t))
    (let* ((live (selection-batch--make-live-selections buffer selections primary-id))
           (session (selection-batch--session-create
                     :buffer buffer :selections live :primary-id primary-id
                     :history nil :redo nil
                     :generation (selection-batch-snapshot-generation snapshot)
                     :state 'set :overlays nil)))
      (condition-case err
          (progn
            (selection-batch--project-primary
             session
             (selection-batch-snapshot-selection-anchor primary)
             (selection-batch-snapshot-selection-cursor primary))
            (setq selection-batch--session session)
            (add-hook 'kill-buffer-hook #'selection-batch--lifecycle-exit nil t)
            (add-hook 'before-revert-hook #'selection-batch--lifecycle-exit nil t)
            (add-hook 'change-major-mode-hook #'selection-batch--lifecycle-exit nil t)
            session)
        ((error quit)
         (selection-batch--detach-selections live)
         (signal (car err) (cdr err)))))))

(defun selection-batch-current-snapshot ()
  "Return an integer-only snapshot of the current live session."
  (let* ((session (selection-batch--owner-session))
         (buffer (selection-batch--session-buffer session))
         values)
    (condition-case err
        (progn
          (dolist (selection (append (selection-batch--session-selections session) nil))
            (push (selection-batch-snapshot-selection-create
                   :id (selection-batch--live-selection-id selection)
                   :anchor (selection-batch-selection-anchor selection)
                   :cursor (selection-batch-selection-cursor selection))
                  values))
          (with-current-buffer buffer
            (selection-batch-snapshot-create
             :buffer buffer
             :buffer-tick (buffer-chars-modified-tick)
             :generation (selection-batch--session-generation session)
             :primary-id (selection-batch--session-primary-id session)
             :narrowing (cons (point-min) (point-max))
             :selections (vconcat (nreverse values)))))
      ((error quit)
       ;; Endpoint helpers already clean invariant failures.  Preserve other
       ;; errors, such as a caller-provided quit.
       (signal (car err) (cdr err))))))

(defun selection-batch--cleanup (session preserve-primary deactivate-mark-p)
  "Idempotently clean SESSION.
Keep its primary projection when PRESERVE-PRIMARY is non-nil.  Deactivate the
mark when DEACTIVATE-MARK-P is non-nil."
  (when (and session (not (selection-batch--session-exit-in-progress-p session)))
    (setf (selection-batch--session-exit-in-progress-p session) t)
    (let ((buffer (selection-batch--session-buffer session)))
      (unwind-protect
          (progn
            (when (and preserve-primary (buffer-live-p buffer))
              ;; point and mark already are the source of truth.
              (with-current-buffer buffer
                (when (selection-batch--mark-position) (setq mark-active t))))
            (dolist (overlay (selection-batch--session-overlays session))
              (when (overlayp overlay) (delete-overlay overlay)))
            (setf (selection-batch--session-overlays session) nil)
            (selection-batch--detach-selections
             (selection-batch--session-selections session))
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (remove-hook 'kill-buffer-hook #'selection-batch--lifecycle-exit t)
                (remove-hook 'before-revert-hook #'selection-batch--lifecycle-exit t)
                (remove-hook 'change-major-mode-hook #'selection-batch--lifecycle-exit t)
                (when deactivate-mark-p (ignore-errors (deactivate-mark)))))
            (let ((exit (selection-batch--session-transient-exit-function session)))
              (setf (selection-batch--session-transient-exit-function session) nil)
              (when (functionp exit) (ignore-errors (funcall exit)))))
        (when (eq selection-batch--session session)
          (setq selection-batch--session nil))))))

(defun selection-batch--lifecycle-exit ()
  "Exit the session owned by the current buffer."
  (when (and selection-batch--session
             (eq (current-buffer) (selection-batch--session-buffer selection-batch--session)))
    (selection-batch--cleanup selection-batch--session nil t)))

(defun selection-batch-collapse ()
  "End the live session while preserving its primary region."
  (interactive)
  (let ((session (selection-batch--owner-session t)))
    (selection-batch--cleanup session t nil)))

(defun selection-batch-cancel ()
  "Cancel the live session and deactivate its primary region."
  (interactive)
  (let ((session (selection-batch--owner-session t)))
    (selection-batch--cleanup session nil t)))

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
      (selection-batch-snapshot-selections snapshot) new
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
  (let* ((original (selection-batch-snapshot-selections snapshot))
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
        (if (and current
                 (cl-some (lambda (member)
                            (selection-batch--overlap-p (cdr member) (cdr item)))
                          current))
            (setq current (append current (list item)))
          (when current (push current groups))
          (setq current (list item))))
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
                                             (< (selection-batch-selection-end selection) origin))
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
         values (id 0))
    (save-excursion
      (goto-char (max (car bounds) (point-min)))
      (while (and (<= (point) limit) (re-search-forward regexp limit t))
        (let ((beginning (match-beginning 0))
              (end (match-end 0)))
          (push (selection-batch-snapshot-selection-create
                 :id id :anchor beginning :cursor end) values)
          (setq id (1+ id))
          ;; Emacs normally advances repeated empty matches itself.  The
          ;; explicit guard also makes this true for boundary-only regexps.
          (when (and (= beginning end) (= (point) beginning) (< (point) limit))
            (forward-char 1)))))
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
    (selection-batch-snapshot-create
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
                     (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-batch-transform-drop-regexp (snapshot regexp)
  "Drop SNAPSHOT selections whose text matches REGEXP."
  (selection-batch--filtered-snapshot
   snapshot
   (cl-remove-if (lambda (selection)
                   (string-match-p regexp
                                   (selection-batch--selection-text snapshot selection)))
                 (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-batch-transform-split-lines (snapshot)
  "Split each SNAPSHOT selection into per-line content selections."
  (let (output (next-id 0))
    (dolist (selection (append (selection-batch-snapshot-selections snapshot) nil))
      (let ((beginning (selection-batch-selection-beginning selection))
            (end (selection-batch-selection-end selection))
            pieces (piece-index 0))
        (with-current-buffer (selection-batch-snapshot-buffer snapshot)
          (setq pieces (selection-batch-provider-result-selections
                        (selection-batch-provider-lines beginning end))))
        (dolist (piece (append pieces nil))
          (let ((id (if (= piece-index 0)
                        (selection-batch-snapshot-selection-id selection)
                      (while (selection-batch--selection-by-id
                              (vconcat output) (format "split-%d" next-id))
                        (setq next-id (1+ next-id)))
                      (prog1 (format "split-%d" next-id)
                        (setq next-id (1+ next-id))))))
            (push (selection-batch-snapshot-selection-create
                   :id id
                   :anchor (selection-batch-snapshot-selection-anchor piece)
                   :cursor (selection-batch-snapshot-selection-cursor piece))
                  output)
            (setq piece-index (1+ piece-index))))))
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
            (append (selection-batch-snapshot-selections snapshot) nil)))))

(defun selection-batch-transform-merge (snapshot)
  "Merge overlapping selections in SNAPSHOT."
  (selection-batch-normalize-snapshot snapshot 'merge))

(defun selection-batch-transform-rotate-primary (snapshot &optional backward)
  "Rotate SNAPSHOT primary one logical step, BACKWARD when non-nil."
  (let* ((selections (selection-batch-snapshot-selections snapshot))
         (length (length selections))
         (index (cl-position (selection-batch-snapshot-primary-id snapshot)
                             (append selections nil)
                             :key #'selection-batch-snapshot-selection-id :test #'equal))
         (next (mod (+ index (if backward -1 1)) length)))
    (selection-batch--copy-snapshot
     snapshot selections (selection-batch-snapshot-selection-id (aref selections next)))))

(defun selection-batch--replace-with-snapshot (session snapshot)
  "Replace SESSION's live state with SNAPSHOT once."
  (selection-batch--validate-snapshot snapshot)
  (unless (and (eq session selection-batch--session)
               (eq (current-buffer) (selection-batch--session-buffer session))
               (eq (selection-batch-snapshot-buffer snapshot)
                   (selection-batch--session-buffer session)))
    (user-error "Cannot replace a stale or foreign session"))
  (let* ((selections (selection-batch-snapshot-selections snapshot))
         (primary-id (selection-batch-snapshot-primary-id snapshot))
         (primary (selection-batch--selection-by-id selections primary-id))
         (old-live (selection-batch--session-selections session))
         (new-live (selection-batch--make-live-selections
                    (current-buffer) selections primary-id)))
    (condition-case err
        (progn
          (selection-batch--project-primary
           session
           (selection-batch-snapshot-selection-anchor primary)
           (selection-batch-snapshot-selection-cursor primary))
          (selection-batch--detach-selections old-live)
          (setf (selection-batch--session-selections session) new-live
                (selection-batch--session-primary-id session) primary-id
                (selection-batch--session-generation session)
                (1+ (selection-batch--session-generation session)))
          session)
      ((error quit)
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

(provide 'selection-batch-core)
;;; selection-batch-core.el ends here
