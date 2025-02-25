;;;; arithmetic tests without side effects

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; While most of SBCL is derived from the CMU CL system, the test
;;;; files (like this one) were written from scratch after the fork
;;;; from CMU CL.
;;;;
;;;; This software is in the public domain and is provided with
;;;; absolutely no warranty. See the COPYING and CREDITS files for
;;;; more information.

(defmacro define-compiled-fun (fun name)
  `(progn
    (declaim (notinline ,name))
    (defun ,name (&rest args)
     (declare (optimize safety))
     (case (length args)
       (1 (,fun (car args)))
       (2 (,fun (car args) (cadr args)))
       (t (apply #',fun args))))))

(define-compiled-fun min compiled-min)
(define-compiled-fun max compiled-max)
(define-compiled-fun + compiled-+)
(define-compiled-fun * compiled-*)
(define-compiled-fun logand compiled-logand)
(define-compiled-fun logior compiled-logior)
(define-compiled-fun logxor compiled-logxor)

(assert (null (ignore-errors (compiled-min '(1 2 3)))))
(assert (= (compiled-min -1) -1))
(assert (null (ignore-errors (compiled-min 1 #(1 2 3)))))
(assert (= (compiled-min 10 11) 10))
(assert (null (ignore-errors (compiled-min (find-package "CL") -5.0))))
(assert (= (compiled-min 5.0 -3) -3))
(assert (null (ignore-errors (compiled-max #c(4 3)))))
(assert (= (compiled-max 0) 0))
(assert (null (ignore-errors (compiled-max "MIX" 3))))
(assert (= (compiled-max -1 10.0) 10.0))
(assert (null (ignore-errors (compiled-max 3 #'max))))
(assert (= (compiled-max -3 0) 0))

(assert (null (ignore-errors (compiled-+ "foo"))))
(assert (= (compiled-+ 3f0) 3f0))
(assert (null (ignore-errors (compiled-+ 1 #p"tmp"))))
(assert (= (compiled-+ 1 2) 3))
(assert (null (ignore-errors (compiled-+ '(1 2 3) 3))))
(assert (= (compiled-+ 3f0 4f0) 7f0))
(assert (null (ignore-errors (compiled-* "foo"))))
(assert (= (compiled-* 3f0) 3f0))
(assert (null (ignore-errors (compiled-* 1 #p"tmp"))))
(assert (= (compiled-* 1 2) 2))
(assert (null (ignore-errors (compiled-* '(1 2 3) 3))))
(assert (= (compiled-* 3f0 4f0) 12f0))

(assert (null (ignore-errors (compiled-logand #(1)))))
(assert (= (compiled-logand 1) 1))
(assert (null (ignore-errors (compiled-logior 3f0))))
(assert (= (compiled-logior 4) 4))
(assert (null (ignore-errors (compiled-logxor #c(2 3)))))
(assert (= (compiled-logxor -6) -6))

(with-test (:name (coerce :overflow))
  (checked-compile-and-assert
      ()
      '(lambda (n) (coerce n 'single-float))
    (((expt 10 1000)) (condition 'floating-point-overflow))))

(defun are-we-getting-ash-right (x y)
  (declare (optimize speed)
           (type (unsigned-byte 32) x)
           (type (integer -40 0) y))
  (ash x y))
(defun what-about-with-constants (x)
  (declare (optimize speed) (type (unsigned-byte 32) x))
  (ash x -32))

(dotimes (i 41)
  (assert (= (are-we-getting-ash-right (1- (ash 1 32)) (- i))
             (if (< i 32)
                 (1- (ash 1 (- 32 i)))
                 0))))
(assert (= (what-about-with-constants (1- (ash 1 32))) 0))

(defun one-more-test-case-to-catch-sparc (x y)
  (declare (optimize speed (safety 0))
           (type (unsigned-byte 32) x) (type (integer -40 2) y))
  (the (unsigned-byte 32) (ash x y)))
(assert (= (one-more-test-case-to-catch-sparc (1- (ash 1 32)) -40) 0))


(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *n-fixnum-bits* (- sb-vm:n-word-bits sb-vm::n-fixnum-tag-bits))
  (defvar *shifts* (let ((list (list 0
                                     1
                                     (1- sb-vm:n-word-bits)
                                     sb-vm:n-word-bits
                                     (1+ sb-vm:n-word-bits))))
                     (append list (mapcar #'- list)))))

(macrolet ((nc-list ()
             `(list ,@(loop for i from 0 below (length *shifts*)
                         collect `(frob (nth ,i *shifts*)))))
           (c-list ()
             `(list ,@(loop for i from 0 below (length *shifts*)
                         collect `(frob ,(nth i *shifts*))))))
  (defun nc-ash (x)
    (macrolet ((frob (y)
                 `(list x ,y (ash x ,y))))
      (nc-list)))
  (defun c-ash (x)
    (macrolet ((frob (y)
                 `(list x ,y (ash x ,y))))
      (c-list)))
  (defun nc-modular-ash-ub (x)
    (macrolet ((frob (y)
                 `(list x ,y (logand most-positive-fixnum (ash x ,y)))))
      (nc-list)))
  (defun c-modular-ash-ub (x)
    (declare (type (and fixnum unsigned-byte) x)
             (optimize speed))
    (macrolet ((frob (y)
                 `(list x ,y (logand most-positive-fixnum (ash x ,y)))))
      (c-list))))

(let* ((values (list 0 1 most-positive-fixnum))
       (neg-values (cons most-negative-fixnum
                         (mapcar #'- values))))
  (labels ((test (value fun1 fun2)
             (let ((res1 (funcall fun1 value))
                   (res2 (funcall fun2 value)))
               (mapcar (lambda (a b)
                         (unless (equalp a b)
                           (error "ash failure for ~A vs ~A: ~A not EQUALP ~A"
                                  fun1 fun2
                                  a b)))
                       res1 res2))))
    (loop for x in values do
         (test x 'nc-ash 'c-ash)
         (test x 'nc-modular-ash-ub 'c-modular-ash-ub))
    (loop for x in neg-values do
         (test x 'nc-ash 'c-ash))))


(declaim (inline ppc-ldb-2))

(defun ppc-ldb-2 (fun value)
  (declare (type (signed-byte 32) value)
           (optimize (speed 3) (safety 0) (space 1) (debug 1)
                     (compilation-speed 0)))
  (funcall fun (ldb (byte 8 24) value))
  (funcall fun (ldb (byte 8 16) value))
  (funcall fun (ldb (byte 8 8) value))
  (funcall fun (ldb (byte 8 0) value))
  (values))

(defun ppc-ldb-1 (fun)
  (declare (optimize (speed 3) (safety 0) (space 1) (debug 1)
                     (compilation-speed 0)))
  (loop
     for param :across (make-array 1 :initial-element nil)
     for size :across (make-array 1 :element-type 'fixnum :initial-element 3)
     do (ppc-ldb-2 fun (if param size -1))))

(with-test (:name :ppc-ldb)
 (let ((acc '()))
   (ppc-ldb-1 (lambda (x)
                (push x acc)))
   (assert (equal acc '(#xff #xff #xff #xff)))))

(with-test (:name :ldb-word-cast)
  (checked-compile-and-assert
      ()
      `(lambda (x y)
         (truly-the fixnum (ldb (byte x y) 100)))
    ((100 0) 100)))

(with-test (:name :logbitp-negative-error)
  (checked-compile-and-assert
      (:optimize :safe)
      `(lambda (x y)
         (logbitp x y))
    ((-1 0) (condition 'type-error))
    ((-2 (1+ most-positive-fixnum)) (condition 'type-error))
    (((1- most-negative-fixnum) 1) (condition 'type-error))))

(with-test (:name :*-overflow-ratio)
  (checked-compile-and-assert
      (:optimize :safe)
      `(lambda (a)
         (the fixnum (* 8 a)))
    ((1/8) 1)))

#+64-bit
(with-test (:name :bignum-float)
  (checked-compile-and-assert
      ()
      `(lambda (d)
         (sb-sys:without-gcing
           (let ((res (sb-bignum:%allocate-bignum 2)))
             (setf (sb-bignum:%bignum-ref res 1) 529
                   (sb-bignum:%bignum-ref res 0) 9223372036854775807)
             (sb-bignum:%bignum-set-length res 1)
             (unwind-protect
                  (< res d)
               (sb-bignum:%bignum-set-length res 2)))))
    ((-9.223372036854776d18) nil)
    ((9.223372036854776d18) t)))

(with-test (:name :overflow-transform-nil)
  (checked-compile-and-assert
      (:allow-warnings t)
      `(lambda (v)
         (let ((i 0))
           (flet ((f (i)
                    (the fixnum i)
                    (svref v (+ i 26387449082611642302))))
             (f i)
             (incf i)
             (f i)
             (incf i)))))
  (checked-compile-and-assert
      (:allow-style-warnings t)
      `(lambda (s e)
         (subseq s 0 (when e
                       (- (length s) 12129535698721845515))))))

(with-test (:name :integer-length-union-derivation)
  (checked-compile-and-assert
      ()
      `(lambda (b)
         (integer-length
          (if (>= b 0)
              b
              -2)))
    ((-1) 1)
    ((0) 0)
    ((15) 4)))

(with-test (:name :isqrt-union)
  (assert-type
   (lambda (x)
     (declare ((or (integer 1 5) (integer 9 10)) x))
     (isqrt x))
   (integer 1 3)))

(with-test (:name :integer-length-union)
  (assert-type
   (lambda (x)
     (declare ((or (integer 1 5) (integer 9 10)) x))
     (integer-length x))
   (integer 1 4)))

(with-test (:name :rem-transform-erase-types)
  (checked-compile-and-assert
   ()
   `(lambda (a)
      (declare ((integer * 0) a))
      (zerop (rem a 2)))
   ((-1) nil)
   ((-2) t))
  (checked-compile-and-assert
   ()
   `(lambda (a)
      (declare ((member 7 -9) a))
      (zerop (rem a 8)))
   ((7) nil)
   ((-9) nil)))

(with-test (:name :unexpected-immediates-in-vops)
  (checked-compile
   `(lambda (n)
      (declare (fixnum n))
      (loop for i below 2
            do (print (logbitp i n))
               (the (satisfies minusp) i))))
  (checked-compile
   `(lambda ()
      (loop for i below 2
            do (print (lognot i))
               (the (satisfies minusp) i))))
  (checked-compile
   `(lambda ()
      (loop for i below 2
            do (print (- i))
               (the (satisfies minusp) i))))
  (checked-compile
   `(lambda ()
      (loop for i below 2
            do (print (* i 3))
               (the (satisfies minusp) i))))
  (checked-compile
   `(lambda ()
      (loop for i below 2
            do (print (* i 3))
               (the (satisfies minusp) i))))
  (checked-compile
   `(lambda ()
      (loop for i of-type fixnum below 2
            do (print (logand most-positive-word (* i 4)))
               (the (satisfies minusp) i)))))

(with-test (:name :/-by-integer-type)
  (assert-type
   (lambda (x y)
     (declare ((integer 1 9) x)
              (integer y))
     (/ x y))
   (or (rational -9 (0)) (rational (0) 9)))
  (assert-type
   (lambda (x y)
     (declare ((integer 1 9) x)
              ((integer 0) y))
     (/ x y))
   (rational (0) 9))
  (assert-type
   (lambda (x y)
     (declare ((rational 0 9) x)
              ((integer 0) y))
     (/ x y))
   (rational 0 9)))

(with-test (:name :truncate-unused-q)
  (checked-compile-and-assert
   ()
   `(lambda (a)
      (declare (fixnum a))
      (rem a 4))
   ((3) 3)
   ((-3) -3)
   ((4) 0)
   ((-4) 0)))

(with-test (:name :*-by-integer-type)
  (assert-type
   (lambda (x)
     (declare (integer x))
     (* x 5))
   (or (integer 5) (integer * -5) (integer 0 0))))

(with-test (:name :truncate-transform-unused-result)
  (assert-type
   (lambda (c)
     (declare ((integer -1000 0) c)
              (optimize speed))
     (values
      (truncate (truncate (rem c -89) -16) 20)))
   (or (integer 0 0))))

(with-test (:name :rem^2)
  (checked-compile-and-assert
   ()
   `(lambda (a)
      (declare (fixnum a))
      (rem a 2))
   ((-2) 0)
   ((-3) -1)
   ((2) 0)
   ((3) 1)))

(with-test (:name :deposit-field-derive-type)
  (assert-type
   (lambda (s)
     (declare ((member 8 10) s))
     (deposit-field -21031455 (byte s 9) 1565832649825))
   (or (integer 1565832320097 1565832320097) (integer 1565832713313 1565832713313))))

(with-test (:name :logior-negative-bound)
  (checked-compile-and-assert
   ()
   `(lambda (b c)
      (declare ((integer 7703 1903468060) c))
      (logandc1 (/ (logorc2 c b) -1) c))
   ((-1 7703) 7702)))

(with-test (:name :set-numeric-contagion)
  (assert-type
   (lambda (n)
     (loop for i below n
           sum (coerce n 'single-float)))
   (or (integer 0 0) single-float)))

(with-test (:name :overflow-transform-order)
  (checked-compile-and-assert
      (:optimize :safe)
      `(lambda (a m)
         (declare (fixnum a))
         (let ((j (* 44 a)))
           (when m
             (the fixnum j))))
    ((most-positive-fixnum nil) nil)
    ((most-positive-fixnum t) (condition 'type-error))))
