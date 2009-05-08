;;;
;;; Some common routines for chaton scripts
;;;
(define-module chaton
  (use srfi-1)
  (use srfi-13)
  (use text.html-lite)
  (use text.tree)
  (use file.util)
  (use util.match)
  (use gauche.fcntl)
  (use gauche.sequence)
  (export chaton-render
          chaton-render-from-file
          chaton-with-shared-locking
          chaton-with-exclusive-locking))
(select-module chaton)

(define *archivepath* "@@httpd-url@@@@url-path@@a/")

;;;
;;;  Entries
;;;

;; es : ((<nick> (<sec> <nsec>) <text> <ipaddr>) ...)
;; last-state : (<chatter> <ipaddr> <timestamp>)
;; returns <text-tree> and new-state
(define (chaton-render es last-state)
  (map-accum chaton-render-1 (ensure-state last-state) es))

;; render from file, starting from POS.
;; returns <text-tree>, new-state, and new POS.
(define (chaton-render-from-file file pos last-state)
  (receive (lines pos) (read-diff file pos)
    (receive (tree new-state)
        (chaton-render (safe-lines->sexps lines) (ensure-state last-state))
      (values tree new-state pos))))

;;;
;;;  Rendering
;;;

(define (ensure-state last-state) ; bridge to support backward compat. 
  (match last-state
    [(c i t) last-state]
    [_       '(#f #f #f)]))

(define (make-state chatter ip timestamp) (list chatter ip timestamp))
(define (state-chatter last-state) (car last-state))
(define (state-ip last-state)      (cadr last-state))
(define (state-timestamp last-state) (caddr last-state))

(define (chaton-render-1 entry last-state)
  (match-let1 (nick (sec usec) text . opt) entry
    (let* ([anchor-string (format "entry-~x-~2,'0x" sec usec)]
           [permalink (make-permalink sec anchor-string)]
           [ip (if (pair? opt) (car opt) #f)])
      (values `(,(if (and (equal? nick (state-chatter last-state))
                          (equal? ip (state-ip last-state))
                          (< (abs (- (state-timestamp last-state) sec)) 240))
                   '()
                   (html:div
                    :class "entry-header"
                    (html:span :class "timestamp"
                               (sys-strftime "%Y/%m/%d %T %Z" (sys-localtime sec)))
                    (html:span :class "chatter" nick)))
                ,(html:a :class "permalink-anchor"
                         :id #`"anchor-,anchor-string"
                         :href permalink :name permalink :target "_parent"
                         "#")
                ,(if (#/\n/ text)
                   (html:pre :class "entry-multi" :id anchor-string
                             (safe-text text))
                   (html:div :class "entry-single" :id anchor-string
                             (html:span (safe-text text)))))
              (make-state nick ip sec)))))

(define (make-permalink sec anchor)
  (build-path *archivepath*
              (format "~a#~a"
                      (sys-strftime "%Y/%m/%d" (sys-localtime sec))
                      anchor)))

(define *url-rx*
  #/https?:\/\/(\/\/[^\/?#\s]*)?([^?#\s]*(\?[^#\s]*)?(#\S*)?)/)

(define (safe-text text)
  (let loop ([s text] 
             [r '()])
    (cond [(string-null? s) (reverse r)]
          [(*url-rx* s)
           => (lambda (m)
                (loop (m 'after)
                      (list* (render-url (m 0))
                             (html-escape-string (m 'before))
                             r)))]
          [else (reverse (cons (html-escape-string s) r))])))

(define (render-url url)
  (rxmatch-case url
    [#/\.(?:jpg|gif|png)/ () (render-url-image url)]
    [#/^http:\/\/(\w{2,3}\.youtube\.com)\/watch\?v=(\w{1,12})/ (_ host vid)
     (render-url-youtube host vid)]
    [#/^http:\/\/www\.nicovideo\.jp\/watch\/(\w{1,13})/ (_ vid)
     (render-url-nicovideo vid)]
    [else (render-url-default url)]))

(define (render-url-default url)
  (html:a :href url :rel "nofollow" :class "link-default"
          :onclick "window.open(this.href); return false;"
          (html-escape-string url)))

(define (render-url-image url)
  (html:a :href url :rel "nofollow" :class "link-image hide-while-loading"
          :onclick "window.open(this.href); return false;"
          (html:img :src url :alt url :onload "checkImageSize(this);")))

(define (render-url-youtube host vid)
  (html:object :class "youtube"
               :width "@@embed-youtube-width@@"
               :height "@@embed-youtube-height@@"
               :type "application/x-shockwave-flash"
               :data #`"http://,|host|/v/,|vid|"
               :onload "scrollToBottom();"
               (html:param :name "movie" :value #`"http://,|host|/v/,|vid|")
               (html:param :name "wmode" :value "transparent")))

(define (render-url-nicovideo vid)
  (html:iframe :width "314" :height "176"
               :src #`"http://ext.nicovideo.jp/thumb/,|vid|"
               :scrolling "no" :class "nicovideo"
               :frameborder "0"
               :onload "scrollToBottom();"
               (html:a :href #`"http://www.nicovideo.jp/watch/,|vid|"
                       (html-escape-string
                        #`"http://www.nicovideo.jp/watch/,|vid|"))))

;;;
;;;  Reading datafile
;;;

(define *lockfile* "@@server-data-dir@@lock")

(define (%with-chaton-lock locktype opener closer thunk)
  (ensure-lockfile)
  (let1 p #f
    (unwind-protect
        (begin (set! p (opener *lockfile*))
               (sys-fcntl p F_SETLK (make <sys-flock> :type locktype))
               (thunk))
      (when p
        (sys-fcntl p F_SETLK (make <sys-flock> :type F_UNLCK))
        (closer p)))))

(define (chaton-with-shared-locking thunk)
  (%with-chaton-lock F_RDLCK open-input-file close-input-port thunk))

(define (chaton-with-exclusive-locking thunk)
  (%with-chaton-lock F_WRLCK (cut open-output-file <> :if-exists :overwrite)
                     close-output-port thunk))

(define (ensure-lockfile)
  (unless (file-exists? *lockfile*)
    (with-output-to-file *lockfile*
      (lambda () (display "lockfile\n"))
      :if-does-not-exist :create
      :if-exists #f)))

;; Read the source file from offset START, and returns a list of
;; lines and the updated offset that points the end of the source file.
(define (read-diff source start)
  (chaton-with-shared-locking
   (lambda ()
     (call-with-input-file source
       (lambda (in)
         (cond [in
                (port-seek in start)
                (let1 tx (port->string-list in)
                  (values tx (port-tell in)))]
               [else (values "" 0)]))
       :if-does-not-exist #f))))

(define (safe-read line)
  (guard (e [(<read-error> e) #f]) (read-from-string line)))

(define (safe-lines->sexps lines)
  (filter pair? (map safe-read lines)))


