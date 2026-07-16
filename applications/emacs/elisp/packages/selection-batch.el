;;; selection-batch.el --- Batch editing over explicit selections -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "31.0"))

;;; Commentary:
;; Public facade for a short-lived ordered selection transaction.

;;; Code:

(require 'selection-batch-core)
(require 'selection-batch-plan)
(require 'selection-batch-ui)
(require 'selection-batch-operators)

(provide 'selection-batch)
;;; selection-batch.el ends here
