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
(define-constant ERR-TOO-MANY-MILESTONES (err u8))
(define-constant ERR-INVALID-FREELANCER (err u9))
(define-constant ERR-INVALID-DESCRIPTION (err u10))
(define-constant ERR-INVALID-CATEGORY (err u11))
(define-constant ERR-INVALID-DEADLINE (err u12))
(define-constant ERR-INVALID-NAME (err u13))
(define-constant ERR-INVALID-JOB-ID (err u14))
(define-constant ERR-INVALID-MILESTONE-ID (err u15))
(define-constant ERR-INVALID-EVIDENCE (err u16))
(define-constant TIMEOUT-BLOCKS u1440) ;; ~10 days at 10min per block
(define-constant PLATFORM-FEE-RATE u25) ;; 2.5% fee (base 1000)
(define-constant MIN-STAKE-AMOUNT u1000000) ;; Minimum stake for freelancers
(define-constant MAX-MILESTONES u10)
(define-constant MAX-DEADLINE-BLOCKS u14400) ;; ~100 days maximum deadline

;; Data Structures
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

(define-map DisputeEvidence
    { job-id: uint, party: principal }
    {
        evidence-hash: (buff 32),
        timestamp: uint
    }
)

(define-data-var job-counter uint u0)
(define-data-var category-counter uint u0)

;; Helper functions for validation
(define-private (is-valid-freelancer (freelancer principal))
    (is-some (map-get? FreelancerStakes { user: freelancer })))

(define-private (is-valid-description (description (string-ascii 256)))
    (and 
        (not (is-eq description ""))
        (<= (len description) u256)))

(define-private (is-valid-category (category (string-ascii 64)))
    (and 
        (not (is-eq category ""))
        (<= (len category) u64)))

(define-private (is-valid-deadline (deadline uint))
    (and 
        (> deadline u0)
        (<= deadline MAX-DEADLINE-BLOCKS)))

(define-private (is-valid-name (name (string-ascii 64)))
    (and 
        (not (is-eq name ""))
        (<= (len name) u64)))

(define-private (is-valid-job-id (job-id uint))
    (and
        (> job-id u0)
        (<= job-id (var-get job-counter))))

(define-private (is-valid-milestone-id (job-id uint) (milestone-id uint))
    (match (map-get? Jobs { job-id: job-id })
        job (< milestone-id (get milestones-total job))
        false))

(define-private (is-valid-amount (amount uint))
    (> amount u0))

(define-private (is-valid-evidence-hash (evidence-hash (buff 32)))
    (not (is-eq evidence-hash 0x0000000000000000000000000000000000000000000000000000000000000000)))

;; Stake management
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

;; Job creation
(define-public (create-job 
    (freelancer principal) 
    (total-amount uint) 
    (description (string-ascii 256))
    (category (string-ascii 64))
    (deadline uint))
    
    (begin
        ;; Input validation
        (asserts! (is-valid-freelancer freelancer) ERR-INVALID-FREELANCER)
        (asserts! (is-valid-description description) ERR-INVALID-DESCRIPTION)
        (asserts! (is-valid-category category) ERR-INVALID-CATEGORY)
        (asserts! (is-valid-deadline deadline) ERR-INVALID-DEADLINE)
        (asserts! (is-valid-amount total-amount) ERR-INVALID-AMOUNT)
        
        (let ((job-id (+ (var-get job-counter) u1))
              (platform-fee (/ (* total-amount PLATFORM-FEE-RATE) u1000)))
            
            (asserts! (>= (stx-get-balance tx-sender) (+ total-amount platform-fee)) 
                     ERR-INSUFFICIENT-FUNDS)
            
            (try! (stx-transfer? (+ total-amount platform-fee) 
                                tx-sender 
                                (as-contract tx-sender)))
            
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
                    milestones-total: u0,
                    milestones-completed: u0
                }
            )
            
            (var-set job-counter job-id)
            (ok job-id))))

