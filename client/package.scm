;;
;; Package chaton-client
;;

(define-gauche-package "Chaton-client"
  :version "2.0"
  :description "Client library of Chaton chat server"
  :require (("Gauche" (>= "0.9.13")))
  :providing-modules (chaton.client)
  :authors ("Shiro Kawai <shiro@acm.org>")
  :maintainers ()
  :licenses ("BSD")
  :homepage "https://chaton.practical-scheme.net/"
  :repository "https://github.com/shork/Chaton"
  )
