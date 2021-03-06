(in-package :lem)

(export '(buffer-output-stream
          make-buffer-output-stream
          buffer-output-stream-point
          minibuffer-input-stream
          make-minibuffer-input-stream
          editor-io-stream
          make-editor-io-stream))

(defclass buffer-output-stream (trivial-gray-streams:fundamental-output-stream)
  ((marker
    :initarg :marker
    :accessor buffer-output-stream-marker)
   (interactive-update-p
    :initarg :interactive-update-p
    :accessor buffer-output-stream-interactive-update-p)))

(defun make-buffer-stream-instance (class-name buffer
                                               &optional
                                               point
                                               interactive-update-p)
  (make-instance class-name
                 :marker (make-marker buffer point :kind :left-inserting)
                 :interactive-update-p interactive-update-p))

(defun make-buffer-output-stream (&optional (buffer (current-buffer))
                                            (point (make-min-point))
                                            interactive-update-p)
  (make-buffer-stream-instance 'buffer-output-stream
                               buffer point interactive-update-p))

(defmethod trivial-gray-streams::close ((stream buffer-output-stream) &key abort)
  (declare (ignore abort))
  (delete-marker (buffer-output-stream-marker stream))
  t)

(defun buffer-output-stream-point (stream)
  (marker-point (buffer-output-stream-marker stream)))

(defmethod stream-element-type ((stream buffer-output-stream))
  'line)

(defmethod trivial-gray-streams:stream-line-column ((stream buffer-output-stream))
  (marker-charpos (buffer-output-stream-marker stream)))

(defun buffer-output-stream-refresh (stream)
  (when (buffer-output-stream-interactive-update-p stream)
    (let ((buffer (marker-buffer (buffer-output-stream-marker stream)))
          (point (marker-point (buffer-output-stream-marker stream))))
      (display-buffer buffer)
      (dolist (window (get-buffer-windows buffer))
        (point-set point (window-buffer window)))
      (redraw-display)))
  nil)

(defmethod trivial-gray-streams:stream-fresh-line ((stream buffer-output-stream))
  (unless (zerop (marker-charpos (buffer-output-stream-marker stream)))
    (trivial-gray-streams:stream-terpri stream)))

(defmethod trivial-gray-streams:stream-write-byte ((stream buffer-output-stream) byte)
  (trivial-gray-streams:stream-write-char stream (code-char byte)))

(defmethod trivial-gray-streams:stream-write-char ((stream buffer-output-stream) char)
  (prog1 char
    (insert-char/marker (buffer-output-stream-marker stream)
                        char)))

(defun %write-string-to-buffer-stream (stream string start end &key)
  (insert-string/marker (buffer-output-stream-marker stream)
                        (subseq string start end))
  string)

(defun %write-octets-to-buffer-stream (stream octets start end &key)
  (let ((octets (subseq octets start end)))
    (loop :for c :across octets :do
       (trivial-gray-streams:stream-write-byte stream c))
    octets))

(defmethod trivial-gray-streams:stream-write-sequence
    ((stream buffer-output-stream)
     sequence start end &key)
  (etypecase sequence
    (string
     (%write-string-to-buffer-stream stream sequence start end))
    ((array (unsigned-byte 8) (*))
     (%write-octets-to-buffer-stream stream sequence start end))))

(defmethod trivial-gray-streams:stream-write-string
    ((stream buffer-output-stream)
     (string string)
     &optional (start 0) end)
  (%write-string-to-buffer-stream stream string start end))

(defmethod trivial-gray-streams:stream-terpri ((stream buffer-output-stream))
  (prog1 (insert-char/marker (buffer-output-stream-marker stream)
                             #\newline)
    (buffer-output-stream-refresh stream)))

(defmethod trivial-gray-streams:stream-finish-output ((stream buffer-output-stream))
  (buffer-output-stream-refresh stream))

(defmethod trivial-gray-streams:stream-force-output ((stream buffer-output-stream))
  (buffer-output-stream-refresh stream))

#-(and)
(defmethod trivial-gray-streams:clear-output ((stream buffer-output-stream))
  )


(defclass minibuffer-input-stream (trivial-gray-streams:fundamental-input-stream)
  ((queue
    :initform nil
    :initarg :queue
    :accessor minibuffer-input-stream-queue)))

(defun make-minibuffer-input-stream ()
  (make-instance 'minibuffer-input-stream :queue nil))

(defmethod trivial-gray-streams:stream-read-char ((stream minibuffer-input-stream))
  (let ((c (pop (minibuffer-input-stream-queue stream))))
    (cond ((null c)
           (let ((string
                  (handler-case (values (minibuf-read-string "") t)
                    (editor-abort ()
                                  (setf (minibuffer-input-stream-queue stream) nil)
                                  (return-from trivial-gray-streams:stream-read-char :eof)))))
             (setf (minibuffer-input-stream-queue stream)
                   (nconc (minibuffer-input-stream-queue stream)
                          (coerce string 'list)
                          (list #\newline))))
           (trivial-gray-streams:stream-read-char stream))
          ((eql c #\eot)
           :eof)
          (c))))

(defmethod trivial-gray-streams:stream-unread-char ((stream minibuffer-input-stream) char)
  (push char (minibuffer-input-stream-queue stream))
  nil)

(defmethod trivial-gray-streams:stream-read-char-no-hang ((stream minibuffer-input-stream))
  (trivial-gray-streams:stream-read-char stream))

(defmethod trivial-gray-streams:stream-peek-char ((stream minibuffer-input-stream))
  (let ((c (trivial-gray-streams:stream-read-char stream)))
    (prog1 c
      (trivial-gray-streams:stream-unread-char stream c))))

(defmethod trivial-gray-streams:stream-listen ((stream minibuffer-input-stream))
  (let ((c (trivial-gray-streams:stream-read-char-no-hang stream)))
    (prog1 c
      (trivial-gray-streams:stream-unread-char stream c))))

(defmethod trivial-gray-streams:stream-read-line ((stream minibuffer-input-stream))
  (minibuf-read-string ""))

(defmethod trivial-gray-streams:stream-clear-input ((stream minibuffer-input-stream))
  nil)

(defclass editor-io-stream (buffer-output-stream minibuffer-input-stream)
  ())

(defun make-editor-io-stream (buffer &optional point interactive-update-p)
  (make-buffer-stream-instance 'editor-io-stream
                               buffer point interactive-update-p))
