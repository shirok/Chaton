(use gauche.test)
(add-load-path ".")

(test-start "chaton client")

(test-section "chaton.client")
(use chaton.client)
(test-module 'chaton.client)

(test-end)