;; Add milestone
(define-public (add-milestone 
    (job-id uint)
    (description (string-ascii 256))
    (amount uint))
    
    (begin
        (asserts! (is-valid-job-id job-id) ERR-INVALID-JOB-ID)
        (asserts! (is-valid-description description) ERR-INVALID-DESCRIPTION)
        (asserts! (is-valid-amount amount) ERR-INVALID-AMOUNT)
        
        (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB)))
            (asserts! (is-eq tx-sender (get client job)) ERR-NOT-AUTHORIZED)
            (asserts! (is-eq (get status job) "pending") ERR-ALREADY-COMPLETED)
            (asserts! (< (get milestones-total job) MAX-MILESTONES) ERR-TOO-MANY-MILESTONES)
            
            (map-set Milestones
                { job-id: job-id, milestone-id: (get milestones-total job) }
                {
                    description: description,
                    amount: amount,
                    status: "pending",
                    deadline: (+ block-height TIMEOUT-BLOCKS)
                }
            )
            
            (map-set Jobs
                { job-id: job-id }
                (merge job {
                    milestones-total: (+ (get milestones-total job) u1)
                }))
                
            (ok true))))

;; Complete milestone
(define-public (complete-milestone (job-id uint) (milestone-id uint))
    (begin
        (asserts! (is-valid-job-id job-id) ERR-INVALID-JOB-ID)
        (asserts! (is-valid-milestone-id job-id milestone-id) ERR-INVALID-MILESTONE-ID)
        
        (let ((job (unwrap! (map-get? Jobs { job-id: job-id }) ERR-INVALID-JOB))
              (milestone (unwrap! (map-get? Milestones { job-id: job-id, milestone-id: milestone-id }) 
                                ERR-INVALID-MILESTONE)))
            
            (asserts! (is-eq (get status milestone) "pending") ERR-ALREADY-COMPLETED)
            (asserts! (is-eq tx-sender (get client job)) ERR-NOT-AUTHORIZED)
            
            (try! (as-contract (stx-transfer? (get amount milestone) 
                                            tx-sender 
                                            (get freelancer job))))
            
            (map-set Milestones
                { job-id: job-id, milestone-id: milestone-id }
                (merge milestone { status: "completed" }))
            
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
            
            (ok true))))

;; Dispute evidence submission
(define-public (submit-dispute-evidence (job-id uint) (evidence-hash (buff 32)))
    (begin
        (asserts! (is-valid-job-id job-id) ERR-INVALID-JOB-ID)
        (asserts! (is-valid-evidence-hash evidence-hash) ERR-INVALID-EVIDENCE)
        
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
            (ok true))))

;; Service category management
(define-public (create-service-category 
    (name (string-ascii 64))
    (description (string-ascii 256))
    (min-stake uint))
    
    (begin
        (asserts! (is-eq tx-sender contract-owner) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-name name) ERR-INVALID-NAME)
        (asserts! (is-valid-description description) ERR-INVALID-DESCRIPTION)
        (asserts! (>= min-stake MIN-STAKE-AMOUNT) ERR-INVALID-AMOUNT)
        
        (let ((category-id (+ (var-get category-counter) u1)))
            (map-set ServiceCategories
                { category-id: category-id }
                {
                    name: name,
                    description: description,
                    min-stake: min-stake
                }
            )
            (var-set category-counter category-id)
            (ok category-id))))

;; Read-only functions
(define-read-only (get-job (job-id uint))
    (map-get? Jobs { job-id: job-id }))

(define-read-only (get-milestone (job-id uint) (milestone-id uint))
    (map-get? Milestones { job-id: job-id, milestone-id: milestone-id }))

(define-read-only (get-user-rating (user principal))
    (map-get? UserRatings { user: user }))

(define-read-only (get-freelancer-stats (freelancer principal))
    (let ((rating (unwrap! (map-get? UserRatings { user: freelancer }) (err u8)))
          (stake (map-get? FreelancerStakes { user: freelancer })))
        (ok {
            rating: rating,
            stake: stake
        })))

(define-read-only (get-service-category (category-id uint))
    (map-get? ServiceCategories { category-id: category-id }))

(define-read-only (get-dispute-evidence (job-id uint) (party principal))
    (map-get? DisputeEvidence { job-id: job-id, party: party }))