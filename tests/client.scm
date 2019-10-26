(use gauche.test)

(add-load-path "../client")

(test-start "chaton.client")
(use chaton.client)
(test-module 'chaton.client)

(test-end)
