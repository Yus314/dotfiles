(defvar *my-search-engines*
  (list
   '("hm" "https://home-manager-options.extranix.com/?query=~a&release=master" "https://home-manager-options.extranix.com")
   '("no" "https://search.nixos.org/options?channel=unstable&from=0&size=50&sort=relevance&type=packages&query=~a" "https://search.nixos.org")
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

(define-configuration web-buffer
		      ((override-map
			(let ((map (make-keymap "override-map")))
			  (define-key map
				      "M-x" 'execute-command
				      "C-space" 'nothing
				      "f" 'search-buffer
				      "s" 'follow-hint)))))

(define-nyxt-user-system-and-load "nyxt-user/rbw"
				  :depends-on ("nx-rbw"))

(define-configuration :password-mode
		      ((password-interface (make-instance 'nx-rbw:rbw-interface))))

(nyxt:define-nyxt-user-system-and-load "nyxt-user/nx-zotero-proxy"
				       :description "This proxy system saves us if nx-zotero fails to load.
Otherwise it will break all the config loading."
				       :depends-on ("nx-zotero"))
(define-configuration web-buffer
		      ((default-modes
			(pushnew 'zotero-mode %slot-value%))))
