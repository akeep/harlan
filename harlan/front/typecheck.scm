(library
  (harlan front typecheck)
  (export typecheck)
  (import
    (rnrs)
    (util cKanren mk)
    (util cKanren ck)
    (util cKanren typecomp)
    (only (chezscheme) printf pretty-print)
    (harlan compile-opts)
    (util color))

(define-syntax (define-mk x)
  (define trace-mk #f)
  (syntax-case x ()
    ((_ name (lambda (a* ...) body))
     (if trace-mk
         #`(define name
             (lambda (a* ...)
               (fresh ()
                 (project (a* ...)
                   (begin
                     (printf "~s\n" (list 'name a* ...))
                     succeed))
                 body)))
         #`(define name (lambda (a* ...) body))))))

(define-mk pairo
  (lambda (x)
    (fresh (a d)
      (== `(,a . ,d) x))))

(define-mk lookup
  (lambda (env x type)
    (fresh (env^)
      (conde
        ((== `((,x . ,type) . ,env^) env))
        ((fresh (y t)
           (=/= x y)
           (== `((,y . ,t) . ,env^) env)
           (lookup env^ x type)))))))

(define-mk infer-exprs
  (lambda (exprs env type exprso)
    (fresh (expr expro expr* expro*)
      (conde
        ((== exprs '())
         (== exprso '()))
        ((== exprs `(,expr . ,expr*))
         (== exprso `(,expro . ,expro*))
         (infer-expr expr env type expro)
         (infer-exprs expr* env type expro*))))))

(define-mk infer-expr
  (lambda (expr env type expro)
    (conde
      ((fresh (c)
         (== expr `(char ,c))
         (== expro `(char ,c))
         (== type 'char)))
      ((fresh (n)
         (== expr `(num ,n))
         (prefo type '(int float u64))
         (== expro `(,type ,n))))
      ((fresh (n)
         (== expr `(float ,n))
         (== expro `(float ,n))
         (== type 'float)))
      ((fresh (str)
         (== expr `(str ,str))
         (== expro `(str ,str))
         (== type 'str)))
      ((fresh (b)
         (== expr `(bool ,b))
         (== expro `(bool ,b))
         (== type `bool)))
      ((fresh (x)
         (== expr `(var ,x))
         (== expro `(var ,type ,x))
         (lookup env x type)))
      ((fresh (test test^ conseq conseq^ alt alt^)
         (== expr `(if ,test ,conseq ,alt))
         (== expro `(if ,test^ ,conseq^ ,alt^))
         (infer-expr test env 'bool test^)
         (infer-expr conseq env type conseq^)
         (infer-expr alt env type alt^)))
      ((fresh (e* e^* t n)
         (== expr `(vector . ,e*))
         (== expro `(vector ,type . ,e^*))
         (report-backtrack `(vector . ,e*) env)
         (== type `(vec ,t))
         (== n -1)
         (infer-exprs e* env t e^*)))
      ((fresh (t e e^)
         (== expr `(make-vector ,e))
         (== expro `(make-vector ,t ,e^))
         (== type `(vec ,t))
         (infer-expr e env 'int e^)))
      ((fresh (op e e^ t n)
         (== expr `(reduce ,op ,e))
         (== expro `(reduce ,t ,op ,e^))
         (report-backtrack `(reduce ,op ,e) env)
         (conde
           ((== op '+))
           ((== op '*)))
         (prefo type '(int float u64))
         (== `(vec ,type) t)
         (infer-expr e env t e^)))
      ((fresh (e e^ t n)
         (== expr `(length ,e))
         (report-backtrack `(length ,e) env)
         (== expro `(length ,e^))
         (== type 'int)
         (infer-expr e env `(vec ,t) e^)))
      ((fresh (e e^)
         (== expr `(iota ,e))
         (== expro `(iota ,e^))
         (infer-expr e env 'int e^)
         (== type `(vec int))))
      ((fresh (op e1 e2 e1^ e2^ t)
         (== expr `(,op ,e1 ,e2))
         (== expro `(,op ,t ,e1^ ,e2^))
         (conde
           ((== op '<))
           ((== op '<=))
           ((== op '=))
           ((== op '>))
           ((== op '>=)))
         (== type 'bool)
         (prefo t '(int u64 float))
         (report-backtrack `(,op ,e1 ,e2) env)
         (infer-expr e1 env t e1^)
         (infer-expr e2 env t e2^)))
      ((fresh (e1 e2 e1^ e2^ t t^ n)
         (== expr `(= ,e1 ,e2))
         (== expro `(= ,t ,e1^ ,e2^))
         (== type `bool)
         (report-backtrack `(= ,e1 ,e2) env)
         (conde
           ((== t `char))
           ((== t `bool))
           ((== t `(vec ,t^))))
         (infer-expr e1 env t e1^)
         (infer-expr e2 env t e2^)))
      ((fresh (e1 e2 e1^ e2^ op)
         (== expr `(,op ,e1 ,e2))
         (== expro `(,op ,type ,e1^ ,e2^))
         (conde
           ((== op '+))
           ((== op '-))
           ((== op '*))
           ((== op 'mod))
           ((== op '/)))
         (prefo type '(int u64 float))
         (report-backtrack `(,op ,e1 ,e2) env)
         (infer-expr e1 env type e1^)
         (infer-expr e2 env type e2^)))
      ((fresh (e1 e2 e1^ e2^ op t n)
         (== expr `(+ ,e1 ,e2))
         (== expro `(+ ,type ,e1^ ,e2^))
         (report-backtrack `(,op ,e1 ,e2) env)
         (== type `(vec ,t))
         (infer-expr e1 env type e1^)
         (infer-expr e2 env type e2^)))
      ((fresh (e e^)
         (== expr `(int->float ,e))
         (== expro `(int->float ,e^))
         (== type 'float)
         (report-backtrack `(int->float ,e) env)
         (infer-expr e env 'int e^)))
      ((fresh (ve ie ve^ ie^ n)
         (== expr `(vector-ref ,ve ,ie))
         (== expro `(vector-ref ,type ,ve^ ,ie^))
         (report-backtrack `(vector-ref ,ve ,ie) env)
         (infer-expr ie env 'int ie^)
         (infer-expr ve env `(vec ,type) ve^)))
      ((fresh (fn fn-type args arg-types rtype argso)
         (== expr `(call ,fn . ,args))
         (report-backtrack `(call ,fn . ,args) env)
         (== fn-type `(,arg-types -> ,rtype))
         (lookup env fn fn-type)
         (== type rtype)
         (infer-args env args arg-types argso)
         (== expro `(call (var ,fn-type ,fn) . ,argso))))
      ((fresh (e* e*^ rtype)
         (== expr `(begin . ,e*))
         (== expro `(begin . ,e*^))
         (let loop ((e* e*) (e*^ e*^))
           (conde
             ((fresh (e e^)
                (== `(,e) e*)
                (== `(,e^) e*^)
                (infer-expr e env type e^)))
             ((fresh (s s^ rest rest^)
                (== `(,s . ,rest) e*)
                (== `(,s^ . ,rest^) e*^)
                (pairo rest)
                (infer-stmt s env rtype s^)
                (loop rest rest^)))))))
      ((fresh (b b^ e e^ envo)
         (== expr `(let ,b ,e))
         (== expro `(let ,b^ ,e^))
         (infer-let-bindings b b^ env envo)
         (infer-expr e envo type e^)))
      ((fresh (b* body b^* body^ env^ t n)
         (== expr `(kernel ,b* ,body))
         (report-backtrack `(kernel ,b* ,body) env)
         (== type `(vec ,t))
         (== expro `(kernel ,type ,b^* ,body^))
         (infer-kernel-bindings b* b^* env env^ n)
         (infer-expr body env^ t body^))))))

(define-mk report-backtrack
  (lambda (e env)
    (conde
      ((== #f #f))
      ((lambda (a)
         (let ((s (car a)))
           (if (verbose)
               (begin
                 (printf "~aBacktracking in typecheck on ~s in environment:~a\n"
                         (set-color-string 'blue)
                         (walk* e s)
                         (set-color-string 'default))
                 (pretty-print (walk* env s))))
           ((== #f #f) s)))
         (== #f #t)))))

(define-mk infer-args
  (lambda (env args arg-types argso)
    (conde
      ((== args '()) (== argso '()))
      ((fresh (e e* t t* e^ e^*)
         (== args `(,e . ,e*))
         (== arg-types `(,t . ,t*))
         (== argso `(,e^ . ,e^*))
         (infer-expr e env t e^)
         (infer-args env e* t* e^*))))))

(define-mk infer-kernel-bindings
  (lambda (b* b^* env envo n)
    (conde
      ((== '() b*) (== '() b^*) (== env envo))
      ((fresh (x e e^ tx te rest rest^ env^)
         (== `((,x ,e) . ,rest) b*)
         (report-backtrack e env)
         (== `(((,x ,tx) (,e^ ,te)) . ,rest^) b^*)
         (== `(vec ,tx) te)
         (== envo `((,x . ,tx) . ,env^))
         (infer-expr e env te e^)
         (infer-kernel-bindings rest rest^ env env^ n))))))

(define-mk infer-let-bindings
  (lambda (b b^ env envo)
    (conde
      ((== b '()) (== b b^) (== env envo))
      ((fresh (x e e^ rest rest^ env^ type)
         (== b `((,x ,e) . ,rest))
         (== b^ `((,x ,type ,e^) . ,rest^))
         (== envo `((,x . ,type) . ,env^))
         (infer-expr e env type e^)
         (infer-let-bindings rest rest^ env env^))))))

(define-mk infer-stmt
  (lambda (stmt env rtype stmto)
    (conde
      ((fresh (b b^ s s^ envo)
         (== stmt `(let ,b ,s))
         (== stmto `(let ,b^ ,s^))
         (infer-let-bindings b b^ env envo)
         (infer-stmt s envo rtype s^)))
      ((fresh (stmt* stmt*^)
         (== stmt `(begin . ,stmt*))
         (== stmto `(begin . ,stmt*^))
         (infer-stmts stmt* env rtype stmt*^)))
      ((fresh (test test^ conseq conseq^ type)
         (== stmt `(if ,test ,conseq))
         (== stmto `(if ,test^ ,conseq^))
         (infer-expr test env type test^)
         (infer-stmt conseq env rtype conseq^)))
      ((fresh (test test^ conseq conseq^ alt alt^ type)
         (== stmt `(if ,test ,conseq ,alt))
         (== stmto `(if ,test^ ,conseq^ ,alt^))
         (infer-expr test env type test^)
         (infer-stmt conseq env rtype conseq^)
         (infer-stmt alt env rtype alt^)))
      ((fresh (e1 e2 e1^ e2^ t)
         (== stmt `(set! ,e1 ,e2))
         (== stmto `(set! ,e1^ ,e2^))
         (infer-expr e1 env t e1^)
         (infer-expr e2 env t e2^)))
      ((fresh (e1 e2 e3 e1^ e2^ e3^ t n)
         (== stmt `(vector-set! ,e1 ,e2 ,e3))
         (== stmto `(vector-set! ,t ,e1^ ,e2^ ,e3^))
         (infer-expr e1 env `(vec ,t) e1^)
         (infer-expr e2 env 'int e2^)
         (infer-expr e3 env t e3^)))
      ((fresh (e e^ type)
         (== stmt `(print ,e))
         (== stmto `(print ,type ,e^))
         (infer-expr e env type e^)))
      ((fresh (e e^ op op^ type)
         (== stmt `(print ,e ,op))
         (== stmto `(print ,type ,e^ ,op^))
         (infer-expr e env type e^)
         (infer-expr op env `(ptr ofstream) op^)))
      ((fresh (file fileo data datao)
         (== stmt `(write-pgm ,file ,data))
         (== stmto `(write-pgm ,fileo ,datao))
         (infer-expr file env 'str fileo)
         (infer-expr data env '(vec (vec int)) datao)))
      ((fresh (e e^)
         (== stmt `(assert ,e))
         (== stmto `(assert ,e^))
         (infer-expr e env 'bool e^)))
      ((fresh (e e^)
         (conde
           ((== stmt `(return ,e))
            (== stmto `(return ,e^))
            (infer-expr e env rtype e^))
           ((== stmt `(return))
            (== stmto `(return))
            (== rtype 'void)))))
      ((fresh (e e^ type)
         (== stmt `(do ,e))
         (== stmto `(do ,e^))
         (infer-expr e env type e^)))
      ((fresh (x start start^ end end^ s s^)
         (== stmt `(for (,x ,start ,end) ,s))
         (== stmto `(for (,x ,start^ ,end^) ,s^))
         (infer-expr start env 'int start^)
         (infer-expr end env 'int end^)
         (infer-stmt s `((,x . int) . ,env) rtype s^)))
      ((fresh (e e^ s s^)
         (== stmt `(while ,e ,s))
         (== stmto `(while ,e^ ,s^))
         (infer-expr e env 'bool e^)
         (infer-stmt s env rtype s^))))))

(define-mk infer-stmts
  (lambda (stmts env rtype stmtso)
    (conde
      ((== stmts '()) (== stmts stmtso))
      ((fresh (stmt stmt* stmt^ stmt*^)
         (== stmts `(,stmt . ,stmt*))
         (== stmtso `(,stmt^ . ,stmt*^))
         (report-backtrack `(,stmt . ,stmt*) env)
         (infer-stmt stmt env rtype stmt^)
         (infer-stmts stmt* env rtype stmt*^))))))

(define-mk infer-fn-args
  (lambda (args arg-types env envo)
    (conde
      ((== args '()) (== arg-types '()) (== env envo))
      ((fresh (a at rest restt env^)
         (== args `(,a . ,rest))
         (== arg-types `(,at . ,restt))
         (== envo `((,a . ,at) . ,env^))
         (infer-fn-args rest restt env env^))))))

(define-mk infer-decl*
  (lambda (decl* declo* env)
    (conde
      ((== '() decl*) (== '() declo*))
      ((fresh (decl declo rest resto name type)
         (== decl* `(,decl . ,rest))
         (conde
           ((fresh (stmt stmto args arg-types rtype env^)
              (== decl `(fn ,name ,args ,stmt))
              (== declo `(fn ,name ,args ,type ,stmto))
              (== type `(,arg-types -> ,rtype))
              (lookup env name `(,arg-types -> ,rtype))
              (infer-fn-args args arg-types env env^)
              (conde
                ((== 'main name) (== 'int rtype))
                ((=/= 'main name)))
              (infer-stmt stmt env^ rtype stmto)))
           ((== decl `(extern ,name . ,type))
            (lookup env name type)
            (== declo decl)))
         (infer-decl* rest resto env)
         (== declo* `(,declo . ,resto)))))))

(define-mk infer-initial-env
  (lambda (decl* envo)
    (conde
      ((== decl* '()) (== envo '()))
      ((fresh (extern/fn name r rest type env^)
         (== decl* `((,extern/fn ,name . ,r) . ,rest))
         (== envo `((,name . ,type) . ,env^))
         (infer-initial-env rest env^))))))

(define-mk infer-module
  (lambda (mod typed-mod)
    (fresh (decl* decl*^ envo)
      (== mod `(module . ,decl*))
      (== typed-mod `(module . ,decl*^))
      (infer-initial-env decl* envo)
      (infer-decl* decl* decl*^ envo))))

(define typecheck
  (lambda (mod)
    (usetypecomp)
    (let ((result (run 2 (q)
                    (infer-module mod q))))
      (case (length result)
        ((0) (error 'typecheck
               "Could not infer type for program."
               mod))
        ((1) (car result))
        (else
         (display result)
         (error 'typecheck
           "Could not infer a unique type for program"
           result))))))

)

