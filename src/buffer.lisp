(in-package :lem)

(export '(*undo-limit*
          current-buffer
          buffer
          buffer-p
          buffer-name
          buffer-filename
          buffer-modified-p
          buffer-read-only-p
          buffer-enable-undo-p
          buffer-major-mode
          buffer-minor-modes
          buffer-mark-p
          buffer-nlines
          buffer-overlays
          buffer-truncate-lines
          buffer-enable-undo
          buffer-disable-undo
          buffer-unmark
          buffer-put-property
          buffer-get-char
          buffer-line-string-with-attributes
          buffer-line-string
          map-buffer-lines
          buffer-take-lines
          buffer-erase
          buffer-rename
          buffer-directory
          buffer-undo-boundary
          get-bvar
          clear-buffer-variables
          buffer-add-delete-hook))

(defstruct (line (:constructor %make-line))
  prev
  next
  str
  plist
  %symbol-lifetimes
  %region)

(defmethod print-object ((object line) stream)
  (print-unreadable-object (object stream :identity t)
    (format stream "LINE: string: ~S, plist: ~S"
            (line-str object)
            (line-plist object))))

(defun make-line (prev next str)
  (let ((line (%make-line :next next
                          :prev prev
                          :str str)))
    (when next
      (setf (line-prev next) line))
    (when prev
      (setf (line-next prev) line))
    line))

(defun line-length (line)
  (length (line-str line)))

(defun remove-elements (elements start end)
  (iter:iter (iter:for (start1 end1 value1) iter:in elements)
    (cond
      ((<= start start1 end1 end)
       nil)
      ((<= start start1 end end1)
       (iter:collect (list end end1 value1)))
      ((<= start1 start end1 end)
       (iter:collect (list start1 start value1)))
      ((<= start1 start end end1)
       (iter:collect (list start1 start value1))
       (iter:collect (list end end1 value1)))
      (t
       (iter:collect (list start1 end1 value1))))))

