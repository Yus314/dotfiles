;;; selection-batch-load-test.el --- Selection batch load test -*- lexical-binding: t; -*-

(require 'ert)

(ert-deftest selection-batch-loads ()
  (should (require 'selection-batch nil t))
  (should (featurep 'selection-batch)))

;;; selection-batch-load-test.el ends here
