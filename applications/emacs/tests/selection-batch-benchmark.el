;;; selection-batch-benchmark.el --- Deterministic package benchmarks -*- lexical-binding: t; -*-

;;; Commentary:
;; Explicit, opt-in benchmark for the real selection-batch package.  Package
;; loading and process startup happen before `selection-batch-benchmark-run', so
;; neither is included in a sample.  Each operation gets a fresh fundamental-mode
;; buffer and deterministic disjoint ASCII selections.

;;; Code:

(require 'benchmark)
(require 'cl-lib)
(require 'json)
(require 'selection-batch)

(defconst selection-batch-benchmark-counts '(10 100 1000))
(defconst selection-batch-benchmark-warmups 2)
(defconst selection-batch-benchmark-iterations 5)
(defconst selection-batch-benchmark-insertion "<>")

(defun selection-batch-benchmark--assert (condition format-string &rest args)
  "Signal an error unless CONDITION holds, formatting ARGS with FORMAT-STRING."
  (unless condition
    (apply #'error (concat "selection-batch benchmark assertion: " format-string)
           args)))

(defun selection-batch-benchmark--text (count &optional inserted)
  "Return fixture text for COUNT records, optionally with INSERTED prefix."
  (apply #'concat
         (make-list count (concat (or inserted "") "x\n"))))

(defun selection-batch-benchmark--snapshot (buffer count)
  "Build an immutable snapshot in BUFFER for COUNT disjoint `x' selections."
  (let ((selections
         (vconcat
          (cl-loop for index below count
                   for beginning = (1+ (* index 2))
                   collect
                   (selection-batch-snapshot-selection-create
                    :id index :anchor beginning :cursor (1+ beginning))))))
    (selection-batch-snapshot-create
     :buffer buffer
     :buffer-tick (with-current-buffer buffer (buffer-chars-modified-tick))
     :generation 0 :primary-id 0
     :narrowing (with-current-buffer buffer (cons (point-min) (point-max)))
     :selections selections)))

(defun selection-batch-benchmark--prepare (count)
  "Return a fresh (BUFFER SNAPSHOT) fixture for COUNT selections."
  (let ((buffer (generate-new-buffer " *selection-batch-benchmark*")))
    (with-current-buffer buffer
      (fundamental-mode)
      (buffer-enable-undo)
      (insert (selection-batch-benchmark--text count))
      (goto-char (point-min)))
    (list buffer (selection-batch-benchmark--snapshot buffer count))))

(defun selection-batch-benchmark--artifacts (session)
  "Capture SESSION markers and overlays so cleanup can be checked by identity."
  (list
   (cl-loop for selection across (selection-batch--session-selections session)
            append (delq nil
                         (list
                          (selection-batch--live-selection-anchor-marker selection)
                          (selection-batch--live-selection-cursor-marker selection))))
   (copy-sequence (selection-batch--session-overlays session))))

