;;; -*- Gerbil -*-
;;; (C) vyzo
;;; some standard sugar
package: std

(export #t)

(defrules catch ())
(defrules finally ())

(defsyntax (try stx)
  (def (generate-thunk body)
    (if (null? body)
      (raise-syntax-error #f "Bad syntax; missing body" stx)
      (with-syntax (((e ...) (reverse body)))
        #'(lambda () e ...))))

  (def (generate-fini thunk fini)
    (with-syntax ((thunk thunk)
                  ((e ...) fini))
      #'(with-unwind-protect thunk (lambda () e ...))))

  (def (generate-catch handlers thunk)
    (with-syntax (($e (genident)))
      (let lp ((rest handlers) (clauses []))
        (match rest
          ([hd . rest]
           (syntax-case hd (=>)
             ((pred => K)
              (lp rest (cons #'(((? pred) $e) => K)
                             clauses)))
             (((pred var) body ...)
              (identifier? #'var)
              (lp rest (cons #'(((? pred) $e) (let ((var $e)) body ...))
                             clauses)))
             (((var) body ...)
              (identifier? #'var)
              (lp rest (cons #'(#t (let ((var $e)) body ...))
                             clauses)))
             ((us body ...)
              (underscore? #'us)
              (lp rest (cons #'(#t (begin body ...))
                             clauses)))))
          (else
           (with-syntax (((clause ...) clauses)
                         (thunk thunk))
             #'(with-catch
                (lambda ($e) (cond clause ... (else (raise $e))))
                thunk)))))))

  (syntax-case stx ()
    ((_ e ...)
     (let lp ((rest #'(e ...)) (body []))
       (syntax-case rest ()
         ((hd . rest)
          (syntax-case #'hd (catch finally)
            ((finally fini ...)
             (if (stx-null? #'rest)
               (generate-fini (generate-thunk body) #'(fini ...))
               (raise-syntax-error #f "Misplaced finally clause" stx)))
            ((catch handler ...)
             (let lp ((rest #'rest) (handlers [#'(handler ...)]))
               (syntax-case rest (catch finally)
                 (((catch handler ...) . rest)
                  (lp #'rest [#'(handler ...) . handlers]))
                 (((finally fini ...))
                  (with-syntax ((body (generate-catch handlers (generate-thunk body))))
                    (generate-fini #'(lambda () body) #'(fini ...))))
                 (()
                  (generate-catch handlers (generate-thunk body))))))
            (_ (lp #'rest (cons #'hd body)))))
         (() ; no clauses, just a begin
          (cons 'begin (reverse body))))))))

(defrules with-destroy ()
  ((_ obj body ...)
   (let ($obj obj)
     (try body ... (finally {destroy $obj})))))

(defsyntax (defmethod/alias stx)
  (syntax-case stx (@method)
    ((_ {method (alias ...) type} body ...)
     (and (identifier? #'method)
          (stx-andmap identifier? #'(alias ...))
          (syntax-local-type-info? #'type))
     (with-syntax* (((values klass) (syntax-local-value #'type))
                    (type::t (runtime-type-identifier klass))
                    (method-impl (stx-identifier #'method #'type "::" #'method)))
       #'(begin
           (defmethod {method type} body ...)
           (bind-method! type::t 'alias method-impl) ...)))))

(defrules assert! ()
  ((_ expr)
   (unless expr
     (error "Assertion failed" 'expr)))
  ((_ expr message)
   (unless expr
     (error "Assertion failed" message 'expr))))

(defrules while ()
  ((_ test body ...)
   (let lp ()
     (when test
       body ...
       (lp)))))

(defrules until ()
  ((_ test body ...)
   (let lp ()
     (unless test
       body ...
       (lp)))))

(defrules hash ()
  ((_ (key val) ...)
   (~hash-table make-hash-table (key val) ...)))

(defrules hash-eq ()
  ((_ (key val) ...)
   (~hash-table make-hash-table-eq (key val) ...)))

(defrules hash-eqv ()
  ((_ (key val) ...)
   (~hash-table make-hash-table-eqv (key val) ...)))

(defsyntax (~hash-table stx)
  (syntax-case stx ()
    ((_ make-ht clause ...)
     (with-syntax* ((size (stx-length #'(clause ...)))
                    (((key val) ...) #'(clause ...)))
       #'(let (ht (make-ht size: size))
           (hash-put! ht `key val) ...
           ht)))))
