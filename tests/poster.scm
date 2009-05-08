(use gauche.test)
(use www.cgi.test)
(use file.util)

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

(test* "post" #t (begin (post "Nick.name" "text1") #t))
(test* "post" #t (begin (post "Nick.name" "text2") #t))
(test* "post" #t (begin (post "Nock.name" "text3") #t))
(test* "post" #t (begin (post "Nock.name" "<x>oo</x>http://text4/foo?bar#baz<s>yy</s>") #t))

(test-end)


