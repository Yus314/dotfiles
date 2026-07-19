;;; selection-batch-org.el --- Safe Org indentation adapter -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Yus314
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Org indentation refreshes derived `line-prefix' and `wrap-prefix' text
;; properties from `after-change-functions' under `with-silent-modifications'.
;; The selection-batch change ledger rejects generic silent property mutation.
;; This adapter grants only the unadvised Org refresh function captured at
;; installation a guarded boundary and registers a full derived-property
;; recomputation after rollback.

;;; Code:

(require 'selection-batch-plan)

(defvar org-indent-mode)
(declare-function org-indent-refresh-maybe "org-indent" (beg end dummy))

(defvar selection-batch-org--raw-refresh-function nil
  "Unadvised `org-indent-refresh-maybe' captured by the adapter.")

(defvar selection-batch-org--adapter nil
  "Registered capability for the exact Org indentation refresher.")

(defvar selection-batch-org--disabled-reason nil
  "Non-nil explanation when the adapter could not install safely.")

(defun selection-batch-org--ledger-active-p ()
  "Return non-nil during the ordinary after-change-hook ledger phase."
  (and selection-batch--change-ledger
       (eq (plist-get selection-batch--change-ledger :phase) 'after-hooks)))

(defun selection-batch-org--rollback-refresh ()
  "Recompute Org's derived indentation properties after text rollback."
  (when (and selection-batch-org--raw-refresh-function
             (derived-mode-p 'org-mode)
             (bound-and-true-p org-indent-mode))
    (save-restriction
      (widen)
      (funcall selection-batch-org--raw-refresh-function
               (point-min) (point-max) 0))))

(defun selection-batch-org--refresh-around (function &rest arguments)
  "Guard trusted Org indentation FUNCTION called with ARGUMENTS."
  (when (and (selection-batch-org--ledger-active-p)
             (not (eq function selection-batch-org--raw-refresh-function)))
    (error "Org indentation advice chain changed inside trusted boundary"))
  (selection-batch--call-trusted-property-refresh
   selection-batch-org--adapter function arguments))

(defun selection-batch-org--existing-advice-functions ()
  "Return advice functions already attached to Org's indentation refresh."
  (let (result)
    (advice-mapc (lambda (function _properties) (push function result))
                 'org-indent-refresh-maybe)
    result))

(defun selection-batch-org--validate (adapter)
  "Validate ADAPTER and Org's complete advice chain before mutation."
  (when (and (derived-mode-p 'org-mode)
             (bound-and-true-p org-indent-mode))
    (unless (and (eq adapter selection-batch-org--adapter)
                 (memq adapter selection-batch--property-adapters)
                 (eq selection-batch-org--raw-refresh-function
                     (selection-batch--property-adapter-function adapter))
                 (equal (selection-batch-org--existing-advice-functions)
                        '(selection-batch-org--refresh-around)))
      (error "Org indentation adapter advice chain is not exclusive"))))

(defun selection-batch-org--after-load (&rest _)
  "Install the adapter when `org-indent' finishes loading."
  (when (featurep 'org-indent)
    (selection-batch-org--install)))

(defun selection-batch-org--install ()
  "Install the narrow Org indentation compatibility advice once."
  (unless (and (advice-member-p #'selection-batch-org--refresh-around
                                'org-indent-refresh-maybe)
               selection-batch-org--adapter
               (memq selection-batch-org--adapter
                     selection-batch--property-adapters))
    (selection-batch--ensure-property-adapters-mutable)
    (let ((old-hook (copy-sequence after-load-functions))
          (old-registry (copy-sequence selection-batch--property-adapters))
          (old-definition (symbol-function 'org-indent-refresh-maybe))
          (old-adapter selection-batch-org--adapter)
          (old-raw selection-batch-org--raw-refresh-function)
          (old-reason selection-batch-org--disabled-reason)
          completed)
      (unwind-protect
          (let ((existing (selection-batch-org--existing-advice-functions)))
            (if existing
                (progn
                  (setq selection-batch-org--disabled-reason
                        (format "pre-existing advice: %S" existing))
                  (remove-hook 'after-load-functions
                               #'selection-batch-org--after-load)
                  (display-warning
                   'selection-batch-org
                   (concat "Org transactional insertion adapter disabled: "
                           selection-batch-org--disabled-reason)
                   :warning))
              (setq selection-batch-org--raw-refresh-function
                    (symbol-function 'org-indent-refresh-maybe)
                    selection-batch-org--disabled-reason nil)
              (setq selection-batch-org--adapter
                    (selection-batch--register-property-adapter
                     selection-batch-org--raw-refresh-function
                     #'selection-batch-org--rollback-refresh
                     #'selection-batch-org--validate))
              (advice-add 'org-indent-refresh-maybe :around
                          #'selection-batch-org--refresh-around)
              (remove-hook 'after-load-functions
                           #'selection-batch-org--after-load))
            (setq completed t))
        (unless completed
          ;; Restore exact captured state for error, quit, or `throw'.
          (setq after-load-functions old-hook
                selection-batch--property-adapters old-registry
                selection-batch-org--adapter old-adapter
                selection-batch-org--raw-refresh-function old-raw
                selection-batch-org--disabled-reason old-reason)
          (fset 'org-indent-refresh-maybe old-definition))))))

(defun selection-batch-org-unload-function ()
  "Remove Org compatibility advice before unloading this feature."
  (selection-batch--ensure-property-adapters-mutable)
  (let ((old-hook (copy-sequence after-load-functions))
        (old-registry (copy-sequence selection-batch--property-adapters))
        (old-definition (symbol-function 'org-indent-refresh-maybe))
        (old-adapter selection-batch-org--adapter)
        (old-raw selection-batch-org--raw-refresh-function)
        (old-reason selection-batch-org--disabled-reason)
        completed)
    (unwind-protect
        (progn
          (remove-hook 'after-load-functions #'selection-batch-org--after-load)
          (when (advice-member-p #'selection-batch-org--refresh-around
                                 'org-indent-refresh-maybe)
            (advice-remove 'org-indent-refresh-maybe
                           #'selection-batch-org--refresh-around))
          (when selection-batch-org--adapter
            (selection-batch--unregister-property-adapter
             selection-batch-org--adapter))
          (setq selection-batch-org--raw-refresh-function nil
                selection-batch-org--adapter nil
                selection-batch-org--disabled-reason nil)
          (setq completed t)
          nil)
      (unless completed
        (setq after-load-functions old-hook
              selection-batch--property-adapters old-registry
              selection-batch-org--adapter old-adapter
              selection-batch-org--raw-refresh-function old-raw
              selection-batch-org--disabled-reason old-reason)
        (fset 'org-indent-refresh-maybe old-definition)))))

(if (featurep 'org-indent)
    (selection-batch-org--install)
  (add-hook 'after-load-functions #'selection-batch-org--after-load))

(provide 'selection-batch-org)
;;; selection-batch-org.el ends here
