(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))
(require (only-in "helix/components.scm"
                  status-element
                  span
                  push-status-element!
                  theme-scope-ref))
(require "steel/result")

(provide session-create
         session-delete
         session-list
         session-load
         session-autoload)

(define (environment-value name fallback)
  (let ([value (maybe-get-env-var name)])
    (if (Ok? value)
        (unwrap-ok value)
        fallback)))

(define SESSION-DIRECTORY
  (string-append (environment-value "XDG_DATA_HOME"
                                    (string-append (env-var "HOME") "/.local/share"))
                 "/helix/sessions"))
(define SESSION-PARENT (parent-name SESSION-DIRECTORY))
(define SESSION-STORE (string-append SESSION-DIRECTORY "/sessions.scm"))
(define *active-session-name* #false)

(define (render-session-status _view-id _focused)
  (if *active-session-name*
      (list (span (string-append " session: " *active-session-name*)
                  (theme-scope-ref "ui.statusline")))
      '()))

(push-status-element! 'right (status-element render-session-status))

(define (session-valid-name? name)
  (and (string? name)
       (> (string-length name) 0)
       (not (string-contains? name "/"))
       (not (string-contains? name "\\"))
       (not (string-contains? name ".."))))

(define (read-forms path)
  (call-with-input-file path
                        (lambda (port)
                          (~> port read-port-to-string read!))))

(define (session-name arguments command)
  (cond
    [(not (= (length arguments) 1))
     (set-error! (string-append command " requires exactly one session name"))
     #false]
    [(not (session-valid-name? (car arguments)))
     (set-error! "Session names cannot be empty or contain '/', '\\', or '..'")
     #false]
    [else (car arguments)]))

(define (ensure-session-directory!)
  (unless (path-exists? SESSION-PARENT)
    (create-directory! SESSION-PARENT))
  (unless (path-exists? SESSION-DIRECTORY)
    (create-directory! SESSION-DIRECTORY)))

(define (file-backed-documents)
  (filter string?
          (map (lambda (document-id)
                 (editor-document->path document-id))
               (editor-all-documents))))

(define (list-of-strings? values)
  (cond
    [(null? values) #true]
    [(not (pair? values)) #false]
    [(not (string? (car values))) #false]
    [else (list-of-strings? (cdr values))]))

(define (session-record? record)
  (and (list? record)
       (= (length record) 3)
       (string? (list-ref record 0))
       (session-valid-name? (list-ref record 1))
       (list-of-strings? (list-ref record 2))))

(define (session-store? records)
  (cond
    [(null? records) #true]
    [(not (pair? records)) #false]
    [(not (session-record? (car records))) #false]
    [else (session-store? (cdr records))]))

(define (read-session-store)
  (if (path-exists? SESSION-STORE)
      (let ([forms (read-forms SESSION-STORE)])
        (if (and (= (length forms) 1)
                 (session-store? (car forms)))
            (car forms)
            #false))
      '()))

(define (write-session-store! records)
  (call-with-port (open-output-file SESSION-STORE #:exists 'truncate)
                  (lambda (port)
                    (write records port))))

(define (find-session records project name)
  (cond
    [(null? records) #false]
    [(and (equal? project (list-ref (car records) 0))
          (equal? name (list-ref (car records) 1)))
     (car records)]
    [else (find-session (cdr records) project name)]))

(define (find-project-session records project)
  (cond
    [(null? records) #false]
    [(equal? project (list-ref (car records) 0)) (car records)]
    [else (find-project-session (cdr records) project)]))

(define (without-session records project name)
  (filter (lambda (record)
            (not (and (equal? project (list-ref record 0))
                      (equal? name (list-ref record 1)))))
          records))

(define (current-project)
  (helix.static.get-helix-cwd))

(define (save-session-documents! name documents)
  (let ([records (read-session-store)]
        [project (current-project)])
    (if (not records)
        (begin
          (set-error! "Session store is malformed")
          #false)
        (begin
          (write-session-store!
           (cons (list project name documents)
                 (without-session records project name)))
          #true))))

(define (session-save-active)
  (when *active-session-name*
    (save-session-documents! *active-session-name* (file-backed-documents))))

;;@doc
;; Save all file-backed buffers in a shared named session store.
(define (session-create . arguments)
  (let ([name (session-name arguments "session-create")])
    (when name
      (ensure-session-directory!)
      (let ([documents (file-backed-documents)])
        (when (save-session-documents! name documents)
          (set! *active-session-name* name)
          (set-status! (string-append "Saved session '" name "' ("
                                      (number->string (length documents))
                                      " files)")))))))

;;@doc
;; Delete a named session for the current project.
(define (session-delete . arguments)
  (let ([name (session-name arguments "session-delete")])
    (when name
      (let ([records (read-session-store)]
            [project (current-project)])
        (cond
          [(not records)
           (set-error! "Session store is malformed")]
          [(not (find-session records project name))
           (set-error! (string-append "Session '" name "' does not exist"))]
          [else
           (write-session-store! (without-session records project name))
           (set-status! (string-append "Deleted session '" name "'"))])))))

;;@doc
;; Show the session names saved for the current project.
(define (session-list)
  (let ([records (read-session-store)])
    (if (not records)
        (set-error! "Session store is malformed")
        (let ([names (map (lambda (record) (list-ref record 1))
                          (filter (lambda (record)
                                    (equal? (current-project) (list-ref record 0)))
                                  records))])
          (set-status! (if (null? names)
                           "No saved sessions"
                           (string-append "Sessions: " (string-join names ", "))))))))

;;@doc
;; Open the files from a named session without changing the layout.
(define (session-load . arguments)
  (let ([name (session-name arguments "session-load")])
    (when name
      (let ([records (read-session-store)]
            [project (current-project)])
        (if (not records)
            (set-error! "Session store is malformed")
            (let ([record (find-session records project name)])
              (if (not record)
                  (set-error! (string-append "Session '" name "' does not exist"))
                  (let ([documents (list-ref record 2)])
                    (set! *active-session-name* name)
                    (if (null? documents)
                        (set-status! (string-append "Session '" name "' is empty"))
                        (begin
                          (for-each (lambda (document)
                                      (helix.open document))
                                    documents)
                          (set-status! (string-append "Loaded session '" name "' ("
                                                      (number->string (length documents))
                                                      " files)"))))))))))))

;;@doc
;; Load the most recently saved session for the current project.
(define (session-autoload)
  (let ([records (read-session-store)])
    (cond
      [(not records)
       (set-error! "Session store is malformed")]
      [(find-project-session records (current-project))
       (session-load (list-ref (find-project-session records (current-project)) 1))])))

(define (session-autoload-on-startup)
  (when (null? (file-backed-documents))
    (session-autoload)))

(register-hook 'document-opened (lambda (_) (session-save-active)))
(register-hook 'document-closed (lambda (_) (session-save-active)))
(enqueue-thread-local-callback session-autoload-on-startup)
