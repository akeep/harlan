(library
  (harlan middle returnify-kernels)
  (export returnify-kernels)
  (import (rnrs) (elegant-weapons helpers)
    (harlan helpers))
  
(define-match returnify-kernels
  ((module ,[returnify-kernel-decl -> fn*] ...)
   `(module . ,fn*)))

(define-match returnify-kernel-decl
  ((fn ,name ,args ,type ,[returnify-kernel-stmt -> stmt])
   `(fn ,name ,args ,type ,stmt))
  ((extern ,name ,args -> ,type)
   `(extern ,name ,args -> ,type)))

(define-match returnify-kernel-stmt
  ((print . ,expr*) `(print . ,expr*))
  ((assert ,expr) `(assert ,expr))
  ((set! ,x ,e) `(set! ,x ,e))
  ((error ,x) `(error ,x))
  ((begin ,[stmt*] ...)
   `(begin . ,stmt*))
  ((if ,test ,[conseq])
   `(if ,test ,conseq))
  ((if ,test ,[conseq] ,[alt])
   `(if ,test ,conseq ,alt))
  ((return) `(return))
  ((return ,expr) `(return ,expr))
  ((while ,expr ,[body])
   `(while ,expr ,body))
  ((for ,b ,[body])
   `(for ,b ,body))
  ((let ((,id ,t ,e) ...) ,[stmt])
   ((returnify-kernel-let stmt) `((,id ,t ,e) ...)))
  ((do ,expr) `(do ,expr)))

(define-match returnify-kernel-expr
  ((begin ,[returnify-kernel-stmt -> stmt*] ,[expr])
   `(begin ,@stmt* ,expr))
  ((let ((,id ,t ,e) ...) ,[expr])
   ((returnify-kernel-let expr) `((,id ,t ,e) ...)))
  (,else else))

(define-match (returnify-kernel-let finish)
  (() finish)
  (((,id ,xt (kernel void ,arg* ,body))
    . ,[(returnify-kernel-let finish) -> rest])
   ;; TODO: we still need to traverse the body
   `(let ((,id ,xt (kernel void ,arg* ,body))) ,rest))
  (((,id ,xt (kernel (vec ,t) ,dims ,arg* ,body))
    . ,[(returnify-kernel-let finish) -> rest])
   (match arg*
     ((((,x* ,tx*) (,xe* ,xet*) ,dim) ...)
      (let ((retvars (map (lambda (_) (gensym 'retval)) dims)))
        `(let ((,id ,xt (make-vector ,t ,(car dims))))
           (begin
             (kernel
              (vec ,t)
              ,dims
              ,(insert-retvars retvars (cons id retvars) 0 t arg*)
              ,((set-retval (shave-type (length dims) `(vec ,t)) (car (reverse retvars))) body))
             ,rest))))))
  (((,id ,t ,expr) . ,[(returnify-kernel-let finish) -> rest])
   `(let ((,id ,t ,expr)) ,rest)))

;; This is stupid
(define (shave-type dim t)
  (if (zero? dim) t (shave-type (- dim 1) (cadr t))))

(define (insert-retvars retvars sources dim t arg*)
  (match arg*
    ((((,x ,tx) (,xs ,ts) ,d) . ,rest)
     (if (<= dim d)
         (cons
          `((,(car retvars) ,t)
            ((var (vec ,t) ,(car sources))
             (vec ,t))
            ,dim)
          (if (null? rest)
              arg*
              (insert-retvars (cdr retvars)
                              (cdr sources)
                              (+ dim 1)
                              (cadr t)
                              arg*)))
         (cons (car arg*)
               (insert-retvars retvars
                               sources
                               dim
                               t
                               (cdr arg*)))))))

(define-match (set-retval t retvar)
  ((begin ,stmt* ... ,[(set-retval t retvar) -> expr])
   `(begin ,@stmt* ,expr))
  ((let ,b ,[(set-retval t retvar) -> expr])
   `(let ,b ,expr))
  (,else `(set! (var ,t ,retvar) ,else)))

;; end library
)

