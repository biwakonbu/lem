(in-package :lem)

(defun char-before-2 ()
  (char-before 2))

(defun char-before-3 ()
  (char-before 3))

(defmacro flet-aliases (aliases &body body)
  (let ((gargs (gensym "args")))
    `(flet ,(mapcar (lambda (alias)
                      (assert (= 2 (length alias)))
                      `(,(car alias) (&rest ,gargs)
                         (apply #',(cadr alias) ,gargs)))
              aliases)
       ,@body)))

(defmacro define-dir-functions ((forward-name backward-name)
                                parms aliases &body body)
  `(progn
    (flet ((forward-p () t)
           (backward-p () nil))
      (defun ,forward-name ,parms ,@body))
    (flet ((forward-p () nil)
           (backward-p () t))
      (flet-aliases ,aliases
        (defun ,backward-name ,parms ,@body)))))

(define-dir-functions (skip-chars-forward skip-chars-backward)
  (pred &optional not-p)
  ((following-char preceding-char)
   (next-char prev-char))
  (do ()
      ((if (funcall pred (following-char))
         not-p
         (not not-p))
       t)
    (unless (next-char 1)
      (return))))

(defun skip-space-forward ()
  (skip-chars-forward 'syntax-space-char-p))

(defun skip-space-backward ()
  (skip-chars-backward 'syntax-space-char-p))

(defun skip-until-open-paren-forward ()
  (skip-chars-forward 'syntax-open-paren-char-p t))

(defun skip-until-closed-paren-backward ()
  (skip-chars-backward 'syntax-closed-paren-char-p t))

(defun escape-p (before-1 before-2)
  (and (syntax-escape-char-p before-1)
       (not (syntax-escape-char-p before-2))))

(defun escape-forward-p ()
  (escape-p (preceding-char) (char-before-2)))

(defun escape-backward-p ()
  (escape-p (char-before-2) (char-before-3)))

(define-dir-functions (forward-list-1 backward-list-1) ()
  ((skip-until-open-paren-forward skip-until-closed-paren-backward)
   (following-char preceding-char)
   (syntax-pair-closed-paren syntax-pair-open-paren)
   (preceding-char char-before-2)
   (char-before-2 char-before-3)
   (forward-list-1 backward-list-1)
   (prev-char next-char)
   (next-char prev-char)
   (skip-string-forward skip-string-backward)
   (escape-forward-p escape-backward-p))
  (skip-until-open-paren-forward)
  (let* ((paren-char (following-char))
         (goal-char (syntax-pair-closed-paren paren-char))
         (point (point)))
    (do () (nil)
        (unless (next-char 1)
          (point-set point)
          (return))
      (unless (escape-forward-p)
        (let ((c (following-char)))
          (cond
           ((eql c paren-char)
            (forward-list-1)
            (prev-char 1))
           ((eql c goal-char)
            (next-char 1)
            (do ()
                ((not (and (backward-p)
                           (syntax-expr-prefix-char-p
                            (following-char)))))
              (next-char 1))
            (return t))
           ((syntax-string-quote-char-p c)
            (skip-string-forward)
            (prev-char 1))))))))

(define-key *global-keymap* "M-C-n" 'forward-list)
(defcommand forward-list (n) ("p")
  (dotimes (_ n t)
    (unless (forward-list-1)
      (return))))

(define-key *global-keymap* "M-C-p" 'backward-list)
(defcommand backward-list (n) ("p")
  (dotimes (_ n t)
    (unless (backward-list-1)
      (return))))

(define-dir-functions (skip-string-forward skip-string-backward) ()
  ((skip-chars-forward skip-chars-backward)
   (following-char preceding-char)
   (next-char prev-char)
   (preceding-char char-before-2)
   (char-before-2 char-before-3)
   (escape-forward-p escape-backward-p))
  (skip-chars-forward 'syntax-string-quote-char-p t)
  (let ((goal-char (following-char)))
    (do () (nil)
      (unless (next-char 1)
        (return))
      (unless (escape-forward-p)
        (when (eql (following-char) goal-char)
          (next-char 1)
          (return t))))))

(define-dir-functions (skip-symbol-forward skip-symbol-backward) ()
  ((next-char prev-char)
   (following-char preceding-char)
   (preceding-char char-before-2)
   (char-before-2 char-before-3)
   (escape-forward-p escape-backward-p))
  (do () (nil)
    (unless (next-char 1)
      (return))
    (let ((c (following-char)))
      (cond
       ((escape-forward-p))
       ((not
         (or
          (syntax-expr-prefix-char-p c)
          (syntax-escape-char-p c)
          (syntax-symbol-char-p c)))
        (return t))))))

(defun start-sexp-p (c)
  (or (syntax-open-paren-char-p c)
      (and (syntax-expr-prefix-char-p c)
           (syntax-open-paren-char-p (char-after 1)))
      (and (syntax-expr-prefix-char-p c)
           (syntax-expr-prefix-char-p (char-after 1))
           (syntax-open-paren-char-p (char-after 2)))))

(define-dir-functions (%forward-sexp %backward-sexp) ()
  ((skip-space-forward skip-space-backward)
   (start-sexp-p syntax-closed-paren-char-p)
   (syntax-closed-paren-char-p syntax-open-paren-char-p)
   (following-char preceding-char)
   (preceding-char char-before-2)
   (char-before-2 char-before-3)
   (forward-list-1 backward-list-1)
   (skip-string-forward skip-string-backward)
   (skip-symbol-forward skip-symbol-backward)
   (next-char prev-char)
   (escape-forward-p escape-backward-p))
  (skip-space-forward)
  (let ((c (following-char)))
    (when (escape-forward-p)
      (next-char 1)
      (setq c (following-char)))
    (cond
     ((start-sexp-p c)
      (forward-list-1))
     ((syntax-closed-paren-char-p c)
      nil)
     ((syntax-string-quote-char-p c)
      (skip-string-forward))
     (t
      (skip-symbol-forward)))))

(define-key *global-keymap* "M-C-f" 'forward-sexp)
(defcommand forward-sexp (&optional (n 1)) ("p")
  (dotimes (_ n t)
    (unless (%forward-sexp)
      (return))))

(define-key *global-keymap* "M-C-b" 'backward-sexp)
(defcommand backward-sexp (&optional (n 1)) ("p")
  (dotimes (_ n t)
    (unless (%backward-sexp)
      (return))))

(define-key *global-keymap* "M-C-d" 'down-list)
(defcommand down-list (&optional (n 1)) ("p")
  (block outer
    (dotimes (_ n t)
      (let ((point (point)))
        (do () (nil)
          (let ((c (following-char)))
            (cond
             ((and
               (syntax-open-paren-char-p c)
               (not (escape-forward-p)))
              (next-char 1)
              (return t))
             ((and (syntax-string-quote-char-p c)
                (not (escape-forward-p)))
              (skip-string-forward))
             ((or
               (syntax-closed-paren-char-p c)
               (not (next-char 1)))
              (point-set point)
              (return-from outer nil)))))))))

(define-key *global-keymap* "M-C-u" 'up-list)
(defcommand up-list (&optional (n 1)) ("p")
  (block outer
    (let ((point (point)))
    (dotimes (_ n t)
      (do () (nil)
        (let ((c (preceding-char)))
          (cond
           ((and
             (syntax-closed-paren-char-p c)
             (not (escape-backward-p)))
            (unless (backward-list-1)
              (point-set point)
              (return-from outer nil)))
           ((and
             (syntax-open-paren-char-p c)
             (not (escape-backward-p)))
            (prev-char 1)
            (return t))
           ((and
             (syntax-string-quote-char-p c)
             (not (escape-backward-p)))
            (skip-string-backward))
           ((not (prev-char 1))
            (point-set point)
            (return-from outer nil)))))))))

(define-key *global-keymap* "M-C-a" 'beginning-of-defun)
(defcommand beginning-of-defun (&optional (n 1)) ("p")
  (dotimes (_ n t)
    (if (up-list 1)
      (do () ((not (up-list 1)) t))
      (unless (backward-sexp 1)
        (return nil)))))

(define-key *global-keymap* "M-C-e" 'end-of-defun)
(defcommand end-of-defun (&optional (n 1)) ("p")
  (dotimes (_ n t)
    (do () ((not (up-list 1)) t))
    (unless (forward-sexp 1)
      (return nil))))

(define-key *global-keymap* "M-C-@" 'mark-sexp)
(defcommand mark-sexp () ()
  (let ((point (point)))
    (forward-sexp 1)
    (mark-set)
    (point-set point)))

(define-key *global-keymap* "M-C-k" 'kill-sexp)
(defcommand kill-sexp (&optional (n 1)) ("p")
  (mark-sexp)
  (kill-region (region-beginning) (region-end)))

(define-key *global-keymap* "M-C-t" 'transpose-sexps)
(defcommand transpose-sexps () ()
  (let ((point (point)))
    (or
     (block outer
       (let (left right)
         (unless (forward-sexp 1)
           (return-from outer nil))
         (unless (backward-sexp 2)
           (return-from outer nil))
         (kill-sexp 1)
         (setq *kill-new-flag* t)
         (delete-while-whitespaces)
         (setq *kill-new-flag* t)
         (kill-sexp 1)
         (yank 1)
         (yank 2)
         (yank 3)
         (setq *kill-new-flag* t)
         t))
     (progn (point-set point)
       nil))))