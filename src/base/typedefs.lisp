(defpackage :eazy-a-star.base
  (:use :cl :trivia)
  (:shadowing-import-from :immutable-struct :defstruct :ftype)
  (:nicknames :ea*.b)
  (:export :node :edge
           :priority :id
           ;; 
           :implement-interface
           :define-interface))
(in-package :ea*.b)

(deftype predicate (&optional (arg t)) `(function (,arg) boolean))

(deftype equality (&optional (arg t)) `(function (,arg ,arg) boolean))

(defvar *id-count* 0)
(deftype id () 'fixnum)
(declaim (id *id-count*))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct id-mixin
    (id (incf *id-count*) :type id)))

(declaim (inline id id-mixin-id))
(ftype id id-mixin id)
(defun id (id-mixin)
  (declare (optimize (debug 1) (speed 3) (space 0) (compilation-speed 0) (safety 0)))
  (id-mixin-id id-mixin))

(defstruct (node (:include id-mixin))
  (parent nil :type (or null node)))

(defstruct (edge (:include id-mixin))
  (cost 0 :type fixnum)
  (to (error "no edge destination") :type edge))

(deftype priority ()
  `(mod #.array-dimension-limit))

;;; interface

(defstruct interface
  (typevars nil :type list)
  (methods nil :type list)
  (hash (make-hash-table :test 'equal) :type hash-table))

(defun expander-fn-name (name)
  (let ((*package* (symbol-package name)))
    (alexandria:symbolicate name '-type)))

(lisp-namespace:define-namespace interface interface)

(defmacro define-interface (name typevars &body methods)
  (ematch methods
    ((list* (and s (type string)) rest)
     `(eval-when (:compile-toplevel :load-toplevel :execute)
        (setf (symbol-interface ',name)
              (interface ',typevars ',(mapcar #'first rest)))
        ,@(mapcar (lambda-ematch
                    ((list name body)
                     (let ((expander (expander-fn-name name)))
                       `(progn
                          (defun ,expander ,typevars ,body)
                          (deftype ,name ,typevars (,expander ,@typevars))))))
                  rest)
        (eval '(define-generic-functions ',name))
        ,(dummy-form name typevars (concatenate 'string s "

The macro is a dummy macro for slime integration."))))
    (_ `(define-interface ,name ,typevars "" ,@methods))))

(defun dummy-form (name typevars string)
  `(defmacro ,name (,@typevars)
     ,string
     (declare (ignore ,@typevars))
     (error "dummy macro!")))

(defun check-impl (methods impl)
  (assert (= (length methods) (length impl))
          nil
          "mismatch in interface/implementation"))

(defun check-args (typevars typevals)
  (assert (= (length typevars) (length typevals))
          nil
          "mismatch in interface typevars"))

;;; implement-interface

(defmacro implement-interface ((name &rest typevals) &key (export t))
  (ematch (symbol-interface name)
    ((interface typevars methods hash)
     (let ((implementations
            (mapcar (lambda (x) (intern (string x)))
                    methods)))
       (check-impl methods implementations)
       (check-args typevars typevals)
       (setf (gethash typevals hash) implementations)
       `(eval-when (:compile-toplevel :load-toplevel :execute)
          ,(declaim-method-types methods implementations typevals)
          ,@(when export `((export ',implementations)))
          ,(define-generic-functions name))))))

(defun declaim-method-types (methods implementations typevals)
  `(declaim ,@(mapcar (lambda (method impl)
                        `(cl:ftype (,method ,@typevals) ,impl))
                      methods
                      implementations)))

(deftype lambda-keyword () 'symbol)
(defun lambda-keywordp (obj)
  (match obj
    ((symbol (name (string* #\&))) t)))

(defun /lk (list)
  (remove-if #'lambda-keywordp list))

;; (mapcar (lambda (x) (declare (ignore x)) (gensym))
;;                                          )

(defun define-generic-functions (name)
  ;; recompile the generic version of the function.
  ;; dispatch is implemented with pattern matcher.
  ;; always inlined and dispatch is done in compile time as much as possible
  ;; FIXME: dirty handling of lambda keywords
  (ematch (symbol-interface name)
    ((interface typevars methods hash)
     `(progn
        ,@(mapcar (lambda (m i)
                    ;; for each method, redefine a new generic function
                    (let* ((expander (symbol-function (expander-fn-name m)))
                           (args (mapcar (lambda (x)
                                           (ematch x
                                             ((symbol) x)
                                             (_ (gensym))))
                                         (second (apply expander typevars))))
                           (args/lk (/lk args))
                           arg-type-list
                           result-type-list
                           (body (let (clauses)
                                   (maphash
                                    (lambda (typevals impl-function-names)
                                      ;; run type-expand and get the arguments types and result types
                                      (push (ematch (apply expander typevals)
                                              ((list 'function arg-type result-type)
                                               (push arg-type arg-type-list)
                                               (push result-type result-type-list)
                                               (let ((arg-type/lk (/lk arg-type)))
                                                 `(,(mapcar (lambda (type)
                                                              (match type
                                                                ((list* 'function _)
                                                                 `(type function))
                                                                (_
                                                                 `(type ,type))))
                                                            arg-type/lk)
                                                    (,(elt impl-function-names i) ,@args/lk)))))
                                            clauses))
                                    hash)
                                   (nreverse clauses))))
                      `(progn
                         ,@(when arg-type-list
                             `((ftype ,m ,@(apply #'mapcar (lambda (&rest args)
                                                             (if (lambda-keywordp (car args))
                                                                 (car args)
                                                                 `(or ,@args)))
                                                  arg-type-list) t)))
                         (declaim (inline ,m))
                         (defun-ematch* ,m ,args ,@body))))
                  methods (alexandria:iota (length methods)))))))


;; (defmacro with-implementation ((name . typevals) &body body)
;;   (ematch (symbol-interface name)
;;     ((interface typevars ftypes implementations)
;;      (check-typevals typevars typevals)
;;      (let ((impl (gethash typevals implementations)))
;;        `(flet ,(mapcar (lambda (method)
;;                          `(,method))
;;                        
;;                        impl)
;;           ,@body)))))

