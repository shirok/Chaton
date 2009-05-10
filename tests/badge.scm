;;
;; basic tests for badge
;;

(use gauche.test)

(add-load-path "..")

(test-start "badge")
(load "../chaton-badge")
(define main #f)                        ;prevent execution of 'main'
(test-module 'chaton.badge)

(test-end)
