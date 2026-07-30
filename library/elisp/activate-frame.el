;; The activate half of a tk9wm emacs button — ONE self-contained
;; round-trip: the daemon decides and reports a verdict string for the
;; WM's log.
;;
;; API (the WM wraps this file's form in a let providing both):
;;   tk9wm-name  the frame's name, a string
;;   tk9wm-fix   a function of no arguments: the button's eval, run
;;               inside the frame on every activation (a no-op
;;               function when the button carries none)
;;
;; The eval rides EVERY activation — the frame may have wandered off
;; to other work, and the button means "back here".  A smarter policy
;; ("stay put when already on a related buffer") is the eval's own
;; business: it runs inside the frame and can ask where it is.
;;
;; The frame is found by name over (frame-list) — never nil (the
;; daemon's selected frame follows input across displays) and never a
;; bare outer-window-id (ids collide between X servers); both
;; measured.  A tty frame is put on top of its terminal with
;; select-frame-set-input-focus plus a redisplay — THAT is what moves
;; tty-top-frame; bare raise-frame does not (measured).  A named frame
;; that is GONE, with exactly one tty terminal alive to rebuild on, is
;; recreated there — the C-x 5 2 case: the user opened another frame
;; in that terminal and closed ours.  Anything else ends in a
;; sentence, not a hang.
(let* ((nf (seq-find (lambda (f)
                       (equal (frame-parameter f 'name) tk9wm-name))
                     (frame-list)))
       (terms (delete-dups
               (delq nil (mapcar (lambda (f)
                                   (and (frame-parameter f 'tty)
                                        (frame-terminal f)))
                                 (frame-list))))))
  (cond
   (nf
    (when (frame-parameter nf 'tty)
      (select-frame-set-input-focus nf)
      (redisplay t))
    (with-selected-frame nf (funcall tk9wm-fix))
    (if (frame-parameter nf 'tty) "raised" "gui"))
   ((= (length terms) 1)
    (let ((f (make-frame (list (cons 'terminal (car terms))
                               (cons 'name tk9wm-name)))))
      (select-frame-set-input-focus f)
      (redisplay t)
      (with-selected-frame f (funcall tk9wm-fix))
      "rebuilt"))
   (t (format "frame %s missing, %d tty terminals to rebuild on"
              tk9wm-name (length terms)))))
