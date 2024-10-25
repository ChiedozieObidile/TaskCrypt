;; TaskCrypt - Enhanced Decentralized Freelance Marketplace
;; Contract for managing freelance jobs, payments, and disputes with advanced features

(define-constant contract-owner tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INVALID-JOB (err u2))
(define-constant ERR-INSUFFICIENT-FUNDS (err u3))
(define-constant ERR-ALREADY-COMPLETED (err u4))
(define-constant ERR-INVALID-MILESTONE (err u5))
(define-constant ERR-TIMEOUT-NOT-REACHED (err u6))
(define-constant ERR-INVALID-AMOUNT (err u7))
(define-constant TIMEOUT-BLOCKS u1440) ;; ~10 days at 10min per block
(define-constant PLATFORM-FEE-RATE u25) ;; 2.5% fee (base 1000)
(define-constant MIN-STAKE-AMOUNT u1000000) ;; Minimum stake for freelancers

;; Enhanced Data Structures
(define-map Jobs
    { job-id: uint }
    {
        client: principal,
        freelancer: principal,
        total-amount: uint,
        remaining-amount: uint,
        description: (string-ascii 256),
        category: (string-ascii 64),
        status: (string-ascii 20),
        created-at: uint,
        completed-at: uint,
        deadline: uint,
        arbitrator: (optional principal),
        milestones-total: uint,
        milestones-completed: uint
    }
)

(define-map Milestones
    { job-id: uint, milestone-id: uint }
    {
        description: (string-ascii 256),
        amount: uint,
        status: (string-ascii 20),
        deadline: uint
    }
)

(define-map UserRatings
    { user: principal }
    {
        total-ratings: uint,
        rating-sum: uint,
        jobs-completed: uint,
        disputes-won: uint,
        disputes-lost: uint
    }
)

(define-map FreelancerStakes
    { user: principal }
    {
        amount: uint,
        locked-until: uint
    }
)

(define-map ServiceCategories
    { category-id: uint }
    {
        name: (string-ascii 64),
        description: (string-ascii 256),
        min-stake: uint
    }
)

(define-data-var job-counter uint u0)
(define-data-var category-counter uint u0)

;; Stake management for freelancers
(define-public (stake-tokens (amount uint))
    (begin
        (asserts! (>= amount MIN-STAKE-AMOUNT) ERR-INVALID-AMOUNT)
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (map-set FreelancerStakes
            { user: tx-sender }
            {
                amount: amount,
                locked-until: (+ block-height TIMEOUT-BLOCKS)
            }
        )
        (ok true)))

(define-public (withdraw-stake)
    (let ((stake (unwrap! (map-get? FreelancerStakes { user: tx-sender }) ERR-NOT-AUTHORIZED)))
        (asserts! (>= block-height (get locked-until stake)) ERR-TIMEOUT-NOT-REACHED)
        (try! (as-contract (stx-transfer? (get amount stake) tx-sender tx-sender)))
        (map-delete FreelancerStakes { user: tx-sender })
        (ok true)))

;; Enhanced job creation with milestones
(define-public (create-job-with-milestones 
    (freelancer principal) 
    (total-amount uint) 
    (description (string-ascii 256))
    (category (string-ascii 64))
    (milestone-amounts (list 10 uint))
    (milestone-descriptions (list 10 (string-ascii 256)))
    (deadline uint))
    
    (let ((job-id (+ (var-get job-counter) u1))
          (platform-fee (/ (* total-amount PLATFORM-FEE-RATE) u1000)))
        
        (asserts! (>= (stx-get-balance tx-sender) (+ total-amount platform-fee)) 
                 ERR-INSUFFICIENT-FUNDS)
        (asserts! (is-some (map-get? FreelancerStakes { user: freelancer }))
                 ERR-NOT-AUTHORIZED)
        
        ;; Transfer total amount plus platform fee
        (try! (stx-transfer? (+ total-amount platform-fee) 
                            tx-sender 
                            (as-contract tx-sender)))
        
        ;; Create main job entry
        (map-set Jobs
            { job-id: job-id }
            {
                client: tx-sender,
                freelancer: freelancer,
                total-amount: total-amount,
                remaining-amount: total-amount,
                description: description,
                category: category,
                status: "pending",
                created-at: block-height,
                completed-at: u0,
                deadline: (+ block-height deadline),
                arbitrator: none,
                milestones-total: (len milestone-amounts),
                milestones-completed: u0
            }
        )
        
        ;; Create milestone entries
        (create-milestones job-id milestone-amounts milestone-descriptions)
        
        (var-set job-counter job-id)
        (ok job-id)))

;; Helper function to create milestones
(define-private (create-milestones 
    (job-id uint)
    (amounts (list 10 uint))
    (descriptions (list 10 (string-ascii 256))))
    
    (let ((milestone-id u0))
        (map create-milestone-entry 
             amounts 
             descriptions)
        (ok true)))

