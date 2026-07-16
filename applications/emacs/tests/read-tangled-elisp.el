;;; read-tangled-elisp.el --- Read tangled Lisp without evaluating it -*- lexical-binding: t; -*-

;;; Commentary:
;; Batch syntax reader for one tangled Emacs Lisp file.

;;; Code:

(let ((path (pop command-line-args-left)))
  (unless (and path (null command-line-args-left))
    (error "usage: emacs --batch --quick -l read-tangled-elisp.el FILE"))
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (let ((form-count 0)
          done)
      (condition-case condition
          (while (not done)
            (condition-case nil
                (progn
                  (read (current-buffer))
                  (setq form-count (1+ form-count)))
              (end-of-file
               (let ((state (syntax-ppss (point-max))))
                 (if (or (> (car state) 0) (nth 3 state))
                     (error "premature malformed input in %s" path)
                   (setq done t))))))
        ((invalid-read-syntax error)
         (message "failed reading %s after %d forms: %S"
                  path form-count condition)
         (kill-emacs 1)))
      (message "read %d forms from %s" form-count path))))

;;; read-tangled-elisp.el ends here
