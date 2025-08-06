(defvar *my-search-engines*
  (list
   '("en" "https://google.com/search?lr=lang_en&q=~a" "https://google.com")
   '("g" "https://google.com/search?q=~a" "https://google.com"))
  "List of search engines.")

(define-configuration buffer
    "Go through the search engines above and make-search-engine out of them."
  ((search-engines
    (append
     %slot-default%
     (mapcar (lambda (engine) (apply 'make-search-engine engine))
             *my-search-engines*)))))
