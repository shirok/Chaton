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
  (use srfi-13)
  (use srfi-27)
  (use rfc.http)
  (use rfc.uri)
  (use file.util)
  (use text.tree)
  (use util.list)
  (use util.queue)
  (use util.match)
  (export chaton-connect
          chaton-room-url chaton-room-name chaton-post-url chaton-comet-url
          chaton-icon-url chaton-cid chaton-pos chaton-observer-error
          chaton-permalink
          chaton-message-dequeue!
          
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
   (message-queue   :init-form (make-queue))
   (message-mutex   :init-form (make-mutex))
   (message-cv      :init-form (make-condition-variable))
   ))

(define *chaton-log-drain* #f)

(define (chaton-log-open path . args)
  (set! *chaton-log-drain* (apply make <log-drain> :path path args)))

;; chaton-connect ROOM-URL APP-NAME :optional OBSERVER => #<chaton-client>
(define (chaton-connect room-url app-name :optional (observer #f))
  (receive (name post comet icon cid pos) (%connect-main room-url app-name)
    (rlet1 client (make <chaton-client>
                    :room-url room-url :observer observer
                    :post-url post :comet-url comet :icon-url icon
                    :room-name name :cid cid :pos pos)
      (set! (~ client'observer-thread) (make-handler client observer)))))

(define (chaton-talk client nickname text)
  (POST (~ client'room-url) (~ client'post-url)
        `((nick . ,nickname) (text . ,text) (cid . ,(~ client'cid))))
  #t)

(define (chaton-bye client)
  ;; thread-terminate! is not recommended generally.  this may leave
  ;; message-mutex "abandoned" state.
  (cond [(~ client'observer-thread) => thread-terminate!]))

(define (chaton-message-dequeue! client :optional (timeout #f) (timeout-val #f))
  (let1 mutex (~ client'message-mutex)
    (guard (e [(<abandoned-mutex-exception> e) '()]
              [else (when (eq? (mutex-state mutex) (current-thread))
                      (mutex-unlock! mutex))
                    (raise e)])
      (let loop ()
        (mutex-lock! mutex)
        (if (queue-empty? (~ client'message-queue))
          (if (mutex-unlock! mutex (~ client'message-cv) timeout)
            (loop)
            timeout-val)
          (begin0 (dequeue! (~ client'message-queue))
            (mutex-unlock! mutex)))))))

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
  (define handle-it (or observer (lambda (_ _) #f)))
  (define (loop)
    (let1 r (guard (e [(eq? e 'disconnected)
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
      (when (and (not (null? r)) (list? r))
        (with-locking-mutex (~ client'message-mutex)
          (lambda ()
            (enqueue! (~ client'message-queue) r)
            (condition-variable-broadcast! (~ client'message-cv))))))
    (loop))
  (thread-start! (make-thread loop)))

(define (%connect-main room-url who)
  (let1 reply (POST room-url (build-path room-url "apilogin") `((who . ,who)))
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
         `((t . ,(sys-time)) (c . ,(~ client'cid)) (p . ,(~ client'pos))
           (s . 1)))))

(define (GET room-url uri params)
  (receive (host path) (host&path uri)
    (receive (status hdrs body)
        (http-get host #`",path,(make-qstr params)")
      (unless (equal? status "200")
        (cerrf room-url "GET from ~a failed with ~a" uri status))
      (safe-parse room-url body))))

(define (POST room-url uri params)
  (receive (host path) (host&path uri)
    (receive (body boundary) (make-mime params)
      (receive (status hdrs body)
          (http-post host path body
                     :mime-version "1.0"
                     :content-type #`"multipart/form-data; boundary=,boundary")
        (unless (equal? status "200")
          (cerrf room-url "POST to ~a failed with ~a" uri status))
        (safe-parse room-url body)))))

(define (host&path uri)
  (receive (scheme specific) (uri-scheme&specific uri)
    (receive (host path q f) (uri-decompose-hierarchical specific)
      (values host path))))

(define (make-qstr alist)
  (define (do-item k&v)
    `(,(uri-encode-string (x->string (car k&v))) "="
      ,(uri-encode-string (x->string (cdr k&v)))))
  (if (null? alist)
    ""
    (tree->string `("?" ,(intersperse "&" (map do-item alist))))))

(define (make-mime alist)
  (let1 boundary (format "boundary-~a"
                         (number->string (* (random-integer (expt 2 64))
                                            (sys-time) (sys-getpid))
                                         36))
    (values (tree->string
             `(,(map (lambda (k&v)
                       `("\r\n--",boundary"\r\n"
                         "Content-disposition: form-data; name=\"",(car k&v)"\"\r\n\r\n"
                         ,(x->string (cdr k&v))))
                     alist)
               "\r\n--",boundary"--\r\n"))
            boundary)))

(define (safe-parse room-url reply)
  (guard (e [(<read-error> e)
             (cerrf room-url "invalid reply from server: ~s" reply)])
    (read-from-string reply)))

(define (cerrf room-url fmt . args)
  (apply errorf <chaton-error> :room-url room-url fmt args))

(provide "chaton/client")
