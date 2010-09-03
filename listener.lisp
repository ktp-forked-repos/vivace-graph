(in-package #:vivace-graph)

(defparameter *stop-listener* nil)
(defparameter *eoc* 0)
(defparameter +max-bytes+ 10240)

(define-condition listener-error (error)
  ((reason :initarg :reason))
  (:report (lambda (error stream)
             (with-slots (reason)
                 error
               (format stream "Listener error: ~A." reason)))))

(defmethod data-received-handler ((session session))
  (let ((buffer (session-buffer session)))
    (do ((fin nil))
	(fin t)
      (let ((len
	     (do ((byte (read-byte (session-stream session) nil :eof)
			(read-byte (session-stream session) nil :eof))
		  (count 0 (incf count)))
		 ((or (= (fill-pointer (session-buffer session)) +buflen+)
		      (eq byte :eof))
		  count)
	       (vector-push-extend byte (session-buffer session))
	       (if (eql byte *eoc*) (return count)))))
	(if (= 0 len)
	    (setf fin t)
	    (setf (fill-pointer buffer) len)))
      (cond ((= (length buffer) 0)
	     (logger :debug "Got 0 bytes, closing session ~A" session)
	     (setf fin t)
	     (setf (session-finished? session) t))
	    (fin 
	     (logger :debug "Got NIL for ~A, returning from data-received-handler" session)
	     (setf (session-finished? session) t))
	    ((and (= (fill-pointer (session-buffer session)) +buflen+)
		  (not (= *eoc* (aref (session-buffer session) 
				      (1- (fill-pointer (session-buffer session)))))))
	     (logger :crit "Buffer overrun attempt for ~A: ~A" session (session-buffer session))
	     (setf (session-finished? session) t))
	    (t
	     (logger :debug "Read ~A bytes for ~A: ~A~%" 
		     (length buffer) session buffer)
	     (dotimes (i (length buffer))
	       (logger :debug "Sending byte ~A: ~A to client" i (aref buffer i))
	       (write-byte (aref buffer i) (session-stream session)))
	     (force-output (session-stream session)))))))

(defun client-loop ()
  (handler-case
      (progn
        (loop until *stop-listener*
           do
           (let ((socket
		  (usocket:wait-for-input (session-socket *session*) :ready-only t :timeout 1)))
             (when socket
               (let ((status (data-received-handler *session*)))
		 (logger :debug "client-loop got status ~A" status)
		 (if (session-finished? *session*) (return))))))
        (shutdown-session *session*)
        (logger :debug "Session ended normally: ~A" *session*))
    (end-of-file (c)
      (declare (ignore c))
      (logger :err "Client closed connection. Killing ~A" *session*)
      (shutdown-session *session*))
    (error (c)
      (logger :err "client-loop got unhandled error: ~A. Killing session." 
	      (or c "?"))
      (shutdown-session *session*))))

(defun accept-handler (socket)
  (make-thread
   #'(lambda ()
       (let (*session*)
         (logger :debug "IN ACCEPT-HANDLER FOR ~A" socket)
         (handler-case
             (let ((stream (usocket:socket-stream socket)))
               (setf *session* (start-session stream socket))
               (force-output (session-stream *session*))
               (setf (session-thread *session*) (current-thread))
               (initiate-session *session*))
           (end-of-file (c)
             (declare (ignore c))
             (logger :err "Client closed connection. Killing ~A" *session*)
             (when (session? *session*)
               (shutdown-session *session*)))
           (error (c)
             (logger :err "~A got unhandled error: ~A. Killing session." *session* c)
             (when (session? *session*)
               (shutdown-session *session*)))
	   (:no-error (status)
	     (declare (ignore status))
	     (if (session? *session*)
		 (client-loop)
		 (progn
		   (logger :err "Unable to initiate session.")
		   (remove-thread (current-thread))))))))
   :name (format nil "~A handler" socket)))

(defun stop-listener ()
  (setf *stop-listener* t))

(defun start-listener (port &key (address usocket:*wildcard-host*))
  (logger :info "Starting tcp listener on port ~A" port)
  (setf *stop-listener* nil)
  (usocket:with-server-socket (listener (usocket:socket-listen address port 
							       :reuse-address t 
							       :element-type '(unsigned-byte 8)))
    (loop until *stop-listener*
       do
       (handler-case
           (when (usocket:wait-for-input listener :ready-only t :timeout 1)
             (let ((client-connection (usocket:socket-accept listener 
							     :element-type '(unsigned-byte 8))))
               (handler-case
                   (let ((thread (accept-handler client-connection)))
		     (if (threadp thread)
			 (add-thread thread)))
                 (usocket:connection-aborted-error ())
                 (usocket:socket-error (c)
                   (logger :err "Listener got error on ~A: ~A" listener c)))))
         (error (c)
           (logger :err "UNHANDLED ERROR OF TYPE ~A IN LISTENER: ~A" (type-of c) c)))))
  (logger :info "Shutting down tcp listener on port ~A" port))

