(require "helix/editor.scm")
(require "helix/misc.scm")
(require (prefix-in helix. "helix/commands.scm"))
(require (prefix-in helix.static. "helix/static.scm"))

(provide session-create
         session-delete
         session-list
         session-load)

(define SESSION-DIRECTORY ".helix/sessions")
(define SESSION-EXTENSION ".scm")

(define (session-valid-name? name)
  (and (string? name)
       (> (string-length name) 0)
       (not (string-contains? name "/"))
       (not (string-contains? name "\\"))
       (not (string-contains? name ".."))))

(define (session-path name)
  (string-append SESSION-DIRECTORY "/" name SESSION-EXTENSION))

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
  (unless (path-exists? ".helix")
    (create-directory! ".helix"))
  (unless (path-exists? SESSION-DIRECTORY)
    (create-directory! SESSION-DIRECTORY)))

(define (file-backed-documents)
  (filter string?
          (map (lambda (document-id)
                 (editor-document->path document-id))
               (editor-all-documents))))

(define (read-session path)
  (call-with-input-file path
                        (lambda (port)
                          (~> port read-port-to-string read! car))))

(define (list-of-strings? values)
  (cond
    [(null? values) #true]
    [(not (pair? values)) #false]
    [(not (string? (car values))) #false]
    [else (list-of-strings? (cdr values))]))

;;@doc
;; Save all file-backed buffers in a project-local named session.
(define (session-create . arguments)
  (let ([name (session-name arguments "session-create")])
    (when name
      (ensure-session-directory!)
      (let ([path (session-path name)]
            [documents (file-backed-documents)])
        (call-with-port (open-output-file path #:exists 'truncate)
                        (lambda (port)
                          (write documents port)))
        (set-status! (string-append "Saved session '" name "' (" (number->string (length documents))
                                    " files)"))))))

;;@doc
;; Delete a project-local named session.
(define (session-delete . arguments)
  (let ([name (session-name arguments "session-delete")])
    (when name
      (let ([path (session-path name)])
        (if (path-exists? path)
            (begin
              (delete-file! path)
              (set-status! (string-append "Deleted session '" name "'")))
            (set-error! (string-append "Session '" name "' does not exist")))))))

;;@doc
;; Show the project-local session names in the status line.
(define (session-list)
  (if (path-exists? SESSION-DIRECTORY)
      (let ([names (map (lambda (path)
                          (substring (file-name path)
                                     0
                                     (- (string-length (file-name path))
                                        (string-length SESSION-EXTENSION))))
                        (filter (lambda (path)
                                  (and (is-file? path)
                                       (ends-with? (file-name path) SESSION-EXTENSION)))
                                (read-dir SESSION-DIRECTORY)))])
        (set-status! (if (null? names)
                         "No saved sessions"
                         (string-append "Sessions: " (string-join names ", ")))))
      (set-status! "No saved sessions")))

;;@doc
;; Open the files from a named session in vertical splits.
(define (session-load . arguments)
  (let ([name (session-name arguments "session-load")])
    (when name
      (let ([path (session-path name)])
        (if (not (path-exists? path))
            (set-error! (string-append "Session '" name "' does not exist"))
            (let ([documents (read-session path)])
              (cond
                [(not (list-of-strings? documents))
                 (set-error! (string-append "Session '" name "' is malformed"))]
                [(null? documents)
                 (set-status! (string-append "Session '" name "' is empty"))]
                [else
                 (helix.open (car documents))
                 (for-each (lambda (document)
                             (helix.static.vsplit)
                             (helix.open document))
                           (cdr documents))
                 (set-status! (string-append "Loaded session '" name "' ("
                                             (number->string (length documents))
                                             " files)"))])))))))
