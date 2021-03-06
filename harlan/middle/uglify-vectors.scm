(library
  (harlan middle uglify-vectors)
  (export uglify-vectors
    uglify-stmt
    uglify-decl
    uglify-expr)
  (import
    (rnrs)
    (only (harlan front typecheck) free-regions-type)
    (elegant-weapons helpers)
    (elegant-weapons sets))

(define (remove-dups ls)
  (cond
   ((null? ls) `())
   ((memq (car ls) (cdr ls))
    (remove-dups (cdr ls)))
   (else (cons (car ls) (remove-dups (cdr ls))))))

(define vector-length-offset '(int 8))

(define (uglify-vector-ref t e i region)
  `(vector-ref
    ,(remove-regions t)
    (region-ref
     (ptr ,(remove-regions t))
     (var (ptr region) ,region)
     (+ ,e ,vector-length-offset))
    ,i))

;; TODO: should this return true for region-allocated ADTs as well?
(define-match region-allocated?
  ((vec ,r ,t) #t)
  (,else #f))

(define (uglify-let-vec t n region)
  (let ((t (if (region-allocated? t) `region_ptr (remove-regions t))))
    `(alloc
      (var (ptr region) ,region)
      (+ (* (sizeof ,t) ,n)
         ;; sizeof int for the length field.
         ,vector-length-offset))))

(define (vector-length-field e region)
  `(deref
    (region-ref
     (ptr int)
     (var (ptr region) ,region)
     ,e)))

(define-match extract-regions
  ;;((fn (,[t*] ...) -> ,[t])
  ;; (append (apply append t*) t))
  (,else (free-regions-type else)))

(define (remove-regions t)
  (match t
    ((vec ,r ,[t]) `(vec ,t))
    ((adt ,n ,r) `(adt ,n))
    ((fn (,[t*] ...) -> ,[t]) `(fn ,t* -> ,t))
    ((ptr ,[t]) `(ptr ,t))
    ((struct (,x* ,[t*]) ...)
     `(struct (,x* ,t*) ...))
    ((union (,x* ,[t*]) ...)
     `(union (,x* ,t*) ...))
    (,else else)))

(define-match uglify-vectors
  ((module ,[uglify-decl -> decl*] ...)
   `(module . ,decl*)))

(define-match uglify-decl
  ((fn ,name ,args (fn ,arg-t -> ,rt)
       ,[uglify-stmt -> s sr*])
   (let ((all-regions (free-regions-type `(fn ,arg-t -> ,rt)))
         (arg-t (map remove-regions arg-t))
         (rt (remove-regions rt)))
     `(fn ,name
          (,@args ,@all-regions)
          (fn (,@arg-t
            ,@(map (lambda (_) `(ptr region)) all-regions))
           -> ,rt)
          ,s)))
  ((typedef ,name ,t) `(typedef ,name ,(remove-regions t)))
  ((extern ,name ,args -> ,t)
   `(extern ,name ,args -> ,t)))

(define-match (uglify-let finish)
  (() (values finish `()))
  (((,x (vec ,r ,t)
        (make-vector ,t ,r ,[uglify-expr -> n r*]))
    . ,[(uglify-let finish) -> rest rr*])
   (let* ((length (gensym (symbol-append x '_length)))
          (vv (uglify-let-vec t `(var int ,length) r))
          (xt (remove-regions `(vec ,r ,t))))
     (values
      `(let ((,length int ,n))
         (let ((,x ,xt ,vv))
           ,(make-begin
             `((if (= (int 0) (cast int (var ,xt ,x)))
                   (error allocation-failure))
               (set! ,(vector-length-field `(var ,xt ,x) r)
                     (var int ,length))
               ,rest))))
      (append r* rr*))))
  (((,x ,t ,[uglify-expr -> e er*])
    . ,[(uglify-let finish) -> rest rr*])
   (assert (not (and (pair? e) (eq? (car e) 'make-vector))))
   (values `(let ((,x ,(remove-regions t) ,e))
              ,rest)
           (append er* rr*)))
  (((,x ,t)  . ,[(uglify-let finish) -> rest rr*])
   (values `(let ((,x ,(remove-regions t))) ,rest)
           rr*)))

(define-match uglify-stmt
  ((error ,x) (values `(error ,x) '()))
  ((let ,b ,[s r*])
   (let-values (((ans ar*) ((uglify-let s) b)))
     (values ans (append r* ar*))))
  ((let-region (,r ...) ,[stmt r*])
   (values
    `(let-region (,r ...) ,stmt)
    r*))
  ((begin ,[stmt* r**] ...)
   (values (make-begin stmt*)
           (apply append r**)))
  ((if ,[uglify-expr -> t tr*] ,[c cr*])
   (values `(if ,t ,c)
           (append tr* cr*)))
  ((if ,[uglify-expr -> t tr*] ,[c cr*] ,[a ar*])
   (values `(if ,t ,c ,a)
           (append tr* cr* ar*)))
  ((while ,[uglify-expr -> e er*] ,[s sr*])
   (values `(while ,e ,s)
           (append er* sr*)))
  ((for (,i ,[uglify-expr -> start startr*]
            ,[uglify-expr -> end endr*]
            ,[uglify-expr -> step stepr*])
     ,[stmt sr*])
   (values `(for (,i ,start ,end ,step) ,stmt)
           (append startr* endr* stepr* sr*)))
  ((set! ,[uglify-expr -> lhs lr*]
         ,[uglify-expr -> rhs rr*])
   (values `(set! ,lhs ,rhs) (append lr* rr*)))
  ((return)
   (values `(return) `()))
  ((return ,[uglify-expr -> e r*])
   (values `(return ,e) r*))
  ((assert ,[uglify-expr -> e r*])
   (values `(assert ,e) r*))
  ((print ,[uglify-expr -> e* r**] ...)
   (values `(print . ,e*)
           (apply append r**)))
  ((kernel
     ,t
     (,[uglify-expr -> dims dr**] ...)
     (free-vars . ,fv*)
     ,[stmt sr*])
   (let ((regions (remove-dups
                   (apply append sr*
                          (map extract-regions
                               (map cadr fv*))))))
     (values
      `(kernel ,dims
               (free-vars
                ,@(map (lambda (fv) `(,(car fv)
                                 ,(remove-regions (cadr fv))))
                       fv*)
                ,@(map (lambda (r) `(,r (ptr region))) regions))
               ,stmt)
      (apply append sr* dr**))))
  ((do ,[uglify-expr -> e r*])
   (values `(do ,e) r*)))

(define-match uglify-expr
  ((error ,x) (values `(error ,x) '()))
  ((,t ,n)
   (guard (scalar-type? t))
   (values `(,(remove-regions t) ,n) `()))
  ((var ,tx ,x)
   (values `(var ,(remove-regions tx) ,x)
           (extract-regions tx)))
  ((int->float ,[e r*])
   (values `(cast float ,e) r*))
  ((float->int ,[e r*])
   (values `(cast int ,e) r*))
  ((call ,[name nr*] ,[args ar**] ...)
   (values `(call ,name
                  ,@args
                  . ,(map (lambda (r) `(var (ptr region) ,r)) nr*))
           (apply append nr* ar**)))
  ((c-expr ,t ,name)
   (values `(c-expr ,(remove-regions t) ,name) `()))
  ((if ,[test tr*] ,[conseq cr*] ,[alt ar*])
   (values `(if ,test ,conseq ,alt)
           (append tr* cr* ar*)))
  ((not ,[e r])
   (values `(not ,e) r))
  ((,op ,[lhs lr*] ,[rhs rr*])
   (guard (or (binop? op) (relop? op)))
   (values `(,op ,lhs ,rhs)
           (append lr* rr*)))
  ((vector-ref ,t ,[e er*] ,[i ir*])
   (begin
     (assert (not (null? er*)))
     (values (uglify-vector-ref t e i (car er*))
             (append er* ir*))))
  ((unsafe-vec-ptr (ptr ,t) ,[v r*])
   (values `(addressof ,(uglify-vector-ref t v `(int 0) (car r*)))
           (append r*)))
  ((length ,[e r*])
   (begin
     (assert (not (null? r*)))
     (values (vector-length-field e (car r*)) r*)))
  ((addressof ,[expr r*])
   (values `(addressof ,expr) r*))
  ((field ,[e r] ,x)
   (values `(field ,e ,x) r))
  ((empty-struct) (values '(empty-struct) '()))
  ((box ,r ,t)
   (values `(alloc (var (ptr region) ,r) (sizeof ,(remove-regions t)))
           (list r)))
  ((unbox ,t ,r ,[e r*])
   (values
    `(deref (region-ref (ptr ,(remove-regions t)) (var (ptr region) ,r) ,e))
    (cons r r*)))
  ((deref ,[expr r*])
   (values `(deref ,expr) r*)))

)
