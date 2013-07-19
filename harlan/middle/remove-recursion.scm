(library
    (harlan middle remove-recursion)
  (export remove-recursion)
  (import
   (rnrs)
   (rnrs mutable-pairs)
   (only (chezscheme) pretty-print trace-define)
   (harlan middle languages)
   (harlan helpers)
   (harlan compile-opts)
   (elegant-weapons sets)
   (elegant-weapons graphs)
   (elegant-weapons graphviz)
   (nanopass))

  ;; This is the set of passes that transforms recursive functions
  ;; called from kernels so that they are no longer recursive.
  ;;
  ;; There are several steps. First, we need to identify the recursive
  ;; functions, which involves looking for cycles in the call
  ;; graph. This is simpler at this point, because lambdas have been
  ;; removed.
  ;;
  ;; Secondly, we need to find the functions that are reachable from
  ;; kernels. This isn't strictly necessary, but for code that's
  ;; running on the CPU, we might as well use C's support for
  ;; recursion instead.
  ;;
  ;; Next, the functions that have been identified as recursive and
  ;; kernel-reachable need to be transformed to CPS. We will probably
  ;; do this by defining a new continuation form, which is sort of
  ;; like lambda, but will be removed later. We'll probably also want
  ;; to generate wrapper functions at this point which supply the
  ;; initial continuation, so that callers don't need to worry about
  ;; the CPS functions.
  ;;
  ;; Finally, we need to build trampolines.

  ;; We may want to split functions with kernels into a host and
  ;; device version. The host version can keep the kernel form while
  ;; the device version replaces the kernel with a for loop, so that
  ;; it can be called once we enter the kernel. Perhaps this can
  ;; happen in remove-nested-kernels or in one of the passes that
  ;; handles functions in a gpu-module.

  (trace-define-pass extract-callgraph : M3 (m) -> M4 ()
    (definitions

      (define current-node '())
      (define cgraph '())

      (define (new-node! name)
        (unless (null? current-node)
          (set! cgraph (cons current-node cgraph)))
        (set! current-node (list name)))

      (define (add-call! name)
        (set-cdr! current-node (set-add (cdr current-node) name))))
    
    (Body : Body (b) -> Body ())
    
    (Decl
     : Decl (decl) -> Decl ()

     ((fn ,name (,x ...) ,[t] ,body)
      (new-node! name)
      `(fn ,name (,x ...) ,t ,(Body body))))

    (Expr
     : Expr (e) -> Expr ()
     ((call (var ,[t] ,x) ,[e*] ...)
      (add-call! x)
      `(call (var ,t ,x) ,e* ...)))
    
    (Module
     : Module (m) -> CallGraph ()
     ((module ,[decl] ...)
      (new-node! '_)
      (if (dump-call-graph)
          (begin
            (if (file-exists? "call-graph.dot")
                (delete-file "call-graph.dot"))
            (write-dot cgraph
                       (strongly-connected-components cgraph)
                       (open-output-file "call-graph.dot"))))
      `(call-graph ,cgraph (module ,decl ...)))))

  (define-pass remove-callgraph : M4 (m) -> M3 ()

    (CallGraph
     : CallGraph (cg) -> Module ()

     ((call-graph ,? ,[m])
      m)))
  
  (define (remove-recursion module)
    (>::> module
          extract-callgraph
          remove-callgraph
          unparse-M3))
  
  )
