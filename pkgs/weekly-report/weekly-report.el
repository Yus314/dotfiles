;;; weekly-report.el --- Generate weekly report in Markdown -*- lexical-binding: t -*-

;;; Commentary:
;; Emacs batch script to generate a weekly report from org-mode files.
;; Reads DONE tasks from inbox.org, inbox.org_archive, and legacy archive .org files,
;; generates clocktable, agenda, and TODO lists, then outputs a Markdown file.
;;
;; Usage:
;;   emacs --batch -l weekly-report.el --eval "(weekly-report-generate)" -- [--date YYYY-MM-DD]

;;; Code:

(require 'org)
(require 'org-clock)
(require 'org-agenda)
(require 'org-habit)
(require 'time-date)

;;;; Configuration

(defvar weekly-report-org-dir "~/org")
(defvar weekly-report-archive-dir "~/org-knowledge/archive")
(defvar weekly-report-agenda-files
  '("~/org/inbox/inbox.org"
    "~/org/habit.org"
    "~/org/kana.org"
    "~/org/calendar.org"))
(defvar weekly-report-wstart 0) ; Sunday

;; Must match user's org-todo-keywords (not loaded from user init in batch mode)
(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "SOMEDAY(s)" "PROJECT(p)" "|" "DONE(d)" "CANCEL(c)")))

;; Batch mode settings
(when noninteractive
  (setq org-agenda-inhibit-startup t)
  (setq org-element-cache-persistent nil)
  ;; Hide habit entries from agenda (they repeat every week, not useful in reports)
  (setq org-habit-show-habits nil)
  ;; Ensure Japanese clocktable translations are available
  (setq org-clock-clocktable-language-setup
        '(("en" "File" "L" "Timestamp" "Headline" "Time" "ALL" "Total time" "File time" "Clock summary at")
          ("ja" "ファイル" "L" "タイムスタンプ" "見出し" "時間" "全て" "合計時間" "ファイル時間" "作成日時"))))

;;;; Command line argument parsing

(defun weekly-report--parse-args ()
  "Parse --date argument from command line.
Returns YYYY-MM-DD string or nil."
  (let ((args command-line-args-left)
        (date nil))
    (while args
      (cond
       ((string= (car args) "--date")
        (setq args (cdr args))
        (when args (setq date (car args))))
       ((string= (car args) "--") nil))
      (setq args (cdr args)))
    (setq command-line-args-left nil)
    date))

;;;; Date utilities

(defun weekly-report--parse-date (date-string)
  "Parse YYYY-MM-DD DATE-STRING to a time value."
  (when (string-match "\\`\\([0-9]+\\)-\\([0-9]+\\)-\\([0-9]+\\)\\'" date-string)
    (encode-time 0 0 0
                 (string-to-number (match-string 3 date-string))
                 (string-to-number (match-string 2 date-string))
                 (string-to-number (match-string 1 date-string)))))

(defun weekly-report--date-range (&optional date-string)
  "Calculate Sunday-to-Saturday week range containing DATE-STRING or today.
Returns plist with :start :end :start-mmdd :end-mmdd :year :start-time :end-time :next-start."
  (let* ((date (weekly-report--parse-date
                (or date-string
                    (format-time-string "%Y-%m-%d"))))
         (dow (string-to-number (format-time-string "%w" date)))
         (days-since-start (mod (- dow weekly-report-wstart) 7))
         (start (time-subtract date (days-to-time days-since-start)))
         (end (time-add start (days-to-time 6)))
         (next-start (time-add start (days-to-time 7))))
    (list :start (format-time-string "%Y-%m-%d" start)
          :end (format-time-string "%Y-%m-%d" end)
          :start-mmdd (format-time-string "%m%d" start)
          :end-mmdd (format-time-string "%m%d" end)
          :year (format-time-string "%Y" start)
          :start-time start
          :end-time end
          :next-start (format-time-string "%Y-%m-%d" next-start))))

;;;; Org text / table conversion

(defun weekly-report--org-text-to-markdown (text)
  "Convert simple org markup in TEXT to Markdown."
  (with-temp-buffer
    (insert text)
    ;; [[url][text]] -> [text](url)
    (goto-char (point-min))
    (while (re-search-forward "\\[\\[\\([^]]+\\)\\]\\[\\([^]]+\\)\\]\\]" nil t)
      (replace-match "[\\2](\\1)"))
    ;; [[url]] -> <url>
    (goto-char (point-min))
    (while (re-search-forward "\\[\\[\\([^]]+\\)\\]\\]" nil t)
      (replace-match "<\\1>"))
    ;; /italic/ -> *italic*
    (goto-char (point-min))
    (while (re-search-forward "\\b/\\([^/\n]+\\)/\\b" nil t)
      (replace-match "*\\1*"))
    ;; org *bold* -> markdown **bold**
    (goto-char (point-min))
    (while (re-search-forward "\\b\\*\\([^*\n]+\\)\\*\\b" nil t)
      (replace-match "**\\1**"))
    (buffer-string)))

(defun weekly-report--org-table-to-markdown (table-string)
  "Convert org TABLE-STRING to Markdown table format.
Removes #+BEGIN/#+END/#+CAPTION lines, converts separators.
Keeps only the first separator line, removes 0:00 file summary rows,
cleans up org indentation markers, and merges extra time columns."
  (let ((lines (split-string table-string "\n" t "[ \t]+"))
        (first-sep t))
    (let ((result
           (delq nil
                 (mapcar
                  (lambda (line)
                    (cond
                     ;; Skip #+lines
                     ((string-match-p "^#\\+" line) nil)
                     ;; Separator: keep only the first one (after header)
                     ((string-match-p "^|[-+]+|$" line)
                      (when first-sep
                        (setq first-sep nil)
                        (replace-regexp-in-string "\\+" "|" line)))
                     ;; Data lines
                     ((string-match-p "^|" line)
                      (let ((converted line))
                        ;; *bold* -> **bold**
                        (setq converted (replace-regexp-in-string
                                         "\\*\\([^*|]+\\)\\*" "**\\1**" converted))
                        ;; Remove \_ indentation markers
                        (setq converted (replace-regexp-in-string
                                         "\\\\_[ \t]*" "" converted))
                        ;; Skip rows with **0:00** (empty file summaries)
                        (unless (string-match-p "\\*\\*0:00\\*\\*" converted)
                          converted)))
                     (t nil)))
                  lines))))
      ;; Merge extra time columns (4+) into a single column, then realign
      (weekly-report--realign-table
       (weekly-report--merge-table-columns result)))))

(defun weekly-report--merge-table-columns (lines)
  "Merge extra time columns in table LINES into a single time column.
If the table has more than 3 data columns, merge columns 3+ into one
by keeping the rightmost non-empty value.  Returns a list of lines."
  (let* ((first-data (seq-find (lambda (l)
                                 (and (string-match-p "^|" l)
                                      (not (string-match-p "^|[-|]" l))))
                               lines)))
    (if (and first-data
             (> (length (split-string first-data "|" t)) 3))
        (mapcar
         (lambda (line)
           (if (not (string-match-p "^|" line))
               line
             (let ((cells (split-string line "|" t)))
               (if (<= (length cells) 3)
                   line
                 (let* ((base (list (nth 0 cells) (nth 1 cells)))
                        (rest (nthcdr 2 cells))
                        (merged
                         (if (string-match-p "^[ \t]*-" (car rest))
                             ;; Separator: keep one cell
                             (car rest)
                           ;; Data: rightmost non-blank cell
                           (or (seq-find (lambda (c) (not (string-blank-p c)))
                                         (reverse rest))
                               (car rest)))))
                   (concat "|" (mapconcat #'identity
                                          (append base (list merged))
                                          "|")
                           "|"))))))
         lines)
      lines)))

(defun weekly-report--realign-table (lines)
  "Realign Markdown table LINES using `string-width' for CJK-aware padding.
Returns a single string with the realigned table."
  (let* (;; Parse each line into a list of trimmed cells, or symbol 'sep
         (parsed
          (mapcar
           (lambda (line)
             (if (string-match-p "^|[ \t]*-" line)
                 'sep
               (mapcar #'string-trim
                       (split-string
                        (replace-regexp-in-string "^|\\||$" "" line)
                        "|"))))
           lines))
         ;; Determine number of columns
         (ncols (apply #'max 1
                       (mapcar (lambda (r) (if (eq r 'sep) 0 (length r)))
                               parsed)))
         ;; Calculate max string-width per column
         (col-widths (make-vector ncols 0)))
    ;; First pass: find max display width per column
    (dolist (row parsed)
      (unless (eq row 'sep)
        (dotimes (i (min ncols (length row)))
          (let ((w (string-width (nth i row))))
            (when (> w (aref col-widths i))
              (aset col-widths i w))))))
    ;; Second pass: rebuild with correct padding
    (mapconcat
     (lambda (row)
       (if (eq row 'sep)
           ;; Separator: dashes matching column width + 2 (for padding spaces)
           (concat "|"
                   (mapconcat (lambda (w) (make-string (+ w 2) ?-))
                              (append col-widths nil) "|")
                   "|")
         ;; Data row: pad each cell to column width using string-width
         (let ((cells row))
           (concat "| "
                   (mapconcat
                    (lambda (i)
                      (let* ((cell (or (nth i cells) ""))
                             (w (aref col-widths i))
                             (pad (max 0 (- w (string-width cell)))))
                        (concat cell (make-string pad ?\s))))
                    (number-sequence 0 (1- ncols))
                    " | ")
                   " |"))))
     parsed "\n")))

;;;; Clock time utilities

(defun weekly-report--entry-clock-minutes ()
  "Get total clocked minutes for the org entry at point."
  (let ((total 0)
        (bound (save-excursion
                 (or (outline-next-heading) (goto-char (point-max)))
                 (point))))
    (save-excursion
      (while (re-search-forward
              "CLOCK:.*=>[ \t]*\\([0-9]+\\):\\([0-9]+\\)" bound t)
        (setq total (+ total
                       (* 60 (string-to-number (match-string 1)))
                       (string-to-number (match-string 2))))))
    total))

(defun weekly-report--format-duration (minutes)
  "Format MINUTES as H:MM string, or nil if zero."
  (when (> minutes 0)
    (format "%d:%02d" (/ minutes 60) (mod minutes 60))))

;;;; Entry body extraction

(defun weekly-report--entry-body ()
  "Get body text of the org entry at point, excluding drawers and metadata."
  (save-excursion
    (let* ((start (progn (org-end-of-meta-data t) (point)))
           (end (save-excursion
                  (or (outline-next-heading) (goto-char (point-max)))
                  (point))))
      (when (< start end)
        (let ((text (string-trim (buffer-substring-no-properties start end))))
          (unless (string-empty-p text)
            text))))))

;;;; Timestamp range check

(defun weekly-report--timestamp-in-range-p (timestamp start-time end-time)
  "Check if org TIMESTAMP string falls within START-TIME to END-TIME (inclusive)."
  (when (string-match "\\[\\([0-9]+-[0-9]+-[0-9]+\\)" timestamp)
    (let ((ts (weekly-report--parse-date (match-string 1 timestamp))))
      (and ts
           (not (time-less-p ts start-time))
           (not (time-less-p end-time ts))))))

;;;; DONE items extraction

(defun weekly-report--extract-done-items (inbox-file start-time end-time
                                          &optional legacy-archive-file)
  "Extract DONE/CANCEL items from INBOX-FILE, its _archive, and LEGACY-ARCHIVE-FILE.
START-TIME and END-TIME are time values defining the week range.
All sources are filtered by CLOSED timestamp."
  (let ((items '())
        (files (delq nil
                     (list (expand-file-name inbox-file)
                           (let ((archive (concat (expand-file-name inbox-file) "_archive")))
                             (when (file-exists-p archive) archive))
                           (when (and legacy-archive-file
                                      (file-exists-p legacy-archive-file))
                             legacy-archive-file)))))
    (dolist (file files)
      (when (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (org-mode)
          (org-map-entries
           (lambda ()
             (let* ((heading (org-get-heading t t t t))
                    (todo-state (org-get-todo-state))
                    (closed (org-entry-get nil "CLOSED"))
                    (clock-min (weekly-report--entry-clock-minutes))
                    (body (weekly-report--entry-body)))
               (when (and (member todo-state '("DONE" "CANCEL"))
                          closed
                          (weekly-report--timestamp-in-range-p
                           closed start-time end-time))
                 (push (list heading clock-min body) items))))
           nil nil))))
    (nreverse items)))

(defun weekly-report--format-done-items (items)
  "Format ITEMS as Markdown checkbox list.
Each item is (heading clock-minutes body-or-nil)."
  (if (null items)
      ""
    (mapconcat
     (lambda (item)
       (let* ((heading (nth 0 item))
              (clock-min (nth 1 item))
              (body (nth 2 item))
              (duration (weekly-report--format-duration clock-min))
              (line (if duration
                        (format "- [x] %s (%s)" heading duration)
                      (format "- [x] %s" heading))))
         (if body
             (concat line "\n"
                     (mapconcat (lambda (l) (concat "  " l))
                                (split-string
                                 (weekly-report--org-text-to-markdown body) "\n")
                                "\n"))
           line)))
     items "\n")))

;;;; Clocktable generation

(defun weekly-report--generate-clocktable (start-str next-start-str inbox-file
                                           &optional legacy-archive-file)
  "Generate clocktable as Markdown table for range START-STR to NEXT-START-STR.
INBOX-FILE's _archive and LEGACY-ARCHIVE-FILE are included in scope if they exist."
  (let* ((inbox-archive (concat (expand-file-name inbox-file) "_archive"))
         (extra-files (delq nil
                            (list (when (file-exists-p inbox-archive) inbox-archive)
                                  (when (and legacy-archive-file
                                             (file-exists-p legacy-archive-file))
                                    (expand-file-name legacy-archive-file)))))
         (org-agenda-files
          (append (mapcar #'expand-file-name
                          (seq-filter #'file-exists-p weekly-report-agenda-files))
                  extra-files)))
    (if (null org-agenda-files)
        ""
      (condition-case err
          (with-temp-buffer
            (org-mode)
            (insert (format (concat "#+BEGIN: clocktable"
                                    " :scope agenda"
                                    " :maxlevel 10"
                                    " :lang \"ja\""
                                    " :tstart \"%s\""
                                    " :tend \"%s\"\n")
                            start-str next-start-str))
            (insert "#+END:\n")
            (goto-char (point-min))
            (org-update-dblock)
            (weekly-report--org-table-to-markdown
             (buffer-substring-no-properties (point-min) (point-max))))
        (error
         (message "Warning: clocktable generation failed: %s"
                  (error-message-string err))
         "")))))

;;;; Agenda generation

(defun weekly-report--generate-agenda (next-start-str)
  "Generate agenda text for the week starting at NEXT-START-STR."
  (let ((org-agenda-files
         (mapcar #'expand-file-name
                 (seq-filter #'file-exists-p weekly-report-agenda-files)))
        (org-agenda-start-day next-start-str)
        (org-agenda-span 7)
        (org-agenda-start-on-weekday nil)
        (org-agenda-window-setup 'current-window)
        (org-agenda-use-time-grid nil)
        (org-agenda-skip-scheduled-if-done '("DONE" "CANCEL")))
    (if (null org-agenda-files)
        ""
      (condition-case err
          (let ((temp-file (make-temp-file "weekly-report-agenda-")))
            (unwind-protect
                (progn
                  (org-agenda nil "a")
                  (org-agenda-write temp-file)
                  (when (buffer-live-p (get-buffer org-agenda-buffer-name))
                    (kill-buffer org-agenda-buffer-name))
                  (with-temp-buffer
                    (insert-file-contents temp-file)
                    (goto-char (point-min))
                    ;; Remove header line (e.g. "Week-agenda (W08-W09):")
                    (kill-whole-line)
                    (string-trim-right (buffer-string))))
              (delete-file temp-file)))
        (error
         (message "Warning: agenda generation failed: %s"
                  (error-message-string err))
         "")))))

;;;; TODO list extraction

(defun weekly-report--extract-todos (inbox-file)
  "Extract TODO/WAIT/SOMEDAY entries from INBOX-FILE."
  (let ((items '())
        (file (expand-file-name inbox-file)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (org-mode)
        (org-map-entries
         (lambda ()
           (let* ((heading (org-get-heading t t t t))
                  (todo-state (org-get-todo-state))
                  (tags (org-get-tags)))
             (when (equal todo-state "TODO")
               (push (list heading tags) items))))
         nil nil)))
    (nreverse items)))

(defun weekly-report--format-todo-items (items)
  "Format TODO ITEMS as Markdown list.
Each item is (heading tags-list)."
  (if (null items)
      ""
    (mapconcat
     (lambda (item)
       (let* ((heading (nth 0 item))
              (tags (nth 1 item))
              (tag-str (when tags
                         (format " (%s)" (mapconcat #'identity tags ", ")))))
         (format "- [ ] %s%s" heading (or tag-str ""))))
     items "\n")))

;;;; Heading-based section replacement

(defun weekly-report--split-into-sections (content)
  "Split CONTENT into a list of (heading-line . body-string) pairs.
Headings inside fenced code blocks are ignored.
The first element may have nil as heading for content before the first heading."
  (let ((lines (split-string content "\n"))
        (in-code-block nil)
        (current-heading nil)
        (current-body '())
        (sections '()))
    (dolist (line lines)
      (cond
       ;; Toggle code block state
       ((string-match-p "^```" line)
        (setq in-code-block (not in-code-block))
        (push line current-body))
       ;; Heading line (outside code block)
       ((and (not in-code-block)
             (string-match-p "^#\\{1,6\\} " line))
        ;; Save previous section
        (push (cons current-heading
                    (mapconcat #'identity (nreverse current-body) "\n"))
              sections)
        (setq current-heading line)
        (setq current-body '()))
       ;; Normal line
       (t (push line current-body))))
    ;; Save last section
    (push (cons current-heading
                (mapconcat #'identity (nreverse current-body) "\n"))
          sections)
    (nreverse sections)))

(defun weekly-report--replace-sections (content sections)
  "Replace section bodies in CONTENT based on SECTIONS alist.
SECTIONS is an alist of (heading-text . new-body).
Only sections whose heading matches exactly are replaced.
Returns updated content string."
  (let* ((parsed (weekly-report--split-into-sections content))
         ;; Skip empty preamble (nil heading with blank body)
         (filtered (if (and (car parsed)
                            (null (caar parsed))
                            (string-blank-p (cdar parsed)))
                       (cdr parsed)
                     parsed)))
    (mapconcat
     (lambda (section)
       (let* ((heading (car section))
              (body (cdr section))
              (replacement (assoc heading sections)))
         (if heading
             (concat heading "\n"
                     (if replacement (concat (cdr replacement) "\n") body))
           ;; No heading (preamble before first heading)
           body)))
     filtered "\n")))

;;;; Template generation

(defun weekly-report--generate-template (start-str end-str)
  "Generate full Markdown template for the week START-STR to END-STR."
  (concat
   (format "# 今週のこと (%s 〜 %s)\n\n" start-str end-str)
   "## やったこと\n\n"
   "## 時間計測\n\n"
   "## 考えたこと\n"
   "### 良かったこと\n\n"
   "### 改善点、気づき\n\n"
   "### やり残したこと\n\n"
   "# 来週のこと\n\n"
   "## 予定\n\n"
   "## TODOリスト\n\n"
   "## 考えていること\n"))

;;;; Main entry point

(defun weekly-report-generate ()
  "Generate weekly report.
Reads --date argument from command line, or defaults to today."
  (let* ((date-arg (weekly-report--parse-args))
         (range (weekly-report--date-range date-arg))
         (start-str (plist-get range :start))
         (end-str (plist-get range :end))
         (start-mmdd (plist-get range :start-mmdd))
         (end-mmdd (plist-get range :end-mmdd))
         (year (plist-get range :year))
         (start-time (plist-get range :start-time))
         (end-time (plist-get range :end-time))
         (next-start-str (plist-get range :next-start))
         ;; File paths
         (output-dir (expand-file-name
                      year
                      (expand-file-name weekly-report-archive-dir)))
         (legacy-archive-org (expand-file-name
                              (format "%s-%s.org" start-mmdd end-mmdd) output-dir))
         (output-file (expand-file-name
                       (format "%s-%s.md" start-mmdd end-mmdd) output-dir))
         (inbox-file (expand-file-name "inbox/inbox.org" weekly-report-org-dir)))
    (message "Generating weekly report for %s to %s..." start-str end-str)
    ;; Extract data
    (let* ((done-items (weekly-report--extract-done-items
                        inbox-file start-time end-time
                        legacy-archive-org))
           (clocktable (weekly-report--generate-clocktable
                        start-str next-start-str inbox-file
                        legacy-archive-org))
           (agenda (weekly-report--generate-agenda next-start-str))
           (todos (weekly-report--extract-todos inbox-file))
           ;; Format sections (keys are heading lines)
           (sections
            `(("## やったこと" . ,(weekly-report--format-done-items done-items))
              ("## 時間計測" . ,clocktable)
              ("## 予定" . ,(format "```\n%s\n```" agenda))
              ("## TODOリスト" . ,(weekly-report--format-todo-items todos)))))
      ;; Ensure directory exists
      (make-directory output-dir t)
      ;; Update or create file
      (let* ((existing (when (file-exists-p output-file)
                         (with-temp-buffer
                           (insert-file-contents output-file)
                           (buffer-string))))
             (content (weekly-report--replace-sections
                       (or existing
                           (weekly-report--generate-template start-str end-str))
                       sections)))
        (let ((coding-system-for-write 'utf-8))
          (with-temp-file output-file
            (insert content)))
        (message "Generated: %s" output-file)))))

(provide 'weekly-report)
;;; weekly-report.el ends here
