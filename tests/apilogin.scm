;;
;; basic tests for apilogin
;;

(use gauche.test)
(use text.tree)

(add-load-path "..")

(test-start "apilogin")
(load "../chaton-apilogin")
(define main #f)                        ;prevent execution of 'main'

;; override by dummy fuction to bypass connecting to the viewer daemon
(define (get-cid) '((cred . "testcred")))

(test* "check-login (sexpr)"
       "Content-type: application/x-sexpr; charset=utf-8\r\ncache-control: no-cache\r\n\r\n((post-uri . \"@@httpd-url@@@@url-path@@@@cgi-script@@\") (comet-uri . \"@@httpd-url@@:@@comet-port@@/\") (icon-uri . \"@@icon-url@@\") (room-name . \"@@room-name@@\") (cred . \"testcred\"))"
       (tree->string (check-login '(("who" "test")))))

(test* "check-login (json)"
       "Content-type: application/json; charset=utf-8\r\ncache-control: no-cache\r\n\r\n{\"post-uri\":\"@@httpd-url@@@@url-path@@@@cgi-script@@\",\"comet-uri\":\"@@httpd-url@@:@@comet-port@@/\",\"icon-uri\":\"@@icon-url@@\",\"room-name\":\"@@room-name@@\",\"cred\":\"testcred\"}"
       (tree->string (check-login '(("who" "test") ("s" "0")))))

(test-end)
