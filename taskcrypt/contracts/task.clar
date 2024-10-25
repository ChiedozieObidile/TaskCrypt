;; TaskCrypt - Decentralized Freelance Marketplace
;; Contract for managing freelance jobs, payments, and disputes

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INVALID-JOB (err u2))
(define-constant ERR-INSUFFICIENT-FUNDS (err u3))
(define-constant ERR-ALREADY-COMPLETED (err u4))

;; Data structures
(define-map Jobs
    { job-id: uint }
    {
        client: principal,
        freelancer: principal,
        amount: uint,
        description: (string-ascii 256),
        status: (string-ascii 20),
        created-at: uint,
        completed-at: uint,
        arbitrator: (optional principal)
    }
)

(define-map UserRatings
    { user: principal }
    {
        total-ratings: uint,
        rating-sum: uint,
        jobs-completed: uint
    }
)

(define-data-var job-counter uint u0)

;; Create a new job
(define-public (create-job (freelancer principal) (amount uint) (description (string-ascii 256)))
    (let
        ((job-id (+ (var-get job-counter) u1)))
        (if (>= (stx-get-balance tx-sender) amount)
            (begin
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set Jobs
                    { job-id: job-id }
                    {
                        client: tx-sender,
                        freelancer: freelancer,
                        amount: amount,
                        description: description,
                        status: "pending",
                        created-at: block-height,
                        completed-at: u0,
                        arbitrator: none
                    }
                )
                (var-set job-counter job-id)
                (ok job-id))
            ERR-INSUFFICIENT-FUNDS)))

;; Complete job and release payment
(define-public (complete-job (job-id uint))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (asserts! (is-eq (get status job) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (or (is-eq tx-sender (get client job)) 
                     (is-eq tx-sender (get freelancer job)))
                 ERR-NOT-AUTHORIZED)
        (try! (as-contract (stx-transfer? (get amount job) tx-sender (get freelancer job))))
        (map-set Jobs
            { job-id: job-id }
            (merge job { 
                status: "completed",
                completed-at: block-height
            })
        )
        (ok true)))

;; Rate a user
(define-public (rate-user (user principal) (rating uint))
    (let ((current-rating (default-to 
            { total-ratings: u0, rating-sum: u0, jobs-completed: u0 }
            (map-get? UserRatings { user: user }))))
        (asserts! (and (>= rating u1) (<= rating u5)) (err u5))
        (map-set UserRatings
            { user: user }
            {
                total-ratings: (+ (get total-ratings current-rating) u1),
                rating-sum: (+ (get rating-sum current-rating) rating),
                jobs-completed: (+ (get jobs-completed current-rating) u1)
            }
        )
        (ok true)))

;; Initiate dispute
(define-public (initiate-dispute (job-id uint) (arbitrator principal))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (asserts! (is-eq (get status job) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (or (is-eq tx-sender (get client job)) 
                     (is-eq tx-sender (get freelancer job)))
                 ERR-NOT-AUTHORIZED)
        (map-set Jobs
            { job-id: job-id }
            (merge job { 
                status: "disputed",
                arbitrator: (some arbitrator)
            })
        )
        (ok true)))

;; Resolve dispute
(define-public (resolve-dispute (job-id uint) (pay-to principal))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (asserts! (is-eq (get status job) "disputed") ERR-INVALID-JOB)
        (asserts! (is-eq tx-sender (unwrap! (get arbitrator job) ERR-NOT-AUTHORIZED))
                 ERR-NOT-AUTHORIZED)
        (try! (as-contract (stx-transfer? (get amount job) tx-sender pay-to)))
        (map-set Jobs
            { job-id: job-id }
            (merge job { 
                status: "resolved",
                completed-at: block-height
            })
        )
        (ok true)))

;; Read-only functions
(define-read-only (get-job (job-id uint))
    (map-get? Jobs { job-id: job-id }))

(define-read-only (get-user-rating (user principal))
    (let ((rating (unwrap! (map-get? UserRatings { user: user }) (err u6))))
        (ok {
            average-rating: (/ (get rating-sum rating) (get total-ratings rating)),
            total-ratings: (get total-ratings rating),
            jobs-completed: (get jobs-completed rating)
        })))
