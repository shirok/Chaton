;;
;; basic tests for viewer
;;

(use gauche.test)

(add-load-path "..")

(test-start "viewer")
(load "../chaton-viewer")
(define main #f)                        ;prevent execution of 'main'
(test-module 'chaton.viewer)

(test-end)