(defun normalization-elements (elements)
  (flet ((start (elt) (first elt))
         (end (elt) (second elt))
         (value (elt) (third elt)))
    (setf elements (sort elements #'< :key #'first))
    (iter:iter (iter:until (null elements))
      (cond
        ((and (eql (end (first elements))
                   (start (second elements)))
              (equal (value (first elements))
                     (value (second elements))))
         (iter:collect (list (start (first elements))
                             (end (second elements))
                             (value (first elements))))
         (setf elements (cddr elements)))
        (t
         (iter:collect (first elements))
         (setf elements (cdr elements)))))))

(defun subseq-elements (elements start end)
  (iter:iter (iter:for (start1 end1 value1) iter:in elements)
    (cond
      ((<= start start1 end1 end)
       (iter:collect (list (- start1 start) (- end1 start) value1)))
      ((<= start start1 end end1)
       (iter:collect (list (- start1 start) (- end start) value1)))
      ((<= start1 start end1 end)
       (iter:collect (list (- start start) (- end1 start) value1)))
      ((<= start1 start end end1)
       (iter:collect (list (- start start) (- end start) value1))))))

(defun put-elements (elements start end value &optional contp)
  (normalization-elements
   (cons (list start end value contp)
         (remove-elements elements start end))))

(defun line-normalization-plist (line)
  (loop :for (key elements) :on (line-plist line) :by #'cddr
        :collect (cons key (normalization-elements elements))))

(defun line-remove-property (line start end key)
  (setf (getf (line-plist line) key)
        (normalization-elements (remove-elements (getf (line-plist line) key) start end))))

(defun line-add-property (line start end key value contp)
  (setf (getf (line-plist line) key)
        (put-elements (getf (line-plist line) key)
                      start end value contp)))

(defun line-clear-property (line key)
  (setf (getf (line-plist line) key) nil))

(defun line-search-property (line key pos)
  (loop :for (start end value contp) :in (getf (line-plist line) key)
        :do (when (if contp
                      (<= start pos end)
                      (<= start pos (1- end)))
              (return value))))

(defun line-search-property-range (line key pos-start pos-end)
  (when (null pos-end)
    (setq pos-end most-positive-fixnum))
  (loop :for (start end value contp) :in (getf (line-plist line) key)
        :do (when (or (<= pos-start start pos-end)
                      (if contp
                          (<= start pos-start end)
                          (<= start pos-start (1- end))))
              (return value))))

(defun line-property-insert-pos (line pos offset)
  (loop :for values :in (cdr (line-plist line)) :by #'cddr
        :do (loop :for v :in values
                  :for (start end) := v
                  :do (cond ((<= pos start)
                             (incf (first v) offset)
                             (incf (second v) offset))
                            ((< start pos end)
                             (incf (second v) offset))
                            ((< pos end)
                             (incf (second v) offset))))))

(defun line-property-insert-newline (line next-line pos)
  (let ((new-plist '()))
    (loop :for plist-rest :on (line-plist line) :by #'cddr
          :do (let ((new-values '())
                    (new-values-last nil))
                (setf (cadr plist-rest)
                      (iter:iter
                        (iter:for elt iter:in (cadr plist-rest))
                        (iter:for (start end value) iter:next elt)
                        (cond ((<= pos start)
                               (let ((new-elt (list (list (- start pos) (- end pos) value))))
                                 (cond
                                   (new-values-last
                                    (setf (cdr new-values-last) new-elt)
                                    (setf new-values-last (cdr new-values-last)))
                                   (t
                                    (setf new-values new-elt)
                                    (setf new-values-last new-elt)))))
                              ((<= pos end)
                               (iter:collect (list start pos value)))
                              (t
                               (iter:collect elt)))))
                (unless (null new-values)
                  (setf (getf new-plist (car plist-rest)) new-values))))
    (setf (line-plist next-line) new-plist)))

(defun line-property-delete-pos (line pos n)
  (loop :for plist-rest :on (line-plist line) :by #'cddr
        :do (setf (cadr plist-rest)
                  (loop :for elt :in (cadr plist-rest)
                        :for (start end value) := elt
                        :if (<= pos start end (+ pos n))
                        :do (progn)
                        :else :if (<= pos (+ pos n) start)
                        :collect (list (- start n) (- end n) value)
                        :else :if (< pos start (+ pos n))
                        :collect (list pos (- end n) value)
                        :else :if (<= start pos (+ pos n) end)
                        :collect (list start (- end n) value)
                        :else :if (<= start pos end (+ pos n))
                        :collect (list start pos value)
                        :else
                        :collect elt))))

(defun line-property-delete-line (line pos)
  (loop :for plist-rest :on (line-plist line) :by #'cddr
        :do (setf (cadr plist-rest)
                  (loop :for elt :in (cadr plist-rest)
                        :for (start end value) := elt
                        :if (<= pos start)
                        :do (progn)
                        :else :if (<= pos end)
                        :collect (list start pos value)
                        :else
                        :collect elt
                        ))))

(defun line-free (line)
  (when (line-prev line)
    (setf (line-next (line-prev line))
          (line-next line)))
  (when (line-next line)
    (setf (line-prev (line-next line))
          (line-prev line)))
  (setf (line-prev line) nil
        (line-next line) nil
        (line-str line) nil))

(defun line-step-n (line n step-f)
  (do ((l line (funcall step-f l))
       (i 0 (1+ i)))
      ((= i n) l)))

(defun line-forward-n (line n)
  (line-step-n line n 'line-next))

(defun line-backward-n (line n)
  (line-step-n line n 'line-prev))

(define-class buffer () (current-buffer)
  name
  %filename
  %directory
  %modified-p
  read-only-p
  %enable-undo-p
  major-mode
  minor-modes
  head-line
  tail-line
  cache-line
  cache-linum
  mark-p
  mark-overlay
  mark-marker
  point-marker
  keep-binfo
  nlines
  undo-size
  undo-stack
  redo-stack
  overlays
  markers
  truncate-lines
  external-format
  last-write-date
  delete-hooks
  variables)

(defvar *current-buffer*)

(defun current-buffer () *current-buffer*)

(defun (setf current-buffer) (buffer)
  (check-type buffer buffer)
  (setf *current-buffer* buffer))

(defvar *undo-modes* '(:edit :undo :redo))
(defvar *undo-mode* :edit)
(defvar *undo-limit* 100000)

(defun make-buffer (name &key filename read-only-p (enable-undo-p t))
  (let ((buffer (make-instance 'buffer
                               :name name
                               :%filename filename
                               :%directory (when filename (directory-namestring filename))
                               :read-only-p read-only-p
                               :%enable-undo-p enable-undo-p
                               :major-mode 'fundamental-mode)))
    (buffer-reset buffer)
    (setf (buffer-%modified-p buffer) 0)
    (setf (buffer-undo-size buffer) 0)
    (setf (buffer-undo-stack buffer) nil)
    (setf (buffer-redo-stack buffer) nil)
    (setf (buffer-markers buffer) nil)
    (setf (buffer-truncate-lines buffer) t)
    (setf (buffer-variables buffer) (make-hash-table :test 'equal))
    (setf (buffer-point-marker buffer)
          (make-marker buffer (make-min-point)
                       :name "buffer-point"))
    (add-buffer buffer)
    buffer))

(defun buffer-enable-undo-p (&optional (buffer (current-buffer)))
  (buffer-%enable-undo-p buffer))

(defun buffer-modified-p (&optional (buffer (current-buffer)))
  (/= 0 (buffer-%modified-p buffer)))

(defun buffer-reset (buffer)
  (let ((line (make-line nil nil "")))
    (setf (buffer-head-line buffer) line)
    (setf (buffer-tail-line buffer) line)
    (setf (buffer-cache-line buffer) line)
    (setf (buffer-cache-linum buffer) 1)
    (setf (buffer-mark-p buffer) nil)
    (setf (buffer-mark-overlay buffer) nil)
    (setf (buffer-mark-marker buffer) nil)
    (setf (buffer-keep-binfo buffer) nil)
    (setf (buffer-nlines buffer) 1)
    (setf (buffer-overlays buffer) nil)))

(defun buffer-p (x)
  (typep x 'buffer))

(defmethod print-object ((buffer buffer) stream)
  (format stream "#<BUFFER ~a ~a>"
          (buffer-name buffer)
          (buffer-filename buffer)))

(defun call-buffer-delete-hooks (buffer)
  (mapc #'funcall (buffer-delete-hooks buffer))
  (delete-marker (buffer-point-marker buffer)))

(defun buffer-enable-undo (buffer)
  (setf (buffer-%enable-undo-p buffer) t)
  nil)

(defun buffer-disable-undo (buffer)
  (setf (buffer-%enable-undo-p buffer) nil)
  (setf (buffer-undo-size buffer) 0)
  (setf (buffer-undo-stack buffer) nil)
  (setf (buffer-redo-stack buffer) nil)
  nil)

(defun buffer-filename (&optional (buffer (current-buffer)))
  (buffer-%filename buffer))

(defun (setf buffer-filename) (filename &optional (buffer (current-buffer)))
  (let ((result (probe-file filename)))
    (unless result
      (error "file does not exist: ~A" filename))
    (setf (buffer-%filename buffer) (namestring result))))

(defun buffer-directory (&optional (buffer (current-buffer)))
  (or (buffer-%directory buffer)
      (namestring (uiop:getcwd))))

(defun (setf buffer-directory) (directory &optional (buffer (current-buffer)))
  (let ((result (uiop:directory-exists-p directory)))
    (unless result
      (error "directory does not exist: ~A" directory))
    (setf (buffer-%directory buffer)
          (namestring result))))

(defun buffer-unmark (buffer)
  (setf (buffer-%modified-p buffer) 0))

(defun buffer-put-property (buffer start end key value)
  (with-points (((start-linum start-charpos) start)
                ((end-linum end-charpos) end))
    (let ((line (buffer-get-line buffer start-linum)))
      (cond ((= start-linum end-linum)
             (line-add-property line start-charpos end-charpos key value nil))
            (t
             (line-add-property line start-charpos (line-length line) key value t)
             (loop :for linum :from (1+ start-linum) :to end-linum
                   :do (setf line (line-next line))
                   :do (if (= linum end-linum)
                           (line-add-property line 0 end-charpos key value nil)
                           (line-add-property line 0 (line-length line) key value t))))))))

(defun buffer-remove-property (buffer start end key)
  (with-points (((start-linum start-charpos) start)
                ((end-linum end-charpos) end))
    (let ((line (buffer-get-line buffer start-linum)))
      (cond ((= start-linum end-linum)
             (line-remove-property line start-charpos end-charpos key))
            (t
             (line-remove-property line start-charpos (line-length line) key)
             (loop :for linum :from (1+ start-linum) :to end-linum
                   :for line := (line-next line)
                   :do (if (= linum end-linum)
                           (line-remove-property line 0 end-charpos key)
                           (line-remove-property line 0 (line-length line) key))))))))

(defun buffer-get-property (buffer point key)
  (let ((line (buffer-get-line buffer (point-linum point))))
    (line-search-property line key (point-charpos point))))

(defun buffer-add-overlay (buffer overlay)
  (push overlay (buffer-overlays buffer)))

(defun buffer-delete-overlay (buffer overlay)
  (setf (buffer-overlays buffer)
        (delete overlay (buffer-overlays buffer))))

(defun buffer-add-marker (buffer marker)
  (push marker (buffer-markers buffer)))

(defun buffer-delete-marker (buffer marker)
  (let ((length (length (buffer-markers buffer))))
    (prog1 (setf (buffer-markers buffer)
                 (delete marker (buffer-markers buffer)))
      (assert (/= length (length (buffer-markers buffer)))))))

(defun buffer-mark-cancel (buffer)
  (when (buffer-mark-p buffer)
    (setf (buffer-mark-p buffer) nil)
    (delete-overlay (buffer-mark-overlay buffer))))

(defun buffer-end-point (buffer)
  (make-point (buffer-nlines buffer)
              (line-length (buffer-tail-line buffer))))

(defun %buffer-get-line (buffer linum)
  (cond
   ((= linum (buffer-cache-linum buffer))
    (buffer-cache-line buffer))
   ((> linum (buffer-cache-linum buffer))
    (if (< (- linum (buffer-cache-linum buffer))
           (- (buffer-nlines buffer) linum))
        (line-forward-n
         (buffer-cache-line buffer)
         (- linum (buffer-cache-linum buffer)))
        (line-backward-n
         (buffer-tail-line buffer)
         (- (buffer-nlines buffer) linum))))
   (t
    (if (< (1- linum)
           (- (buffer-cache-linum buffer) linum))
        (line-forward-n
         (buffer-head-line buffer)
         (1- linum))
        (line-backward-n
         (buffer-cache-line buffer)
         (- (buffer-cache-linum buffer) linum))))))

(defun check-linum (buffer linum)
  (unless (<= 1 linum (buffer-nlines buffer))
    (error "invalid line number: ~A" linum)))

(defun check-point (buffer linum charpos)
  (check-linum buffer linum)
  (unless (<= 0 charpos (buffer-line-length buffer linum))
    (error "invalid character position: ~A" charpos)))

(defun buffer-get-line (buffer linum)
  (check-linum buffer linum)
  (let ((line (%buffer-get-line buffer linum)))
    (setf (buffer-cache-linum buffer) linum)
    (setf (buffer-cache-line buffer) line)
    line))

(defun buffer-get-char (buffer linum charpos)
  (let ((line (buffer-get-line buffer linum)))
    (when (line-p line)
      (let* ((str (line-str line))
             (len (length str)))
        (cond
          ((<= 0 charpos (1- len))
           (char str charpos))
          ((= charpos len)
           #\newline))))))

(defun buffer-line-length (buffer linum)
  (line-length (buffer-get-line buffer linum)))

(defun buffer-line-string-with-attributes (buffer linum)
  (let ((line (buffer-get-line buffer linum)))
    (when (line-p line)
      (values (line-str line)
              (getf (line-plist line) :attribute)))))

(defun buffer-line-string (buffer linum)
  (let ((line (buffer-get-line buffer linum)))
    (when (line-p line)
      (line-str line))))

(defun map-buffer (fn buffer &optional start-linum)
  (do ((line (if start-linum
                 (buffer-get-line buffer start-linum)
                 (buffer-head-line buffer))
             (line-next line))
       (linum (or start-linum 1) (1+ linum)))
      ((null line))
    (funcall fn line linum)))

(defun map-buffer-lines (fn buffer &optional start end)
  (let ((head-line
         (if start
             (buffer-get-line buffer start)
             (buffer-head-line buffer))))
    (unless end
      (setq end (buffer-nlines buffer)))
    (do ((line head-line (line-next line))
         (i (or start 1) (1+ i)))
        ((or (null line) (< end i)))
      (funcall fn
               (line-str line)
               (not (line-next line))
               i))))

(defun buffer-take-lines (buffer &optional linum len)
  (unless linum
    (setq linum 1))
  (unless len
    (setq len (buffer-nlines buffer)))
  (let ((strings))
    (map-buffer-lines
     #'(lambda (str eof-p linum)
         (declare (ignore eof-p linum))
         (push str strings))
     buffer
     linum
     (+ linum len -1))
    (nreverse strings)))

(defun buffer-update-mark-overlay (buffer)
  (when (buffer-mark-p buffer)
    (let (start
          end
          (mark-point (marker-point (buffer-mark-marker buffer)))
          (cur-point (current-point)))
      (if (point< mark-point cur-point)
          (setq start mark-point
                end cur-point)
          (setq start cur-point
                end mark-point))
      (when (buffer-mark-overlay buffer)
        (delete-overlay (buffer-mark-overlay buffer)))
      (setf (buffer-mark-overlay buffer)
            (make-overlay start end *mark-overlay-attribute*)))))

(defun check-read-only-buffer (buffer)
  (when (buffer-read-only-p buffer)
    (error 'read-only-error)))

(defun buffer-modify (buffer)
  (ecase *undo-mode*
    ((:edit :redo)
     (incf (buffer-%modified-p buffer)))
    ((:undo)
     (decf (buffer-%modified-p buffer))))
  (buffer-mark-cancel buffer))

(defun push-undo-stack (buffer elt)
  (cond ((<= (+ *undo-limit* (floor (* *undo-limit* 0.3)))
             (buffer-undo-size buffer))
         (setf (buffer-undo-stack buffer)
               (subseq (buffer-undo-stack buffer)
                       0
                       *undo-limit*))
         (setf (buffer-undo-size buffer)
               (1+ (length (buffer-undo-stack buffer)))))
        (t
         (incf (buffer-undo-size buffer))))
  (push elt (buffer-undo-stack buffer)))

(defun push-redo-stack (buffer elt)
  (push elt (buffer-redo-stack buffer)))

(defun push-undo (marker fn)
  (let ((buffer (marker-buffer marker)))
    (when (and (buffer-enable-undo-p buffer)
               (not (ghost-buffer-p buffer)))
      (let* ((point (marker-point marker))
             (elt (lambda ()
                    (funcall fn)
                    point)))
        (ecase *undo-mode*
          (:edit
           (push-undo-stack buffer elt)
           (setf (buffer-redo-stack buffer) nil))
          (:redo
           (push-undo-stack buffer elt))
          (:undo
           (push-redo-stack buffer elt)))))))

(defun buffer-erase (&optional (buffer (current-buffer)))
  (buffer-mark-cancel buffer)
  (dolist (marker (buffer-markers buffer))
    (setf (marker-point marker) (make-min-point)))
  (delete-char/marker (buffer-point-marker buffer) t)
  (buffer-reset buffer)
  t)

(defun buffer-rename (buffer name)
  (check-type buffer buffer)
  (check-type name string)
  (when (get-buffer name)
    (editor-error "Buffer name `~A' is in use" name))
  (setf (buffer-name buffer) name))

(defun buffer-have-file-p (buffer)
  (and (buffer-filename buffer)
       (uiop:file-pathname-p (buffer-filename buffer))))

(defun buffer-undo-1 (buffer)
  (let ((elt (pop (buffer-undo-stack buffer))))
    (when elt
      (let ((*undo-mode* :undo))
        (unless (eq elt :separator)
          (decf (buffer-undo-size buffer))
          (funcall elt))))))

(defun buffer-undo (buffer)
  (push :separator (buffer-redo-stack buffer))
  (when (eq :separator (car (buffer-undo-stack buffer)))
    (pop (buffer-undo-stack buffer)))
  (let ((point nil))
    (loop :for result := (buffer-undo-1 buffer)
          :while result
          :do (setf point result))
    (unless point
      (assert (eq :separator (car (buffer-redo-stack buffer))))
      (pop (buffer-redo-stack buffer)))
    point))

(defun buffer-redo-1 (buffer)
  (let ((elt (pop (buffer-redo-stack buffer))))
    (when elt
      (let ((*undo-mode* :redo))
        (unless (eq elt :separator)
          (funcall elt))))))

(defun buffer-redo (buffer)
  (push :separator (buffer-undo-stack buffer))
  (let ((point nil))
    (loop :for result := (buffer-redo-1 buffer)
          :while result
          :do (setf point result))
    (unless point
      (assert (eq :separator (car (buffer-undo-stack buffer))))
      (pop (buffer-undo-stack buffer)))
    point))

(defun buffer-undo-boundary (&optional (buffer (current-buffer)))
  (unless (eq :separator (car (buffer-undo-stack buffer)))
    (push :separator (buffer-undo-stack buffer))))

(defun get-bvar (name &key (buffer (current-buffer)) default)
  (multiple-value-bind (value foundp)
      (gethash name (buffer-variables buffer))
    (if foundp value default)))

(defun (setf get-bvar) (value name &key (buffer (current-buffer)) default)
  (declare (ignore default))
  (setf (gethash name (buffer-variables buffer)) value))

(defun clear-buffer-variables (&key (buffer (current-buffer)))
  (clrhash (buffer-variables buffer)))

(defun buffer-add-delete-hook (buffer fn)
  (push fn (buffer-delete-hooks buffer))
  fn)