(defun selection-batch-benchmark--cleanup-and-assert (buffer artifacts)
  "Clean BUFFER's session and assert that captured ARTIFACTS do not leak."
  (when selection-batch--session
    (with-current-buffer (selection-batch--session-buffer selection-batch--session)
      (selection-batch-cancel)))
  (let ((markers (car artifacts))
        (overlays (cadr artifacts)))
    (selection-batch-benchmark--assert
     (null selection-batch--session) "global session survived cleanup")
    (dolist (marker markers)
      (selection-batch-benchmark--assert
       (null (marker-buffer marker)) "live marker survived cleanup"))
    (dolist (overlay overlays)
      (selection-batch-benchmark--assert
       (null (overlay-buffer overlay)) "live overlay survived cleanup"))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (selection-batch-benchmark--assert
         (null (cl-remove-if-not
                (lambda (overlay) (overlay-get overlay 'selection-batch-view))
                (overlays-in (point-min) (point-max))))
         "tagged overlay survived cleanup")
        (dolist (hook '(kill-buffer-hook before-revert-hook change-major-mode-hook))
          (selection-batch-benchmark--assert
           (not (memq #'selection-batch--lifecycle-exit (symbol-value hook)))
           "%S survived cleanup" hook))))
    (when (buffer-live-p buffer) (kill-buffer buffer))))

(defun selection-batch-benchmark--one (operation count)
  "Run and validate one timed OPERATION fixture at selection COUNT.
Return the `(elapsed-seconds gc-count gc-seconds)' from `benchmark-call'."
  (selection-batch-benchmark--assert
   (null selection-batch--session) "fixture started with a live session")
  (pcase-let* ((`(,buffer ,snapshot) (selection-batch-benchmark--prepare count))
               (artifacts nil)
               (sample nil))
    (unwind-protect
        (with-current-buffer buffer
          (pcase operation
            ('session-install
             (setq sample
                   (benchmark-call
                    (lambda () (selection-batch-install-snapshot snapshot)) 1))
             (selection-batch-benchmark--assert
              (= count (selection-batch-count)) "install count is not %d" count)
             (selection-batch-benchmark--assert
              (equal (buffer-string) (selection-batch-benchmark--text count))
              "install changed fixture text")
             (selection-batch-benchmark--assert
              (= (1- count)
                 (length (selection-batch--session-overlays selection-batch--session)))
              "install overlay count is not %d" (1- count)))
            ('overlay-refresh
             (selection-batch-install-snapshot snapshot)
             (let ((old (copy-sequence
                         (selection-batch--session-overlays selection-batch--session))))
               (setq sample
                     (benchmark-call
                      (lambda ()
                        (selection-batch--view-refresh selection-batch--session)) 1))
               (dolist (overlay old)
                 (selection-batch-benchmark--assert
                  (null (overlay-buffer overlay)) "refresh retained an old overlay")))
             (selection-batch-benchmark--assert
              (= (1- count)
                 (length (selection-batch--session-overlays selection-batch--session)))
              "refresh overlay count is not %d" (1- count))
             (selection-batch-benchmark--assert
              (= count (selection-batch-count)) "refresh count is not %d" count)
             (selection-batch-benchmark--assert
              (equal (buffer-string) (selection-batch-benchmark--text count))
              "refresh changed fixture text"))
            ('insertion-plan-apply
             (selection-batch-install-snapshot snapshot)
             (setq sample
                   (benchmark-call
                    (lambda ()
                      (selection-batch-apply-plan
                       (selection-batch--plan-insert
                        (selection-batch-current-snapshot)
                        selection-batch-benchmark-insertion nil)))
                    1))
             (let ((expected
                    (selection-batch-benchmark--text
                     count selection-batch-benchmark-insertion)))
               (selection-batch-benchmark--assert
                (equal (buffer-string) expected) "insertion text mismatch")
               (selection-batch-benchmark--assert
                (equal (secure-hash 'sha256 (buffer-string))
                       (secure-hash 'sha256 expected))
                "insertion checksum mismatch"))
             (selection-batch-benchmark--assert
              (= count (selection-batch-count)) "insertion count is not %d" count)
             (selection-batch-benchmark--assert
              (= 1 (selection-batch-snapshot-generation
                    (selection-batch-current-snapshot)))
              "insertion generation is not one")))
          (setq artifacts
                (selection-batch-benchmark--artifacts selection-batch--session)))
      (selection-batch-benchmark--cleanup-and-assert buffer artifacts))
    sample))

(defun selection-batch-benchmark--median (numbers)
  "Return the median of odd-length list NUMBERS."
  (nth (/ (length numbers) 2) (sort (copy-sequence numbers) #'<)))

(defun selection-batch-benchmark--measure (operation count)
  "Warm up and measure OPERATION for COUNT, returning an alist result."
  (dotimes (_ selection-batch-benchmark-warmups)
    (selection-batch-benchmark--one operation count))
  (let ((samples
         (cl-loop repeat selection-batch-benchmark-iterations
                  collect (selection-batch-benchmark--one operation count))))
    `((operation . ,(symbol-name operation))
      (count . ,count)
      (iterations . ,selection-batch-benchmark-iterations)
      (warmups . ,selection-batch-benchmark-warmups)
      (median_ms . ,(* 1000.0
                       (selection-batch-benchmark--median
                        (mapcar #'car samples))))
      (samples_ms . ,(vconcat (mapcar (lambda (sample) (* 1000.0 (car sample)))
                                      samples)))
      (gc_counts . ,(vconcat (mapcar #'cadr samples)))
      (gc_seconds . ,(vconcat (mapcar #'caddr samples))))))

(defun selection-batch-benchmark--field (key result)
  "Return KEY from alist RESULT."
  (alist-get key result))

(defun selection-batch-benchmark-run ()
  "Run the opt-in benchmark matrix, print JSON and human summaries, then gate."
  (interactive)
  (when selection-batch--session
    (selection-batch--cleanup selection-batch--session nil t))
  (garbage-collect)
  (let (results)
    (dolist (count selection-batch-benchmark-counts)
      (dolist (operation '(session-install overlay-refresh insertion-plan-apply))
        (let ((result (selection-batch-benchmark--measure operation count)))
          (push result results)
          (princ
           (format "BENCH selection-batch count=%d operation=%s median_ms=%.3f samples_ms=%S gc_counts=%S\n"
                   count (selection-batch-benchmark--field 'operation result)
                   (selection-batch-benchmark--field 'median_ms result)
                   (append (selection-batch-benchmark--field 'samples_ms result) nil)
                   (append (selection-batch-benchmark--field 'gc_counts result) nil))))))
    (setq results (nreverse results))
    (let ((document
           `((schema . "selection-batch-benchmark-v1")
             (emacs_version . ,emacs-version)
             (system_configuration . ,system-configuration)
             (results . ,(vconcat results)))))
      (princ (concat "SELECTION_BATCH_BENCHMARK_JSON "
                     (json-encode document) "\n")))
    (let* ((at-100 (cl-remove-if-not
                    (lambda (result) (= 100 (alist-get 'count result))) results))
           (insert (cl-find "insertion-plan-apply" at-100
                            :key (lambda (result) (alist-get 'operation result))
                            :test #'equal))
           (refresh (cl-find "overlay-refresh" at-100
                             :key (lambda (result) (alist-get 'operation result))
                             :test #'equal)))
      (selection-batch-benchmark--assert
       (< (alist-get 'median_ms insert) 200.0)
       "100-selection insertion median %.3fms is not below 200ms"
       (alist-get 'median_ms insert))
      (selection-batch-benchmark--assert
       (< (alist-get 'median_ms refresh) 100.0)
       "100-selection overlay median %.3fms is not below 100ms"
       (alist-get 'median_ms refresh)))
    (selection-batch-benchmark--assert
     (null selection-batch--session) "benchmark ended with a live session")
    (princ "BENCH selection-batch status=PASS gates=insertion-100<200ms,overlay-100<100ms leaks=none\n")
    results))

(provide 'selection-batch-benchmark)
;;; selection-batch-benchmark.el ends here
