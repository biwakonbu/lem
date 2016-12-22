(in-package :lem)

(export '(indent
          newline-and-indent
          indent-region))

(defun indent-line (point column)
  (when (minusp column)
    (setf column 0))
  (let ((old-column (point-column point))
        (old-indent-string
         (points-to-string (line-start (copy-marker point :temporary))
                           (with-marker ((point point))
                             (skip-chars-forward (line-start point)
                                                 '(#\space #\tab))
                             point)))
        (new-indent-string
         (if (get-bvar :indent-tabs-mode :default t :buffer (marker-buffer point))
             (multiple-value-bind (div mod)
                 (floor column (tab-size))
               (concatenate 'string
                            (make-string div :initial-element #\tab)
                            (make-string mod :initial-element #\space)))
             (make-string column :initial-element #\space))))
    (cond ((string/= old-indent-string new-indent-string)
           (line-start point)
           (delete-char-at point (length old-indent-string) nil)
           (insert-string-at point new-indent-string)
           (if (< old-column column)
               (skip-chars-forward (line-start point) '(#\space #\tab))
               (move-to-column point
                               (max 0 (+ old-column
                                         (- (string-width new-indent-string)
                                            (string-width old-indent-string)))))))
          ((< old-column column)
           (skip-chars-forward (line-start point) '(#\space #\tab)))))
  t)

(defun calc-indent-default (point)
  (with-marker ((point point))
     (skip-chars-forward (line-offset point -1)
                         '(#\space #\tab))
    (point-column point)))

(define-command indent () ()
  (funcall (get-bvar :calc-indent-function
                     :default #'calc-indent-default)
           (current-marker)))

(define-key *global-keymap* (kbd "C-j") 'newline-and-indent)
(define-key *global-keymap* (kbd "M-j") 'newline-and-indent)
(define-command newline-and-indent (n) ("p")
  (newline n)
  (indent))

(define-command indent-region (start end) ("r")
  (save-excursion
    (apply-region-lines start end 'indent)))