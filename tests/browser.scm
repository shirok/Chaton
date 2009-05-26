;;
;; basic tests for browser
;;

(use gauche.test)

(add-load-path "..")

(test-start "browser")
(load "../chaton-browser")
(define main #f)                        ;prevent execution of 'main'
(test-module 'chaton.browser)

(test-end)
