;;
;; basic tests for chaton.scm
;;

(use gauche.test)

(test-start "chaton.scm")
(load "../chaton.scm")
(test-module 'chaton)

(test-end)