(define-private (create-milestone-entry 
    (amount uint)
    (description (string-ascii 256)))
    
    (map-set Milestones
        { job-id: job-id, milestone-id: milestone-id }
        {
            description: description,
            amount: amount,
            status: "pending",
            deadline: (+ block-height TIMEOUT-BLOCKS)
        }
    ))

;; Complete milestone
(define-public (complete-milestone (job-id uint) (milestone-id uint))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB))
          (milestone (unwrap! (map-get? Milestones { job-id: job-id, milestone-id: milestone-id }) 
                             ERR-INVALID-MILESTONE)))
        
        (asserts! (is-eq (get status milestone) "pending") ERR-ALREADY-COMPLETED)
        (asserts! (is-eq tx-sender (get client job)) ERR-NOT-AUTHORIZED)
        
        ;; Transfer milestone amount to freelancer
        (try! (as-contract (stx-transfer? (get amount milestone) 
                                        tx-sender 
                                        (get freelancer job))))
        
        ;; Update milestone status
        (map-set Milestones
            { job-id: job-id, milestone-id: milestone-id }
            (merge milestone { status: "completed" }))
        
        ;; Update job status if all milestones completed
        (if (is-eq (+ (get milestones-completed job) u1) 
                  (get milestones-total job))
            (map-set Jobs
                { job-id: job-id }
                (merge job {
                    status: "completed",
                    completed-at: block-height,
                    milestones-completed: (+ (get milestones-completed job) u1),
                    remaining-amount: (- (get remaining-amount job) (get amount milestone))
                }))
            (map-set Jobs
                { job-id: job-id }
                (merge job {
                    milestones-completed: (+ (get milestones-completed job) u1),
                    remaining-amount: (- (get remaining-amount job) (get amount milestone))
                })))
        
        (ok true)))

;; Enhanced dispute resolution with evidence
(define-map DisputeEvidence
    { job-id: uint, party: principal }
    {
        evidence-hash: (buff 32),
        timestamp: uint
    }
)

(define-public (submit-dispute-evidence (job-id uint) (evidence-hash (buff 32)))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (asserts! (or (is-eq tx-sender (get client job))
                     (is-eq tx-sender (get freelancer job)))
                 ERR-NOT-AUTHORIZED)
        (map-set DisputeEvidence
            { job-id: job-id, party: tx-sender }
            {
                evidence-hash: evidence-hash,
                timestamp: block-height
            }
        )
        (ok true)))

;; Automatic refund on timeout
(define-public (claim-timeout-refund (job-id uint))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (asserts! (is-eq tx-sender (get client job)) ERR-NOT-AUTHORIZED)
        (asserts! (> block-height (get deadline job)) ERR-TIMEOUT-NOT-REACHED)
        (asserts! (is-eq (get status job) "pending") ERR-ALREADY-COMPLETED)
        
        ;; Refund remaining amount to client
        (try! (as-contract (stx-transfer? (get remaining-amount job)
                                        tx-sender
                                        (get client job))))
        
        (map-set Jobs
            { job-id: job-id }
            (merge job {
                status: "refunded",
                completed-at: block-height
            }))
        (ok true)))

;; Service category management
(define-public (create-service-category 
    (name (string-ascii 64))
    (description (string-ascii 256))
    (min-stake uint))
    
    (let ((category-id (+ (var-get category-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (map-set ServiceCategories
            { category-id: category-id }
            {
                name: name,
                description: description,
                min-stake: min-stake
            }
        )
        (var-set category-counter category-id)
        (ok category-id)))

;; Enhanced read-only functions
(define-read-only (get-job-with-milestones (job-id uint))
    (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
        (ok {
            job: job,
            milestones: (get-job-milestones job-id (get milestones-total job))
        })))

(define-read-only (get-job-milestones (job-id uint) (total uint))
    (map unwrap-or-none
        (map milestone-id-to-milestone
            (get-milestone-ids u0 total))))

(define-private (get-milestone-ids (start uint) (end uint))
    (map uint-to-milestone-tuple
        (range start end)))

(define-private (uint-to-milestone-tuple (id uint))
    { job-id: job-id, milestone-id: id })

(define-private (milestone-id-to-milestone (id { job-id: uint, milestone-id: uint }))
    (map-get? Milestones id))

(define-private (unwrap-or-none (opt (optional (tuple (description (string-ascii 256)) (amount uint) (status (string-ascii 20)) (deadline uint)))))
    (default-to
        {
            description: "",
            amount: u0,
            status: "none",
            deadline: u0
        }
        opt))

(define-read-only (get-freelancer-stats (freelancer principal))
    (let ((rating (unwrap! (map-get? UserRatings { user: freelancer }) (err u8)))
          (stake (map-get? FreelancerStakes { user: freelancer })))
        (ok {
            rating: rating,
            stake: stake
        })))