;;;; assume id

(defpackage :eazy-a-star.queue.array.list
  (:use :cl :ea*.b :ea*.q :ea*.bag.list :trivia)
  (:shadowing-import-from :immutable-struct :ftype)
  (:nicknames :ea*.q.a.l))
(in-package :ea*.q.a.l)

;; Assumes the histogram of the priority is very dense and the priority is
;; always an integer. best for unit cost problems.
;; when not unit-cost, use gcd to try converting the costs?
;; (expt 2 26) array: up to 67108864, 400M
;; (expt 2 20) array: up to 1048576, 10M
;; (expt 2 18) array: up to 262144, 2.5M

(defstruct queue
  (min 0 :type fixnum)
  (array (error "no array") :type (array list)))

(implement-interface (queue-methods (queue)))

(ftype reflesh-minimum queue (values))
(defun reflesh-minimum (queue)
  (ematch queue
    ((queue (min (place min)) array)
     (do () ((emptyp (aref array min)))
       (incf min))
     (values))))

(defun init (&optional (initial-max (expt 2 18)))
  (make-queue :array (make-array initial-max :element-type 'bag)))

(defun enqueue (queue node value)
  (ematch queue
    ((queue (min (place min)) array)
     (insert node (aref array value))
     (alexandria:minf min value)
     (values))))

(defun dequeue (queue)
  (ematch queue
    ((queue (min (place min)) array)
     (let ((bag (aref array min)))
       (if (emptyp bag)
           (prog1
             (values (get1 bag) t)
             (reflesh-minimum queue))
           (values nil nil))))))

(defun delete-node (queue value node)
  (delete-id (id node)))

(defun delete-id (queue value id)
  (ematch queue
    ((queue array)
     (if (aref array value)
         (values (progn (setf (aref array value)
                              (delete-id id (aref array value)))
                        (reflesh-minimum queue)
                        queue)
                 t)
         (values queue nil)))))