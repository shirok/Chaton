;;
;; basic tests for entry
;;

(use gauche.test)

(add-load-path "..")

(test-start "entry")
(load "../chaton-entry")
(define main #f)                        ;prevent execution of 'main'
(test-module 'chaton.entry
             :allow-undefined '(@@room-description/escd@@ @@room-name/escd@@))

(test-end)
