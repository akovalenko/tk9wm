;; The daemon half of the desk's edit door, for the one case that
;; cannot be an argument: putting a file into a frame that already
;; lives inside a given terminal.  Everywhere else the desk hands
;; emacsclient `+LINE FILE` and lets it choose and raise the frame.
;;
;; API (the WM wraps this file's form in a let providing all three):
;;   tk9wm-name  the frame's name, a string
;;   tk9wm-file  the file to visit
;;   tk9wm-line  the line to land on
;;
;; THE FOCUS IS OURS TO ASK FOR (the owner, measured 2026-08-02):
;; emacsclient raises and focuses the frame it visits a FILE in, and
;; does neither for a bare eval — it computes what it was told in
;; whatever frame the display already had, invisibly.  Nothing outside
;; picks the frame up here, so the form says it itself.  On a tty that
;; is also what moves tty-top-frame; a bare raise-frame does not.
;;
;; Found by our own parameter first and by name second, exactly as
;; activate-frame.el does, and for the same reason: a frame may have
;; handed its name back to emacs the moment it was born.
(let ((f (seq-find (lambda (x)
                     (or (equal (frame-parameter x 'tk9wm-frame) tk9wm-name)
                         (equal (frame-parameter x 'name) tk9wm-name)))
                   (frame-list))))
  (if (not f)
      (format "frame %s is gone" tk9wm-name)
    (with-selected-frame f
      (find-file tk9wm-file)
      (goto-line tk9wm-line))
    (select-frame-set-input-focus f)
    (redisplay t)
    "edited"))
