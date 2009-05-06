;;
;; basic tests for archiver
;;

(use gauche.test)

(add-load-path "..")

(test-start "archiver")
(load "../chaton-archiver")
(define main #f)                        ;prevent execution of 'main'
(test-module 'chaton.archiver)

(test-end)
