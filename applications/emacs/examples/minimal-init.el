;;; minimal-init.el --- Minimal selection-first example -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "../elisp/packages"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name))))

(require 'selection-first)
(selection-first-global-mode 1)

;;; minimal-init.el ends here
