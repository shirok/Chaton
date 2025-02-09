;;;
;;;  Chaton client utilities
;;;

;; NB: The protocol between the client and the chaton server is provisional.
;; Do not rely on this particular protocol at this moment; it can be
;; changed without prior notice.

(define-module chaton.client
  (use gauche.net)
  (use gauche.threads)
  (use gauche.parameter)
  (use gauche.experimental.ref)
  (use gauche.logger)
  (use srfi.13)
  (use srfi.27)
  (use rfc.http)
  (use rfc.uri)
  (use file.util)
  (use text.tree)
  (use util.match)
  (export <chaton-client> chaton-connect
          chaton-room-url chaton-room-name chaton-post-url chaton-comet-url
          chaton-icon-url chaton-cid chaton-pos chaton-observer-error
          chaton-permalink

          chaton-talk chaton-bye

          chaton-log-open <chaton-error>))
(select-module chaton.client)

(define-condition-type <chaton-error> <error>
  (room-url #f))

;; Holds info about a connection to a room.  All slots should be
;; considered private.  Client programs must use exported getters.
(define-class <chaton-client> ()
  ((room-url  :init-keyword :room-url  :getter chaton-room-url)
   (room-name :init-keyword :room-name :getter chaton-room-name)
   (observer  :init-keyword :observer)
   (post-url  :init-keyword :post-url  :getter chaton-post-url)
   (comet-url :init-keyword :comet-url :getter chaton-comet-url)
   (icon-url  :init-keyword :icon-url  :getter chaton-icon-url)
   (cid       :init-keyword :cid       :getter chaton-cid)
   (pos       :init-keyword :pos       :getter chaton-pos)
   (observer-thread :init-form #f)
   (observer-error  :init-form #f      :getter chaton-observer-error)
   ))

(define *chaton-log-drain* #f)

(define (chaton-log-open path . args)
  (set! *chaton-log-drain* (apply make <log-drain> :path path args)))

;; API
;;  chaton-connect ROOM-URL APP-NAME :optional OBSERVER RETRY
;;  => #<chaton-client>
;;
;;  Establish connection to a chaton room specified by ROOM-URL.
;;  APP-NAME is a string application name, used for logging.
;;
;;  OBSERVER :: (<chaton-client> <packet>) => <? <datum>>
(define (chaton-connect room-url app-name :optional (observer #f) (retry 0))
  (match-let1 (name post comet icon cid pos)
      (let loop ([n retry] [last-error #f])
        (if (< n 0)
          (errorf "Chaton-connect failed (after ~a retry): ~s" retry last-error)
          (let1 r (guard (e [(error? e) e])
                    (values->list (%connect-main room-url app-name)))
            (if (error? r)
              (loop (- n 1) r)
              r))))
    (rlet1 client (make <chaton-client>
                    :room-url room-url :observer observer
                    :post-url post :comet-url comet :icon-url icon
                    :room-name name :cid cid :pos pos)
      (set! (~ client'observer-thread) (make-handler client observer)))))

(define (chaton-talk client nickname text)
  (POST (~ client'room-url) (~ client'post-url)
        `((nick ,nickname) (text ,text) (cid ,(~ client'cid))))
  #t)

(define (chaton-bye client)
  (cond [(~ client'observer-thread) => thread-terminate!]))

;; utility method to return a permalink from the client and
;; timestamp (<seconds> <microseconds>)
(define (chaton-permalink client timestamp)
  (match-let1 (secs usecs) timestamp
    (build-path (~ client'room-url) "a"
                (format "~a#~a"
                        (sys-strftime "%Y/%m/%d" (sys-gmtime secs))
                        (format "entry-~x-~2,'0x" secs usecs)))))

;;;
;;; Internal stuff
;;;

(define (make-handler client observer)
  (define handle-it (or observer values))
  (define (loop)
    (guard (e [(eq? e 'disconnected)
               ;; wait for a while and retry
               (log-format *chaton-log-drain*
                           "comet server disconnected.  retrying...")
               (sys-sleep (+ 5 (random-integer 10)))
               #f]
              [else
               (set! (~ client'observer-error) e)
               (log-format *chaton-log-drain*
                           "observer thread error: ~a" (~ e'message))
               (when (<chaton-error> e) (handle-it client e))
               (sys-sleep 3)    ;avoid busy loop
               #f])
      (let1 packet (%fetch client)
        (let ([new-pos (assq-ref packet 'pos)]
              [new-cid (assq-ref packet 'cid)])
          (unwind-protect (handle-it client packet)
            (begin
              (when new-pos (set! (~ client'pos) new-pos))
              (when new-cid (set! (~ client'cid) new-cid)))))))
    (loop))
  (thread-start! (make-thread loop)))

(define (%connect-main room-url who)
  (let1 reply (POST room-url (build-path room-url "apilogin") `((who ,who)))
    (values (assq-ref reply 'room-name)
            (assq-ref reply 'post-uri)
            (assq-ref reply 'comet-uri)
            (assq-ref reply 'icon-uri)
            (assq-ref reply 'cid)
            (assq-ref reply 'pos))))

(define (%fetch client)
  (guard (e [(and (<http-error> e)
                  (#/http reply contains no data/ (~ e'message)))
             (raise 'disconnected)])
    (GET (ref client'room-url) (ref client'comet-url)
         `((t ,(sys-time)) (c ,(~ client'cid)) (p ,(~ client'pos)) (s 1)))))

(define (GET room-url uri params)
  (match-let1 (scheme host+port path) (uri-ref uri '(scheme host+port path))
    (receive (status hdrs body)
        (http-get host+port `(,path ,@params) :secure (equal? scheme "https"))
      (unless (equal? status "200")
        (cerrf room-url "GET from ~a failed with ~a" uri status))
      (safe-parse room-url body))))

(define (POST room-url uri params)
  (match-let1 (scheme host+port path) (uri-ref uri '(scheme host+port path))
    (receive (status hdrs body)
        (http-post host+port path params :secure (equal? scheme "https"))
      (unless (equal? status "200")
        (cerrf room-url "POST to ~a failed with ~a" uri status))
      (safe-parse room-url body))))

(define (safe-parse room-url reply)
  (guard (e [(<read-error> e)
             (cerrf room-url "invalid reply from server: ~s" reply)])
    (read-from-string reply)))

(define (cerrf room-url fmt . args)
  (apply errorf <chaton-error> :room-url room-url fmt args))
