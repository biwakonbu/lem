(in-package :lem)

(export '(overlay-p
          overlay-start
          overlay-end
          overlay-attribute
          overlay-buffer
          make-overlay
          delete-overlay))

(defclass overlay ()
  ((start
    :initarg :start
    :reader overlay-start)
   (end
    :initarg :end
    :reader overlay-end)
   (attribute
    :initarg :attribute
    :reader overlay-attribute)
   (buffer
    :initarg :buffer
    :reader overlay-buffer)))

(defun overlay-p (x)
  (typep x 'overlay))

(defun make-overlay (start end attribute &optional (buffer (current-buffer)))
  (check-type attribute attribute)
  (let ((overlay
          (make-instance 'overlay
                         :start start
                         :end end
                         :attribute attribute
                         :buffer buffer)))
    (buffer-add-overlay buffer overlay)
    overlay))

(defun delete-overlay (overlay)
  (when (overlay-p overlay)
    (buffer-delete-overlay (overlay-buffer overlay) overlay)))
