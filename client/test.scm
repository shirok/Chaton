(use gauche.test)
(add-load-path ".")

(test-start "chaton client")

(test-section "chaton.client")
(use chaton.client)
(test-module 'chaton.client)

(test-section "sample scripts")

(test-script "examples/chaton-watcher")

(cond-expand
 [(library app.bsky)
  (test-script "examples/chaton-bsky")]
 [else])

(cond-expand
 [(and (library net.twitter.stream)
       (library net.twitter.status)
       (library net.twitter.friendship)
       (library net.twitter.core))
  (test-script "examples/chaton-twitter")]
 [else])

(test-end)
