;;; selection-batch.el --- Batch editing over explicit selections -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later
;; Package-Requires: ((emacs "31.0"))

;;; Commentary:
;; Public facade for a short-lived ordered selection transaction.

;;; Code:

(require 'selection-batch-core)
(require 'selection-batch-plan)
(require 'selection-batch-org)
(require 'selection-batch-ui)
(require 'selection-batch-operators)

(defun selection-batch-export-ranges ()
  "Export the live single-buffer selection set as integer-only plists.
The returned list is in logical order and retains direction and stable IDs.  It
contains no markers, overlays, or backend objects."
  (let* ((snapshot (selection-batch-current-snapshot))
         (buffer (selection-batch-snapshot-buffer snapshot)))
    (mapcar
     (lambda (selection)
       (list :buffer buffer
             :id (selection-batch-snapshot-selection-id selection)
             :anchor (selection-batch-selection-anchor selection)
             :cursor (selection-batch-selection-cursor selection)
             :beginning (selection-batch-selection-beginning selection)
             :end (selection-batch-selection-end selection)
             :forward (selection-batch-selection-forward-p selection)
             :primary (equal (selection-batch-snapshot-selection-id selection)
                             (selection-batch-snapshot-primary-id snapshot))))
     (append (selection-batch-snapshot-selections snapshot) nil))))

(defun selection-batch-collapse-and-call (command)
  "Collapse to the primary region, then invoke interactive COMMAND exactly once.
This is an explicit ownership handoff, not command replay.  The selection set is
exportable with `selection-batch-export-ranges' before this call, but COMMAND
receives only standard point/mark state."
  (interactive (list (read-command "Collapse and call command: ")))
  (unless (commandp command)
    (signal 'wrong-type-argument (list 'commandp command)))
  (selection-batch-collapse)
  (call-interactively command))

(provide 'selection-batch)
;;; selection-batch.el ends here
