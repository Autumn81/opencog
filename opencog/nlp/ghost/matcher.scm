;; GHOST DSL for chat authoring rules
;;
;; This is the custom action selector that allows OpenPsi to find the authored
;; rules.
;; TODO: This is not needed in the long run as the default action selector in
;; OpenPsi should be able to know how and what kinds of rules it should be
;; looking for at a particular point in time.

(define (eval-rules RULES)
  "Evaluate each of the RULES, return those that are satisfied."
  (append-map
    (lambda (r)
      (if (equal? (stv 1 1) (psi-satisfiable? r)) (list r) '()))
    RULES))

(define-public (ghost-find-rules SENT)
  "The action selector. It first searches for the rules using DualLink,
   and then does the filtering by evaluating the context of the rules.
   Eventually returns a list of weighted rules that can satisfy the demand."
  (let* ((curr-topic (ghost-get-curr-topic))
         (input-lseq (gddr (car (filter (lambda (e)
           (equal? ghost-lemma-seq (gar e)))
             (cog-get-pred SENT 'PredicateNode)))))
         ; The ones that contains no variables/globs
         (exact-match (filter psi-rule? (cog-get-trunk input-lseq)))
         ; The ones that contains no constant terms
         (no-const (filter psi-rule? (append-map cog-get-trunk
           (cog-chase-link 'MemberLink 'ListLink ghost-no-constant))))
         ; The ones found by the recognizer
         (dual-match (filter psi-rule? (append-map cog-get-trunk
           (cog-outgoing-set (cog-execute! (Dual input-lseq))))))
         ; Get the psi-rules associate with them with duplicates removed
         (rules-matched
           (fold (lambda (rule prev)
                   ; Since a psi-rule can satisfy multiple goals and an
                   ; ImplicationLink will be generated for each of them,
                   ; we are comparing the implicant of the rules instead
                   ; of the rules themselves, and create a list of rules
                   ; with unique implicants
                   (if (any (lambda (r) (equal? (gar r) (gar rule))) prev)
                       prev (append prev (list rule))))
                 (list) (append exact-match no-const dual-match)))
         ; Evaluate the matched rules one by one and see which of them satisfy
         (rules-satisfied
           (receive (topic-rules other-rules)
             ; Partition the matched rules into two groups -- "on topic"
             ; and "not on topic"
             (partition (lambda (r)
               (equal? curr-topic (car
                 (filter (lambda (x) (any (lambda (y) (equal? ghost-topic y))
                   (cog-chase-link 'InheritanceLink 'ConceptNode x)))
                     (cog-chase-link 'MemberLink 'ConceptNode r)))))
               rules-matched)
             ; Evaluate the ones that are on the current topic first, then the
             ; other rules if no on topic rules are satisfied
             (let ((satisfied-topic-rules (eval-rules topic-rules)))
                  (if (null? satisfied-topic-rules)
                      (eval-rules other-rules)
                      satisfied-topic-rules)))))
        (cog-logger-debug ghost-logger "For input:\n~a" input-lseq)
        (cog-logger-debug ghost-logger "Rules with no constant:\n~a" no-const)
        (cog-logger-debug ghost-logger "Exact match:\n~a" exact-match)
        (cog-logger-debug ghost-logger "Dual match:\n~a" dual-match)
        (cog-logger-debug ghost-logger "Rules matched:\n~a" rules-matched)
        (cog-logger-debug ghost-logger "Rules satisfied:\n~a" rules-satisfied)
        (List rules-satisfied)))

(Define
  (DefinedSchema (ghost-prefix "Get Current Input"))
  (Get (State ghost-curr-proc (Variable "$x"))))

(Define
  (DefinedSchema (ghost-prefix "Find Rules"))
  (Lambda (VariableList (TypedVariable (Variable "$sentence")
                                       (Type "SentenceNode")))
          (ExecutionOutput (GroundedSchema "scm: ghost-find-rules")
                           (List (Variable "$sentence")))))

; The action selector for OpenPsi
(psi-set-action-selector
  (Put (DefinedSchema (ghost-prefix "Find Rules"))
       (DefinedSchema (ghost-prefix "Get Current Input")))
  ; Component label
  (Concept "GHOST"))
