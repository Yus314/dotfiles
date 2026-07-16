;;; selection-batch-transient-spike.el --- Transient-map probe -*- lexical-binding: t; -*-

;;; Commentary:
;; Minimal Emacs 31 probe.  It intentionally does not require or call any
;; selection-batch production function and installs no global binding.
;; Run the ERT probes in batch, then evaluate
;; `selection-batch-spike-prompt' interactively for the minibuffer observation.

;;; Code:

(require 'ert)

(defvar selection-batch-spike-events nil)
(defvar selection-batch-spike-fake-session nil)
(defvar selection-batch-spike-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "x") #'selection-batch-spike-supported)
    map))

(defun selection-batch-spike-supported ()
  "Record one supported transient command."
  (interactive)
  (push 'supported selection-batch-spike-events))

(defun selection-batch-spike--install ()
  "Install the probe map and return its exit function."
  (set-transient-map
   selection-batch-spike-map t
   (lambda ()
     (push (cond
            ((plist-get selection-batch-spike-fake-session :suspending)
             'exit-while-suspending)
            (overriding-terminal-local-map 'exit-map-still-active)
            (t 'exit-after-deactivate))
           selection-batch-spike-events))))

(ert-deftest selection-batch-spike-explicit-exit-order ()
  (let ((selection-batch-spike-events nil)
        (selection-batch-spike-fake-session '(:suspending nil)))
    (let ((exit (selection-batch-spike--install)))
      (push (if overriding-terminal-local-map 'active 'inactive)
            selection-batch-spike-events)
      (funcall exit)
      (push (if overriding-terminal-local-map 'active-after 'inactive-after)
            selection-batch-spike-events))
    (should (equal '(active exit-after-deactivate inactive-after)
                   (nreverse selection-batch-spike-events)))))

(ert-deftest selection-batch-spike-suspend-and-resume ()
  (let ((selection-batch-spike-events nil)
        (selection-batch-spike-fake-session '(:suspending t)))
    (funcall (selection-batch-spike--install))
    (should-not overriding-terminal-local-map)
    (setf (plist-get selection-batch-spike-fake-session :suspending) nil)
    (let ((resume-exit (selection-batch-spike--install)))
      (should (eq (key-binding (kbd "x"))
                  #'selection-batch-spike-supported))
      (funcall resume-exit))
    (should (equal '(exit-while-suspending exit-after-deactivate)
                   (nreverse selection-batch-spike-events)))))

(defun selection-batch-spike-prompt ()
  "Interactively demonstrate suspension around one `read-string'.
The Messages buffer records whether the transient map leaked into the
minibuffer and the exact callback order.  Press C-g to probe quit ordering."
  (interactive)
  (let ((selection-batch-spike-events nil)
        (selection-batch-spike-fake-session '(:suspending t)))
    (funcall (selection-batch-spike--install))
    (unwind-protect
        (progn
          (push (if overriding-terminal-local-map 'leaked 'suspended)
                selection-batch-spike-events)
          (read-string "Spike (C-g or RET): "))
      (setf (plist-get selection-batch-spike-fake-session :suspending) nil)
      (selection-batch-spike--install)
      (message "selection-batch spike: %S"
               (nreverse selection-batch-spike-events)))))

(provide 'selection-batch-transient-spike)
;;; selection-batch-transient-spike.el ends here
