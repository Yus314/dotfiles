;;; selection-first.el --- Meow-independent selection-first frontend -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314

;; Author: Yus314 <shizhaoyoujie@gmail.com>
;; Maintainer: Yus314 <shizhaoyoujie@gmail.com>
;; Version: 0.1.0-pre
;; Package-Requires: ((emacs "31.0"))
;; Keywords: editing, convenience
;; URL: https://github.com/Yus314/selection-first.el
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; A small modal frontend over selection-batch.  It presents singleton native
;; point/mark state and plural selection-batch sessions through one SelectionSet
;; boundary, without consulting Meow state or replaying commands per selection.

;;; Code:

(require 'cl-lib)
(require 'selection-batch)

(defgroup selection-first nil
  "Selection-first modal editing over selection-batch."
  :group 'editing)

(defvar-local selection-first-mode nil
  "Non-nil when the selection-first frontend is enabled in this buffer.")

(defvar-local selection-first--state nil
  "Current frontend state, including `normal', `insert', and `batch-insert'.")

(defvar-local selection-first--normal-active nil
  "Non-nil while the selection-first normal keymap should be active.")

(defvar-local selection-first--batch-insert-active nil
  "Non-nil while the transactional batch-insert keymap is active.")

(defvar-local selection-first--batch-insert-fingerprint nil
  "Expected exclusive ownership state for the next batch-insert intent.")

(defvar-local selection-first--vertical-run nil
  "Continuation record for a vertical command run.
The plist contains `:goals' and the successful result `:fingerprint'.")

(defvar-local selection-first--selection-history nil
  "Frontend selection-only undo snapshots for the current buffer.")

(defvar-local selection-first--selection-redo nil
  "Frontend selection-only redo snapshots for the current buffer.")

(defun selection-first--clear-selection-history ()
  "Clear frontend selection-only undo and redo state."
  (setq selection-first--selection-history nil
        selection-first--selection-redo nil))

(defun selection-first--bounded-cons (snapshot history)
  "Prepend SNAPSHOT to HISTORY while respecting the configured history limit."
  (let ((limit selection-batch-history-limit))
    (cond
     ((= limit 0) nil)
     ((< (length history) limit) (cons snapshot history))
     (t (cl-subseq (cons snapshot history) 0 limit)))))

(defconst selection-first--vertical-commands
  '(selection-first-previous-line
    selection-first-next-line
    selection-first-previous-line-extend
    selection-first-next-line-extend)
  "Commands that continue a per-selection vertical goal-column run.")

(defun selection-first--eligible-buffer-p ()
  "Return non-nil when the current buffer supports selection-first editing."
  (and (not (minibufferp))
       (not buffer-read-only)
       (not (derived-mode-p 'special-mode))))

(defun selection-first--set-state (state)
  "Set the current frontend STATE and refresh keymap activation."
  (unless (eq state 'batch-insert)
    (setq selection-first--batch-insert-fingerprint nil))
  (setq selection-first--state state
        selection-first--normal-active
        (and selection-first-mode (eq state 'normal))
        selection-first--batch-insert-active
        (and selection-first-mode (eq state 'batch-insert))))

(defun selection-first--own-session-p ()
  "Return non-nil when the live session belongs to the current buffer."
  (selection-batch-owned-by-p))

(defun selection-first--collapse-foreign-session ()
  "Collapse a live session owned by another buffer before ownership handoff."
  (when (and (selection-batch-active-p)
             (not (selection-first--own-session-p)))
    (selection-batch-collapse-owner)))

(defun selection-first-current-snapshot ()
  "Return the current singleton or plural selection set as a snapshot."
  (selection-first--collapse-foreign-session)
  (if (selection-first--own-session-p)
      (selection-batch-current-snapshot)
    (selection-batch-provider-snapshot
     (selection-batch-provider-region t))))

(defun selection-first--project-single (selection)
  "Project SELECTION to native point/mark without retaining a session."
  (when (selection-first--own-session-p)
    (selection-batch-collapse))
  (goto-char (selection-batch-snapshot-selection-cursor selection))
  (set-mark (selection-batch-snapshot-selection-anchor selection))
  (setq mark-active t)
  (activate-mark)
  nil)

(defun selection-first--assert-current-snapshot-context
    (snapshot &optional ignore-generation)
  "Reject foreign or stale SNAPSHOT before frontend installation.
When IGNORE-GENERATION is non-nil, validate only immutable buffer context."
  (unless (eq (selection-batch-snapshot-buffer snapshot) (current-buffer))
    (user-error "Cannot install a selection set from another buffer"))
  (unless (= (selection-batch-snapshot-buffer-tick snapshot)
             (buffer-chars-modified-tick))
    (user-error "Selection snapshot buffer tick is stale"))
  (unless (equal (selection-batch-snapshot-narrowing snapshot)
                 (cons (point-min) (point-max)))
    (user-error "Selection snapshot narrowing is stale"))
  (when (and (not ignore-generation)
             (selection-first--own-session-p))
    (unless (= (selection-batch-snapshot-generation snapshot)
               (selection-batch-snapshot-generation
                (selection-batch-current-snapshot)))
      (user-error "Selection snapshot generation is stale"))))

(defun selection-first-install-snapshot (snapshot)
  "Install SNAPSHOT through the singleton/plural storage boundary."
  (unless (eq (current-buffer)
              (selection-batch-snapshot-buffer snapshot))
    (user-error "Cannot install a selection set from another buffer"))
  (selection-first--collapse-foreign-session)
  (selection-first--assert-current-snapshot-context snapshot)
  (let* ((normalized (selection-batch-normalize-snapshot snapshot 'reject))
         (selections (selection-batch-snapshot-selections normalized)))
    (if (= 1 (length selections))
        (progn
          (selection-first--project-single (aref selections 0))
          normalized)
      (selection-batch-install-snapshot normalized t)
      (selection-batch-current-snapshot))))

(defun selection-first-install-ranges (ranges &optional primary-id)
  "Install RANGES as the current set.
Each range is (ID ANCHOR CURSOR).  PRIMARY-ID defaults to the first ID."
  (unless ranges
    (user-error "A selection set cannot be empty"))
  (selection-first-install-snapshot
   (selection-batch-snapshot-create
    :buffer (current-buffer)
    :buffer-tick (buffer-chars-modified-tick)
    :generation (if (selection-first--own-session-p)
                    (selection-batch-snapshot-generation
                     (selection-batch-current-snapshot))
                  0)
    :primary-id (or primary-id (caar ranges))
    :narrowing (cons (point-min) (point-max))
    :selections
    (vconcat
     (mapcar
      (lambda (range)
        (pcase-let ((`(,id ,anchor ,cursor) range))
          (selection-batch-snapshot-selection-create
           :id id :anchor anchor :cursor cursor)))
      ranges)))))

(defun selection-first--copy-snapshot-with-selections (source selections)
  "Copy SOURCE while replacing its immutable SELECTIONS."
  (selection-batch-snapshot-with-selections source (vconcat selections)))

(defun selection-first--reconcile-installed-snapshot (snapshot)
  "Enforce the frontend's native-singleton/plural-session boundary for SNAPSHOT."
  (if (and (selection-first--own-session-p)
           (= 1 (length (selection-batch-snapshot-selections snapshot))))
      (progn
        (selection-batch-collapse)
        snapshot)
    snapshot))

(defun selection-first--snapshot-semantic-equal-p (left right)
  "Return non-nil when LEFT and RIGHT describe the same SelectionSet value."
  (and (eq (selection-batch-snapshot-buffer left)
           (selection-batch-snapshot-buffer right))
       (= (selection-batch-snapshot-buffer-tick left)
          (selection-batch-snapshot-buffer-tick right))
       (equal (selection-batch-snapshot-narrowing left)
              (selection-batch-snapshot-narrowing right))
       (equal (selection-batch-snapshot-primary-id left)
              (selection-batch-snapshot-primary-id right))
       (equal (selection-batch-snapshot-selections left)
              (selection-batch-snapshot-selections right))))

(defun selection-first--record-selection-transition (before after)
  "Record a successful selection-only transition from BEFORE to AFTER."
  (unless (selection-first--snapshot-semantic-equal-p before after)
    (setq selection-first--selection-history
          (selection-first--bounded-cons
           before selection-first--selection-history)
          selection-first--selection-redo nil)))

(defun selection-first--apply-transform-raw (transform arguments)
  "Apply TRANSFORM with ARGUMENTS without changing frontend history."
  (selection-first--collapse-foreign-session)
  (if (selection-first--own-session-p)
      (selection-first--reconcile-installed-snapshot
       (apply #'selection-batch-apply-transform transform arguments))
    (let* ((before (selection-first-current-snapshot))
           (candidate (apply transform before arguments)))
      (selection-first-install-snapshot candidate))))

(defun selection-first--apply-transform (transform &rest arguments)
  "Apply pure TRANSFORM with ARGUMENTS to the current set."
  (let* ((before (selection-first-current-snapshot))
         (after (selection-first--apply-transform-raw transform arguments)))
    (selection-first--record-selection-transition before after)
    after))

(defun selection-first--map-selections (snapshot function)
  "Return SNAPSHOT with FUNCTION applied to every selection."
  (selection-first--copy-snapshot-with-selections
   snapshot
   (mapcar function
           (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-first--char-motion (snapshot direction extend)
  "Move every SNAPSHOT selection by one char in DIRECTION.
When EXTEND is non-nil retain each anchor; otherwise select the adjacent char."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (selection-first--map-selections
     snapshot
     (lambda (selection)
       (let* ((id (selection-batch-snapshot-selection-id selection))
              (cursor (selection-batch-snapshot-selection-cursor selection))
              anchor target)
         (if extend
             (setq anchor (selection-batch-snapshot-selection-anchor selection)
                   target (+ cursor direction))
           (if (> direction 0)
               (setq anchor (selection-batch-selection-end selection)
                     target (1+ anchor))
             (setq anchor (selection-batch-selection-beginning selection)
                   target (1- anchor))))
         (unless (<= (point-min) target (point-max))
           (user-error "Selection motion reached buffer boundary"))
         (selection-batch-snapshot-selection-create
          :id id :anchor anchor :cursor target))))))

(defun selection-first-forward-char ()
  "Select the next character for every selection."
  (interactive)
  (selection-first--apply-transform #'selection-first--char-motion 1 nil))

(defun selection-first-backward-char ()
  "Select the previous character backward for every selection."
  (interactive)
  (selection-first--apply-transform #'selection-first--char-motion -1 nil))

(defun selection-first-forward-char-extend ()
  "Extend every selection cursor forward by one character."
  (interactive)
  (selection-first--apply-transform #'selection-first--char-motion 1 t))

(defun selection-first-backward-char-extend ()
  "Extend every selection cursor backward by one character."
  (interactive)
  (selection-first--apply-transform #'selection-first--char-motion -1 t))

(defun selection-first--word-target (cursor direction)
  "Return word boundary from CURSOR in DIRECTION."
  (save-excursion
    (goto-char cursor)
    (condition-case nil
        (if (> direction 0) (forward-word 1) (backward-word 1))
      ((beginning-of-buffer end-of-buffer)
       (user-error "Selection motion reached buffer boundary")))
    (point)))

(defun selection-first--word-motion (snapshot direction)
  "Move every SNAPSHOT selection to a word in DIRECTION."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (selection-first--map-selections
     snapshot
     (lambda (selection)
       (let* ((cursor (selection-batch-snapshot-selection-cursor selection))
              (target (selection-first--word-target cursor direction)))
         (selection-batch-snapshot-selection-create
          :id (selection-batch-snapshot-selection-id selection)
          :anchor cursor :cursor target))))))

(defun selection-first-forward-word ()
  "Select forward to the next word boundary for every selection."
  (interactive)
  (selection-first--apply-transform #'selection-first--word-motion 1))

(defun selection-first-backward-word ()
  "Select backward to the previous word boundary for every selection."
  (interactive)
  (selection-first--apply-transform #'selection-first--word-motion -1))

(defun selection-first--cursor-column (selection)
  "Return the display column of SELECTION's cursor."
  (save-excursion
    (goto-char (selection-batch-snapshot-selection-cursor selection))
    (current-column)))

(defun selection-first--fresh-vertical-goals (snapshot)
  "Return freshly measured per-selection display columns for SNAPSHOT."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (mapcar
     (lambda (selection)
       (cons (selection-batch-snapshot-selection-id selection)
             (selection-first--cursor-column selection)))
     (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-first--snapshot-fingerprint (snapshot)
  "Return the state fingerprint that owns a vertical run for SNAPSHOT."
  (list
   (selection-batch-snapshot-buffer snapshot)
   (selection-batch-snapshot-buffer-tick snapshot)
   (selection-batch-snapshot-narrowing snapshot)
   (mapcar
    (lambda (selection)
      (list (selection-batch-snapshot-selection-id selection)
            (selection-batch-snapshot-selection-anchor selection)
            (selection-batch-snapshot-selection-cursor selection)))
    (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-first--continuing-vertical-goals-p (snapshot)
  "Return non-nil when the stored vertical run owns SNAPSHOT exactly."
  (and (memq last-command selection-first--vertical-commands)
       selection-first--vertical-run
       (equal (plist-get selection-first--vertical-run :fingerprint)
              (selection-first--snapshot-fingerprint snapshot))))

(defun selection-first--vertical-goals-for (snapshot)
  "Return continuing or freshly measured goal columns for SNAPSHOT."
  (if (selection-first--continuing-vertical-goals-p snapshot)
      (plist-get selection-first--vertical-run :goals)
    (selection-first--fresh-vertical-goals snapshot)))

(defun selection-first--line-target (cursor direction target-column)
  "Move from CURSOR one logical line in DIRECTION toward TARGET-COLUMN.
Signal `user-error' at the accessible buffer boundary.  Short lines clamp at
end of line; no whitespace is inserted."
  (save-excursion
    (goto-char cursor)
    (unless (zerop (forward-line direction))
      (user-error "Selection motion reached buffer boundary"))
    (move-to-column target-column)
    (point)))

(defun selection-first--line-motion (snapshot direction extend goals)
  "Move every SNAPSHOT cursor one logical line in DIRECTION.
GOALS maps selection IDs to display columns.  When EXTEND is non-nil retain
each anchor; otherwise install an empty caret at each target."
  (with-current-buffer (selection-batch-snapshot-buffer snapshot)
    (let ((moved
           (mapcar
            (lambda (selection)
              (let* ((id (selection-batch-snapshot-selection-id selection))
                     (goal-entry (cl-assoc id goals :test #'equal))
                     (cursor
                      (selection-batch-snapshot-selection-cursor selection)))
                (unless goal-entry
                  (user-error "Vertical goal column is missing for a selection"))
                (let ((target (selection-first--line-target
                               cursor direction (cdr goal-entry))))
                  (selection-batch-snapshot-selection-create
                   :id id
                   :anchor (if extend
                               (selection-batch-snapshot-selection-anchor selection)
                             target)
                   :cursor target))))
            (append (selection-batch-snapshot-selections snapshot) nil))))
      (unless extend
        (let ((seen (make-hash-table :test #'eql)))
          (dolist (selection moved)
            (let ((target
                   (selection-batch-snapshot-selection-cursor selection)))
              (when (gethash target seen)
                (user-error "Vertical motion would merge selection cursors"))
              (puthash target t seen)))))
      (selection-first--copy-snapshot-with-selections snapshot moved))))

(defun selection-first--run-line-motion (direction extend)
  "Run one vertical motion in DIRECTION, retaining anchors when EXTEND."
  (let* ((snapshot (selection-first-current-snapshot))
         (goals (selection-first--vertical-goals-for snapshot))
         (result (selection-first--apply-transform
                  #'selection-first--line-motion direction extend goals))
         (after (selection-first-current-snapshot)))
    (setq selection-first--vertical-run
          (list :goals (copy-tree goals)
                :fingerprint (selection-first--snapshot-fingerprint after)))
    result))

(defun selection-first-previous-line ()
  "Move every selection cursor to the previous logical line."
  (interactive)
  (selection-first--run-line-motion -1 nil))

(defun selection-first-next-line ()
  "Move every selection cursor to the next logical line."
  (interactive)
  (selection-first--run-line-motion 1 nil))

(defun selection-first-previous-line-extend ()
  "Extend every selection cursor to the previous logical line."
  (interactive)
  (selection-first--run-line-motion -1 t))

(defun selection-first-next-line-extend ()
  "Extend every selection cursor to the next logical line."
  (interactive)
  (selection-first--run-line-motion 1 t))

(defun selection-first-reverse ()
  "Reverse every selection direction."
  (interactive)
  (selection-first--apply-transform #'selection-batch-transform-reverse))

(defun selection-first-gather-same-all ()
  "Select every occurrence equal to the current primary selection."
  (interactive)
  (let* ((before (selection-first-current-snapshot))
         (candidate
          (selection-batch-provider-snapshot
           (selection-batch-provider-current-same-text 'all)))
         (after (selection-first-install-snapshot candidate)))
    (selection-first--record-selection-transition before after)
    after))

(defun selection-first-gather-same-next ()
  "Add the next unselected occurrence equal to the primary selection."
  (interactive)
  (selection-first--apply-transform
   #'selection-batch-transform-add-same 'next))

(defun selection-first-gather-same-previous ()
  "Add the previous unselected occurrence equal to the primary selection."
  (interactive)
  (selection-first--apply-transform
   #'selection-batch-transform-add-same 'previous))

(defun selection-first--materialize-session ()
  "Ensure the current set is represented by a live selection-batch session."
  (selection-first--collapse-foreign-session)
  (unless (selection-first--own-session-p)
    (selection-batch-install-snapshot (selection-first-current-snapshot) t))
  (selection-batch-current-snapshot))

(defun selection-first--restore-history-snapshot (target)
  "Restore selection-only TARGET against the unchanged current buffer."
  (selection-first--assert-current-snapshot-context target t)
  (selection-first--materialize-session)
  (selection-first--reconcile-installed-snapshot
   (selection-batch-apply-transform
    (lambda (current saved)
      (selection-batch-snapshot-with-selections
       current
       (selection-batch-snapshot-selections saved)
       (selection-batch-snapshot-primary-id saved)))
    target)))

(defun selection-first--call-batch-command
    (command &optional demote-single history-barrier)
  "Materialize the set, call COMMAND, and optionally DEMOTE-SINGLE.
Clear selection-only history after success when HISTORY-BARRIER is non-nil."
  (let ((created (not (selection-first--own-session-p))))
    (selection-first--materialize-session)
    (condition-case err
        (prog1 (funcall command)
          (when history-barrier
            (selection-first--clear-selection-history))
          (when (and demote-single
                     (selection-first--own-session-p)
                     (= 1 (selection-batch-count)))
            (selection-batch-collapse)))
      ((error quit)
       (when (and created (selection-first--own-session-p))
         (selection-batch-collapse))
       (signal (car err) (cdr err))))))

(defun selection-first-copy ()
  "Copy the current set into the typed vector register."
  (interactive)
  (selection-first--call-batch-command #'selection-batch-copy t))

(defun selection-first-delete ()
  "Delete the current set atomically."
  (interactive)
  (selection-first--call-batch-command #'selection-batch-delete t t))

(defun selection-first--read-string (prompt)
  "Read a string with PROMPT using the current SelectionSet owner safely."
  (selection-first--collapse-foreign-session)
  (if (selection-first--own-session-p)
      (selection-batch-read-string prompt)
    (read-string prompt)))

(defun selection-first--read-regexp (prompt)
  "Read a regexp with PROMPT without exposing a suspended plural session."
  (selection-first--collapse-foreign-session)
  (if (selection-first--own-session-p)
      (selection-batch-read-regexp prompt)
    (read-regexp prompt)))

(defun selection-first-keep-regexp (regexp)
  "Keep selections whose text matches REGEXP."
  (interactive (list (selection-first--read-regexp "Keep selections matching: ")))
  (selection-first--apply-transform
   #'selection-batch-transform-keep-regexp regexp))

(defun selection-first-drop-regexp (regexp)
  "Drop selections whose text matches REGEXP."
  (interactive (list (selection-first--read-regexp "Drop selections matching: ")))
  (selection-first--apply-transform
   #'selection-batch-transform-drop-regexp regexp))

(defun selection-first-insert-before-all (string)
  "Insert fixed STRING before every current selection atomically."
  (interactive (list (selection-first--read-string "Insert before all: ")))
  (selection-first--call-batch-command
   (lambda () (selection-batch-insert-before string)) t t))

(defun selection-first-insert-after-all (string)
  "Insert fixed STRING after every current selection atomically."
  (interactive (list (selection-first--read-string "Insert after all: ")))
  (selection-first--call-batch-command
   (lambda () (selection-batch-insert-after string)) t t))

(defun selection-first--recipe-text-changing-p ()
  "Return non-nil when the current semantic recipe can change buffer text."
  (and (selection-batch-recipe-p selection-batch-last-recipe)
       (memq (selection-batch-recipe-operator selection-batch-last-recipe)
             '(delete replace uppercase lowercase capitalize
               insert-before insert-after paste))))

(defun selection-first-repeat ()
  "Repeat the last semantic selection recipe against the current set."
  (interactive)
  (let ((history-barrier (selection-first--recipe-text-changing-p)))
    (selection-first--call-batch-command
     #'selection-batch-repeat t history-barrier)))

(defun selection-first-replace (string)
  "Replace every current selection with STRING."
  (interactive (list (selection-first--read-string "Replace with: ")))
  (selection-first--call-batch-command
   (lambda () (selection-batch-replace string)) t t))

(defun selection-first-paste ()
  "Paste the typed vector register over the current set."
  (interactive)
  (selection-first--call-batch-command #'selection-batch-paste t t))

(defun selection-first-undo ()
  "Undo one whole-buffer text unit and return to a singleton set."
  (interactive)
  (selection-first--collapse-foreign-session)
  (if (selection-first--own-session-p)
      (selection-batch-undo)
    (let ((mark-active nil))
      (undo-only 1)))
  (selection-first--clear-selection-history)
  (selection-first--set-state 'normal))

(defun selection-first-selection-undo ()
  "Undo one selection-only transformation across singleton/plural storage."
  (interactive)
  (unless selection-first--selection-history
    (user-error "No selection history"))
  (let ((target (car selection-first--selection-history)))
    (selection-first--assert-current-snapshot-context target t)
    (let* ((before (selection-first-current-snapshot))
           (after (selection-first--restore-history-snapshot target)))
      (setq selection-first--selection-history
            (cdr selection-first--selection-history)
            selection-first--selection-redo
            (selection-first--bounded-cons
             before selection-first--selection-redo))
      after)))

(defun selection-first-selection-redo ()
  "Redo one selection-only transformation across singleton/plural storage."
  (interactive)
  (unless selection-first--selection-redo
    (user-error "No selection redo"))
  (let ((target (car selection-first--selection-redo)))
    (selection-first--assert-current-snapshot-context target t)
    (let* ((before (selection-first-current-snapshot))
           (after (selection-first--restore-history-snapshot target)))
      (setq selection-first--selection-redo
            (cdr selection-first--selection-redo)
            selection-first--selection-history
            (selection-first--bounded-cons
             before selection-first--selection-history))
      after)))

(defun selection-first--batch-endpoint-transform (snapshot cursor-p)
  "Return plural SNAPSHOT as unique empty carets at its directed endpoints.
Use each selection's cursor endpoint when CURSOR-P, otherwise its anchor."
  (let ((seen (make-hash-table :test #'eql)))
    (selection-first--map-selections
     snapshot
     (lambda (selection)
       (let ((position (if cursor-p
                           (selection-batch-snapshot-selection-cursor selection)
                         (selection-batch-snapshot-selection-anchor selection))))
         (when (gethash position seen)
           (user-error "Batch insertion carets share position %d" position))
         (puthash position t seen)
         (selection-batch-snapshot-selection-create
          :id (selection-batch-snapshot-selection-id selection)
          :anchor position :cursor position))))))

(defun selection-first--enter-insert (cursor-p)
  "Enter singleton native or plural insertion at a directed endpoint.
Use each selection's cursor endpoint when CURSOR-P, otherwise its anchor."
  (let* ((snapshot (selection-first-current-snapshot))
         (selections (selection-batch-snapshot-selections snapshot)))
    (if (= 1 (length selections))
        (let ((selection (aref selections 0)))
          (when (selection-first--own-session-p) (selection-batch-collapse))
          (goto-char (if cursor-p
                         (selection-batch-snapshot-selection-cursor selection)
                       (selection-batch-snapshot-selection-anchor selection)))
          (deactivate-mark)
          (selection-first--clear-selection-history)
          (selection-first--set-state 'insert))
      (selection-first--apply-transform
       #'selection-first--batch-endpoint-transform cursor-p)
      (selection-first--clear-selection-history)
      (selection-first--set-state 'batch-insert)
      (setq selection-first--batch-insert-fingerprint
            (selection-first--batch-fingerprint)))))

(defun selection-first-insert ()
  "Enter native singleton or plural transactional insertion at cursors."
  (interactive)
  (selection-first--enter-insert t))

(defun selection-first-append ()
  "Enter native singleton or plural transactional insertion at anchors."
  (interactive)
  (selection-first--enter-insert nil))

(defun selection-first--batch-fingerprint ()
  "Return the current complete batch-insert ownership fingerprint."
  (let ((snapshot (selection-batch-current-snapshot)))
    (list :buffer (current-buffer)
          :tick (buffer-chars-modified-tick)
          :generation (selection-batch-snapshot-generation snapshot)
          :narrowing (cons (point-min) (point-max))
          :carets
          (mapcar (lambda (selection)
                    (list (selection-batch-snapshot-selection-id selection)
                          (selection-batch-snapshot-selection-anchor selection)
                          (selection-batch-snapshot-selection-cursor selection)))
                  (append (selection-batch-snapshot-selections snapshot) nil)))))

(defun selection-first--require-batch-insert ()
  "Return the current batch-insert snapshot or reject invalid frontend state."
  (unless (and (eq selection-first--state 'batch-insert)
               (selection-first--own-session-p))
    (user-error "No plural batch-insert session is active"))
  (unless (equal selection-first--batch-insert-fingerprint
                 (selection-first--batch-fingerprint))
    (user-error "Batch-insert ownership changed outside an intent"))
  (selection-batch-current-snapshot))

(defun selection-first--batch-record-success (snapshot)
  "Record ownership after a successful intent returning SNAPSHOT."
  (setq selection-first--batch-insert-fingerprint
        (selection-first--batch-fingerprint))
  snapshot)

(defun selection-first-batch-insert-string (string)
  "Insert committed literal STRING at every batch caret as one immutable plan.
This is the adapter boundary for future committed-text frontends; it does not
invoke or replay `self-insert-command'."
  (interactive "sCommitted text: ")
  (let ((source (selection-first--require-batch-insert)))
    (condition-case err
        (prog1 (selection-first--batch-record-success
                (selection-batch-apply-plan
                 (selection-batch--plan-caret-insert source string)))
          (selection-first--clear-selection-history))
      ((error quit)
       (if (and (eq selection-first--state 'batch-insert)
                (selection-first--own-session-p))
           ;; Atomic rollback advances Emacs' monotonic modification tick even
           ;; though it restored the owned session and all buffer contents.
           (setq selection-first--batch-insert-fingerprint
                 (selection-first--batch-fingerprint))
         (selection-first--set-state 'normal))
       (signal (car err) (cdr err))))))

(defun selection-first-batch-self-insert ()
  "Commit the current printable input event literally to all batch carets."
  (interactive)
  (unless (characterp last-command-event)
    (user-error "Batch insertion requires a character event"))
  (when (eq (get-char-code-property last-command-event 'general-category) 'Cc)
    (user-error "Batch insertion requires a printable character"))
  (selection-first-batch-insert-string (string last-command-event)))

(defun selection-first-batch-newline ()
  "Commit one literal newline to all batch carets."
  (interactive)
  (selection-first-batch-insert-string "\n"))

(defun selection-first--batch-delete-plan (source forward-p)
  "Plan one-character deletion at every SOURCE caret in direction FORWARD-P."
  (let ((selections (append (selection-batch-snapshot-selections source) nil))
        points)
    (dolist (selection selections)
      (unless (selection-batch-selection-empty-p selection)
        (user-error "Batch deletion requires empty carets"))
      (let* ((position (selection-batch-selection-beginning selection))
             (beginning (if forward-p position (1- position)))
             (end (if forward-p (1+ position) position)))
        (unless (and (<= (point-min) beginning) (<= end (point-max)))
          (user-error "Batch deletion reached buffer boundary"))
        (push (selection-batch-snapshot-selection-create
               :id (selection-batch-snapshot-selection-id selection)
               :anchor beginning :cursor end)
              points)))
    (let* ((plan (selection-batch--operator-edit-plan
                  source (nreverse points) (make-list (length selections) "")
                  (if forward-p 'batch-delete-forward 'batch-delete-backward)
                  nil 'caret))
           (seen (make-hash-table :test #'eql)))
      (dolist (selection
               (append (selection-batch-snapshot-selections
                        (selection-batch-plan-result-policy plan)) nil))
        (let ((position (selection-batch-selection-beginning selection)))
          (when (gethash position seen)
            (user-error "Batch deletion would merge carets at %d" position))
          (puthash position t seen)))
      plan)))

(defun selection-first-batch-delete-backward ()
  "Delete one character backward at every caret atomically."
  (interactive)
  (condition-case err
      (selection-first--batch-record-success
       (selection-batch-apply-plan
        (selection-first--batch-delete-plan
         (selection-first--require-batch-insert) nil)))
    ((error quit)
     (unless (selection-first--own-session-p)
       (selection-first--set-state 'normal))
     (signal (car err) (cdr err)))))

(defun selection-first-batch-delete-forward ()
  "Delete one character forward at every caret atomically."
  (interactive)
  (condition-case err
      (selection-first--batch-record-success
       (selection-batch-apply-plan
        (selection-first--batch-delete-plan
         (selection-first--require-batch-insert) t)))
    ((error quit)
     (unless (selection-first--own-session-p)
       (selection-first--set-state 'normal))
     (signal (car err) (cdr err)))))

(defun selection-first-exit-batch-insert ()
  "Leave batch insertion while retaining its plural empty-caret session."
  (interactive)
  (when (eq selection-first--state 'batch-insert)
    (selection-first--set-state 'normal)))

(defun selection-first-exit-insert ()
  "Leave native insert state and import point as a singleton caret."
  (interactive)
  (when (eq selection-first--state 'insert)
    (deactivate-mark)
    (selection-first--set-state 'normal)))

(defun selection-first-collapse ()
  "Collapse a plural set to its primary native region."
  (interactive)
  (selection-first--collapse-foreign-session)
  (when (selection-first--own-session-p)
    (selection-batch-collapse))
  (selection-first--clear-selection-history)
  (selection-first--set-state 'normal))

(defun selection-first--prepare-native-handoff ()
  "Collapse frontend-owned plural state before native command ownership."
  (selection-first--collapse-foreign-session)
  (when (selection-first--own-session-p)
    (selection-batch-collapse))
  (selection-first--clear-selection-history))

(defun selection-first--restore-source-normal-state (source)
  "Restore normal state in live enabled SOURCE only."
  (when (buffer-live-p source)
    (with-current-buffer source
      (when selection-first-mode
        (if (selection-first--eligible-buffer-p)
            (selection-first--set-state 'normal)
          (selection-first-mode -1))))))

(defun selection-first--call-native-command (command)
  "Call interactive COMMAND once while the frontend is in passthrough state."
  (unless (commandp command)
    (signal 'wrong-type-argument (list 'commandp command)))
  (selection-first--prepare-native-handoff)
  (let ((source (current-buffer)))
    (selection-first--set-state 'passthrough)
    (unwind-protect
        (progn
          (setq this-command command
                real-this-command command)
          (call-interactively command))
      (selection-first--restore-source-normal-state source))))

(defun selection-first-native-once (command)
  "Choose interactive COMMAND by name, call it once, then restore normal state."
  (interactive (list (read-command "Native command: ")))
  (selection-first--call-native-command command))

(defun selection-first-native-key-once ()
  "Read and execute one complete native key sequence, then restore normal state."
  (interactive)
  (selection-first--prepare-native-handoff)
  (let ((source (current-buffer)))
    (selection-first--set-state 'passthrough)
    (unwind-protect
        (let* ((keys (read-key-sequence "Native key: "))
               (command (key-binding keys)))
          (unless (commandp command)
            (user-error "Native key %s is not bound to a command"
                        (key-description keys)))
          (setq this-command command
                real-this-command command)
          (call-interactively command))
      (selection-first--restore-source-normal-state source))))

(defun selection-first-undefined-key ()
  "Reject an unspecified key in normal state."
  (interactive)
  (user-error "Undefined selection-first normal key; press ? for help"))

(defalias 'selection-first-undefined-printable #'selection-first-undefined-key)

(defconst selection-first--grammar
  '(("d" selection-first-backward-char "Move" "Select previous character")
    ("n" selection-first-forward-char "Move" "Select next character")
    ("t" selection-first-previous-line "Move" "Move to previous logical line")
    ("s" selection-first-next-line "Move" "Move to next logical line")
    ("D" selection-first-backward-char-extend "Extend" "Extend cursor backward")
    ("N" selection-first-forward-char-extend "Extend" "Extend cursor forward")
    ("T" selection-first-previous-line-extend "Extend" "Extend to previous logical line")
    ("S" selection-first-next-line-extend "Extend" "Extend to next logical line")
    ("b" selection-first-backward-word "Move" "Select to previous word boundary")
    ("w" selection-first-forward-word "Move" "Select to next word boundary")
    (";" selection-first-reverse "Selection" "Reverse anchor and cursor")
    ("SPC n" selection-first-gather-same-next "Gather" "Add next equal occurrence")
    ("SPC p" selection-first-gather-same-previous "Gather" "Add previous equal occurrence")
    ("SPC a" selection-first-gather-same-all "Gather" "Gather all equal selections")
    ("SPC k" selection-first-keep-regexp "Refine" "Keep selections matching regexp")
    ("SPC d" selection-first-drop-regexp "Refine" "Drop selections matching regexp")
    ("SPC u" selection-first-selection-undo "History" "Undo selection-only transformation")
    ("SPC U" selection-first-selection-redo "History" "Redo selection-only transformation")
    ("SPC q" selection-first-collapse "Gather" "Collapse to primary selection")
    ("i" selection-first-insert "Insert" "Insert at directed cursor endpoints")
    ("a" selection-first-append "Insert" "Insert at anchor endpoints")
    ("I" selection-first-insert-before-all "Insert" "Insert fixed text before selections")
    ("A" selection-first-insert-after-all "Insert" "Insert fixed text after selections")
    ("." selection-first-repeat "Operate" "Repeat last semantic selection recipe")
    ("p" selection-first-delete "Operate" "Delete selections atomically")
    ("x" selection-first-copy "Operate" "Copy selection vector")
    ("y" selection-first-paste "Operate" "Paste selection vector")
    ("r" selection-first-replace "Operate" "Replace selections with fixed text")
    ("u" selection-first-undo "History" "Undo one whole-buffer text unit")
    ("q" selection-first-collapse "Exit" "Collapse to primary selection")
    ("<escape>" selection-first-collapse "Exit" "Collapse to primary selection")
    ("C-g" selection-first-collapse "Exit" "Collapse to primary selection")
    (":" selection-first-native-key-once "Native" "Native key sequence once")
    ("M-x" selection-first-native-once "Native" "Native command by name once")
    ("?" selection-first-describe-bindings "Help" "Show selection-first bindings"))
  "Canonical normal-state grammar: key, command, category, and description.")

(defvar selection-first--normal-commands nil
  "Commands owned by the selection-first normal grammar.")

(defvar selection-first-normal-map nil
  "Stable DVP-oriented selection-first normal map.")

(defvar selection-first-gather-map nil
  "Selection discovery and refinement prefix map.")

(defvar selection-first--emulation-alist nil
  "Emulation map alist for selection-first normal state.")

(defvar selection-first-batch-insert-map nil
  "Keymap for literal, integration-free plural insertion intents.")

(defvar selection-first--batch-emulation-alist nil
  "Emulation map alist for selection-first batch-insert state.")

(defun selection-first-batch-reject-key ()
  "Reject an unsupported key sequence at the closed batch-insert boundary."
  (interactive)
  (user-error "Unsupported batch-insert key: %s"
              (key-description (this-command-keys-vector))))

(defun selection-first--batch-command-p (command)
  "Return non-nil when COMMAND is supported by batch-insert."
  (memq command '(selection-first-batch-self-insert
                  selection-first-batch-newline
                  selection-first-batch-delete-backward
                  selection-first-batch-delete-forward
                  selection-first-exit-batch-insert)))

(defun selection-first--normal-command-p (command)
  "Return non-nil when COMMAND resolves to frontend-owned normal behavior."
  (or (memq command selection-first--normal-commands)
      (and (symbolp command)
           (condition-case nil
               (let ((resolved (indirect-function command)))
                 (cl-some
                  (lambda (owned)
                    (eq resolved (indirect-function owned)))
                  selection-first--normal-commands))
             (error nil)))))

(defun selection-first--around-command-execute (original command &rest arguments)
  "Call ORIGINAL for COMMAND through the appropriate selection boundary.
ARGUMENTS are the remaining arguments to `command-execute'.  Frontend grammar
commands retain their own atomic boundaries.  Disabled native commands reach
Emacs unchanged.  Other native commands collapse plural state before execution,
or invalidate singleton history afterward if they changed source text."
  (cond
   ((and selection-first-mode (eq selection-first--state 'batch-insert)
         (commandp command)
         (not (selection-first--batch-command-p command)))
    (selection-first-batch-reject-key))
   ((or (not selection-first-mode)
        (not (eq selection-first--state 'normal))
        (not (commandp command))
        (selection-first--normal-command-p command)
        (and (symbolp command) (get command 'disabled)))
    (apply original command arguments))
   ((selection-first--own-session-p)
    (selection-first--prepare-native-handoff)
    (apply original command arguments))
   (t
    (let ((source (current-buffer))
          (tick (buffer-chars-modified-tick)))
      (unwind-protect
          (apply original command arguments)
        (when (buffer-live-p source)
          (with-current-buffer source
            (when (/= tick (buffer-chars-modified-tick))
              (selection-first--clear-selection-history)))))))))

(defun selection-first--make-normal-map ()
  "Build the normal map from `selection-first--grammar'."
  (let ((map (make-sparse-keymap))
        (prefixes (make-hash-table :test #'equal)))
    (dolist (entry selection-first--grammar)
      (let* ((key (car entry))
             (command (cadr entry))
             (parts (split-string key " ")))
        (if (= 1 (length parts))
            (define-key map (kbd key) command)
          (let* ((prefix (car parts))
                 (suffix (mapconcat #'identity (cdr parts) " "))
                 (prefix-map (or (gethash prefix prefixes)
                                 (let ((new-map (make-sparse-keymap)))
                                   (puthash prefix new-map prefixes)
                                   (define-key map (kbd prefix) new-map)
                                   new-map))))
            (define-key prefix-map (kbd suffix) command)))))
    (define-key map [remap self-insert-command]
                #'selection-first-undefined-key)
    map))

(defun selection-first--initialize-grammar-state ()
  "Rebuild every runtime artifact derived from the canonical grammar."
  (setq selection-first--normal-commands
        (delete-dups
         (append (mapcar #'cadr selection-first--grammar)
                 '(selection-first-undefined-key)))
        selection-first-normal-map (selection-first--make-normal-map)
        selection-first-gather-map
        (lookup-key selection-first-normal-map (kbd "SPC"))
        selection-first--emulation-alist
        `((selection-first--normal-active . ,selection-first-normal-map))
        selection-first-batch-insert-map
        (let ((map (make-sparse-keymap)))
          (define-key map [remap self-insert-command]
                      #'selection-first-batch-self-insert)
          (define-key map (kbd "RET") #'selection-first-batch-newline)
          (define-key map (kbd "C-m") #'selection-first-batch-newline)
          (define-key map (kbd "DEL") #'selection-first-batch-delete-backward)
          (define-key map (kbd "<backspace>") #'selection-first-batch-delete-backward)
          (define-key map (kbd "C-d") #'selection-first-batch-delete-forward)
          (define-key map (kbd "<delete>") #'selection-first-batch-delete-forward)
          (define-key map (kbd "<escape>") #'selection-first-exit-batch-insert)
          (define-key map (kbd "C-g") #'selection-first-exit-batch-insert)
          map)
        selection-first--batch-emulation-alist
        `((selection-first--batch-insert-active .
           ,selection-first-batch-insert-map))))

(selection-first--initialize-grammar-state)

(defun selection-first--print-help ()
  "Print the canonical grammar to `standard-output'."
  (princ "Selection-first normal bindings\n\n")
  (dolist (entry selection-first--grammar)
    (pcase-let ((`(,key ,_command ,category ,description) entry))
      (princ (format "%-10s %-11s %s\n" key category description)))))

(defun selection-first-describe-bindings ()
  "Display the canonical selection-first normal grammar."
  (interactive)
  (with-help-window "*Selection First Help*"
    (selection-first--print-help)))

(defun selection-first--lighter ()
  "Return a mode-line indicator for current frontend state and cardinality."
  (pcase selection-first--state
    ('insert " Sel I")
    ('batch-insert (format " Sel BI:%d" (selection-batch-count)))
    ('passthrough " Sel Native")
    ('normal (format " Sel N:%d"
                     (if (selection-first--own-session-p)
                         (selection-batch-count)
                       1)))
    (_ " Sel")))

(defvar-keymap selection-first-mode-map
  :doc "Keys active outside selection-first normal state."
  "<escape>" #'selection-first-exit-insert)

(unless (memq 'selection-first--emulation-alist emulation-mode-map-alists)
  (add-to-list 'emulation-mode-map-alists 'selection-first--emulation-alist))
(unless (memq 'selection-first--batch-emulation-alist emulation-mode-map-alists)
  (add-to-list 'emulation-mode-map-alists
               'selection-first--batch-emulation-alist))

(unless (advice-member-p #'selection-first--around-command-execute
                         #'command-execute)
  (advice-add 'command-execute :around
              #'selection-first--around-command-execute))

(define-minor-mode selection-first-mode
  "Toggle the Meow-independent selection-first frontend."
  :init-value nil
  :lighter (:eval (selection-first--lighter))
  :keymap selection-first-mode-map
  (setq selection-first--vertical-run nil)
  (selection-first--clear-selection-history)
  (if selection-first-mode
      (progn
        (when (or buffer-read-only (derived-mode-p 'special-mode))
          (setq selection-first-mode nil)
          (user-error "Selection-first mode is unavailable in this buffer"))
        (selection-first--set-state 'normal))
    (when (selection-first--own-session-p)
      (selection-batch-collapse))
    (selection-first--set-state nil)))

(defun selection-first--turn-on ()
  "Enable `selection-first-mode' in an eligible buffer."
  (when (selection-first--eligible-buffer-p)
    (selection-first-mode 1)))

(define-globalized-minor-mode selection-first-global-mode
  selection-first-mode selection-first--turn-on
  :group 'selection-first)

(provide 'selection-first)
;;; selection-first.el ends here
