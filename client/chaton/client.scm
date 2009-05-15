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
  (export chaton-connect
          chaton-talk
          chaton-bye
          <chaton-error>))
(select-module chaton.client)

(define-condition-type <chaton-error> <error>
  (room-url #f))

(define-class <chaton-client> ()
  ((room-url  :init-keyword :room-url)
   (observer  :init-keyword :observer)
   (post-url  :init-keyword :post-url)
   (comet-url :init-keyword :comet-url)
   (cid       :init-keyword :cid)
   (pos       :init-keyword :pos)
   (observer-thread :init-form #f)
   (observer-error  :init-form #f)
   (message-queue   :init-form (make-queue))
   (message-mutex   :init-form (make-mutex))
   ))

(define *chaton-log-drain* #f)

(define (chaton-log-open path . args)
  (set! *chaton-log-drain* (apply make <log-drain> :path path args)))

;; chaton-connect ROOM-URL APP-NAME :optional OBSERVER => #<chaton-client>
(define (chaton-connect room-url app-name :optional (observer #f))
  (receive (post-url comet-url cid pos) (%connect-main room-url app-name)
    (rlet1 client (make <chaton-client>
                  :room-url room-url :observer observer
                  :post-url post-url :comet-url comet-url :cid cid :pos pos)
      (set! (~ client'observer-thread) (make-handler client observer)))))

(define (chaton-talk client nickname text)
  (POST (~ client'room-url) (~ client'post-url)
        `((nick . ,nickname) (text . ,text) (cid . ,(~ client'cid))))
  #t)

(define (chaton-bye client)
  ;; thread-terminate! is not recommended generally.  this may leave
  ;; message-mutex "abandoned" state.
  (cond [(~ client'observer-thread) => thread-terminate!]))

;;;
;;; Internal stuff
;;;

(define (make-handler client observer)
  (define handle (or observer (lambda (_) #f)))
  (define (loop)
    (let1 r (guard (e [(<chaton-error> e) (handle e)]
                      [else
                       (set! (~ client'observer-error) e)
                       (log-format *chaton-log-drain*
                                   "observer thread error: ~a" (~ e'message))
                       (raise e)])
              (let1 packet (%fetch client)
                (and-let* ([new-pos (assq-ref packet 'pos)])
                  (set! (~ client'pos) new-pos))
                (and-let* ([new-cid (assq-ref packet 'cid)])
                  (set! (~ client'cid) new-cid))
                (handle packet)))
      (when (and (not (null? r)) (list? r))
        (with-locking-mutex (~ client'message-mutex)
          (lambda () (apply enqueue! (~ client'message-queue) r)))))
    (loop))
  (thread-start! (make-thread loop)))

(define (%connect-main room-url who)
  (let1 reply (POST room-url (build-path room-url "apilogin") `((who . ,who)))
    (values (assq-ref reply 'post-uri)
            (assq-ref reply 'comet-uri)
            (assq-ref reply 'cid)
            (assq-ref reply 'pos))))

(define (%fetch client)
  (GET (ref client'room-url) (ref client'comet-url)
       `((t . ,(sys-time)) (c . ,(~ client'cid)) (p . ,(~ client'pos)) (s . 1))))

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
