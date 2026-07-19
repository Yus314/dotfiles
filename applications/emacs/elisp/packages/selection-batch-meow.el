;;; selection-batch-meow.el --- Optional Meow frontend -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; One opt-in `g' prefix exposes the same grammar as the short-lived transaction
;; map.  Loading this library neither enables Meow nor starts a batch session.

;;; Code:

(require 'selection-batch)

(defvar meow-normal-state-keymap
  "Meow normal-state keymap, declared here to keep the frontend optional.")

(defcustom selection-batch-enable-meow-bindings nil
  "When non-nil, install the selection-batch grammar under Meow normal-state `g'.
The default is nil so loading the package cannot take over an existing key."
  :type 'boolean
  :group 'selection-batch)

(defconst selection-batch-meow-prefix-key "g"
  "Verified free prefix in the active Meow normal-state configuration.
`G' remains bound to `meow-grab'; only lowercase `g' was unbound.")

(defconst selection-batch-meow-bindings
  '(("n" . selection-batch-gather-same-next)
    ("p" . selection-batch-gather-same-previous)
    ("a" . selection-batch-gather-same-all)
    ("r" . selection-batch-gather-regexp)
    ("l" . selection-batch-split-lines)
    ("k" . selection-batch-keep)
    ("d" . selection-batch-drop)
    ("m" . selection-batch-merge)
    ("]" . selection-batch-rotate-primary-next)
    ("[" . selection-batch-rotate-primary-previous)
    ("u" . selection-batch-selection-undo)
    ("U" . selection-batch-selection-redo)
    ("y" . selection-batch-copy)
    ("x" . selection-batch-delete)
    ("c" . selection-batch-replace)
    ("+" . selection-batch-uppercase)
    ("-" . selection-batch-lowercase)
    ("~" . selection-batch-capitalize)
    ("b" . selection-batch-insert-before)
    ("i" . selection-batch-insert-after)
    ("P" . selection-batch-paste)
    ("." . selection-batch-repeat)
    ("q" . selection-batch-collapse)
    ("C-g" . selection-batch-cancel))
  "Shared select/gather/refine/operate grammar.")

(defvar selection-batch-meow-prefix-map
  (let ((map (make-sparse-keymap)))
    (dolist (binding selection-batch-meow-bindings)
      (define-key map (kbd (car binding)) (cdr binding)))
    map)
  "Prefix map installed in Meow normal state when explicitly enabled.")

;; A promoted session uses exactly the same keys without repeating the prefix.
(dolist (binding selection-batch-meow-bindings)
  (define-key selection-batch--transaction-map
              (kbd (car binding)) (cdr binding))
  (selection-batch-register-transaction-command (cdr binding)))

(defun selection-batch-meow-initialize ()
  "Install the optional Meow prefix, refusing to overwrite a conflict."
  (interactive)
  (when selection-batch-enable-meow-bindings
    (unless (boundp 'meow-normal-state-keymap)
      (user-error "Meow normal-state keymap is not available"))
    (let ((existing (lookup-key meow-normal-state-keymap
                                (kbd selection-batch-meow-prefix-key))))
      (unless (or (null existing)
                  (eq existing selection-batch-meow-prefix-map))
        (user-error "Meow key %s is already bound to %S"
                    selection-batch-meow-prefix-key existing))
      (define-key meow-normal-state-keymap
                  (kbd selection-batch-meow-prefix-key)
                  selection-batch-meow-prefix-map)))
  selection-batch-enable-meow-bindings)

(provide 'selection-batch-meow)
;;; selection-batch-meow.el ends here
