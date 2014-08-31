(use gauche.test)
(use www.cgi.test)
(use file.util)
(use util.match)

(define *testdatadir* "data.o")

(test-start "poster")

(add-load-path "..")
(load "../chaton-poster")
(set! main #f)                          ;avoid exection of script main
(test-module 'chaton.poster)

(when (file-exists? *testdatadir*)
  (remove-directory* *testdatadir*))

(define (post nick text)
  (run-cgi-script->string 
   "../chaton-poster"
   :environment `(("GAUCHE_LOAD_PATH" . "..")
                  ("CHATON_DATADIR" . ,*testdatadir*)
                  ("CHATON_DOCDIR"  . ,*testdatadir*))
   :parameters `((nick . ,nick) (text . ,text))))

(define (check nick text)
  (any (^[entry]
         (match entry
           [(nick_ ts text_ remote)
            (and (equal? nick nick_) (equal? text text_))]
           [_ (error "Corrupt entry in current.dat:" entry)]))
       (file->sexp-list (build-path *testdatadir* "current.dat"))))

(define (test-post nick text)
  (test* (format "post ~a ~a" nick text) #t
         (begin (post nick text)
                (boolean (check nick text)))))

(test-post "Nick.name" "text1")
(test-post "Nick.name" "text2")
(test-post "Nock.name" "text3")
(test-post "Nock.name" "<x>oo</x>http://text4/foo?bar#baz<s>yy</s>")

(test-end)


