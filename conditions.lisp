(in-package #:vivace-graph)

(define-condition revision-error (error)
  ((instance :initarg :instance)
   (revision-number :initarg :revision))
  (:report (lambda (error stream)
	     (with-slots (instance revision-number) error
	       (format stream "Problem with ~a revision# ~a." instance revision-number)))))

(define-condition transaction-error (error)
  ((instance :initarg :instance)
   (reason :initarg :reason))
  (:report (lambda (error stream)
	     (with-slots (instance reason) error
	       (format stream "Transaction failed for ~a because of ~a." instance reason)))))

(define-condition serialization-error (error)
  ((instance :initarg :instance)
   (reason :initarg :reason))
  (:report (lambda (error stream)
	     (with-slots (instance reason) error
	       (format stream "Serialization failed for ~a because of ~a." instance reason)))))

(define-condition deserialization-error (error)
  ((instance :initarg :instance)
   (reason :initarg :reason))
  (:report (lambda (error stream)
	     (with-slots (instance reason) error
	       (format stream "Deserialization failed for ~a because of ~a." instance reason)))))
