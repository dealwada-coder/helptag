;; Reward Tokens Contract
;; Manages Helptag reward tokens for volunteer hours verification and distribution

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-NOT-FOUND (err u104))
(define-constant ERR-INVALID-HOURS (err u105))
(define-constant TOKEN-SYMBOL "HELP")
(define-constant TOKEN-NAME "Helptag")
(define-constant DECIMALS u6)
(define-constant TOKENS-PER-HOUR u10) ;; 10 tokens per verified hour
(define-constant MAX-HOURS-PER-LOG u24) ;; Max 24 hours per submission

;; Data maps and variables
(define-map token-balances
  { holder: principal }
  { balance: uint }
)

(define-map volunteer-hours
  { volunteer: principal, log-id: uint }
  {
    hours: uint,
    organization: principal,
    activity: (string-ascii 100),
    date: uint,
    verified: bool,
    verifier: (optional principal),
    tokens-earned: uint
  }
)

(define-map organization-approvers
  { organization: principal }
  {
    name: (string-ascii 50),
    verified: bool,
    total-hours-approved: uint,
    join-date: uint
  }
)

(define-map redemption-requests
  { volunteer: principal, request-id: uint }
  {
    tokens-amount: uint,
    reward-type: (string-ascii 50),
    description: (string-ascii 200),
    status: (string-ascii 20),
    requested-at: uint,
    processed-at: uint
  }
)

(define-data-var total-supply uint u0)
(define-data-var next-log-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var total-hours-verified uint u0)
(define-data-var active-volunteers uint u0)

;; Private functions

;; Mint tokens to a volunteer's balance
(define-private (mint-tokens (recipient principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? token-balances { holder: recipient }))))
  )
    (map-set token-balances
      { holder: recipient }
      { balance: (+ current-balance amount) }
    )
    (var-set total-supply (+ (var-get total-supply) amount))
    (ok amount)
  )
)

;; Burn tokens from volunteer's balance
(define-private (burn-tokens (holder principal) (amount uint))
  (let (
    (current-balance (default-to u0 (get balance (map-get? token-balances { holder: holder }))))
  )
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
    (map-set token-balances
      { holder: holder }
      { balance: (- current-balance amount) }
    )
    (var-set total-supply (- (var-get total-supply) amount))
    (ok amount)
  )
)

;; Check if organization is authorized to verify hours
(define-private (is-authorized-organization (org principal))
  (match (map-get? organization-approvers { organization: org })
    org-data (get verified org-data)
    false
  )
)

;; Public functions

;; Register as an organization (requires owner approval)
(define-public (register-organization (name (string-ascii 50)))
  (let (
    (existing-org (map-get? organization-approvers { organization: tx-sender }))
  )
    (asserts! (is-none existing-org) ERR-ALREADY-EXISTS)
    (asserts! (> (len name) u0) ERR-INVALID-AMOUNT)
    
    (map-set organization-approvers
      { organization: tx-sender }
      {
        name: name,
        verified: false, ;; Requires owner verification
        total-hours-approved: u0,
        join-date: stacks-block-height
      }
    )
    (ok tx-sender)
  )
)

;; Verify organization (only contract owner)
(define-public (verify-organization (org principal))
  (let (
    (org-data (unwrap! (map-get? organization-approvers { organization: org }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set organization-approvers
      { organization: org }
      (merge org-data { verified: true })
    )
    (ok org)
  )
)

;; Log volunteer hours (by volunteer)
(define-public (log-volunteer-hours 
  (hours uint) 
  (organization principal) 
  (activity (string-ascii 100))
)
  (let (
    (log-id (var-get next-log-id))
  )
    (asserts! (and (> hours u0) (<= hours MAX-HOURS-PER-LOG)) ERR-INVALID-HOURS)
    (asserts! (is-authorized-organization organization) ERR-NOT-AUTHORIZED)
    (asserts! (> (len activity) u0) ERR-INVALID-AMOUNT)
    
    (map-set volunteer-hours
      { volunteer: tx-sender, log-id: log-id }
      {
        hours: hours,
        organization: organization,
        activity: activity,
        date: stacks-block-height,
        verified: false,
        verifier: none,
        tokens-earned: u0
      }
    )
    
    (var-set next-log-id (+ log-id u1))
    (ok log-id)
  )
)

;; Verify volunteer hours (by organization)
(define-public (verify-volunteer-hours (volunteer principal) (log-id uint))
  (let (
    (hour-log (unwrap! (map-get? volunteer-hours { volunteer: volunteer, log-id: log-id }) ERR-NOT-FOUND))
    (org-data (unwrap! (map-get? organization-approvers { organization: tx-sender }) ERR-NOT-FOUND))
    (tokens-to-mint (* (get hours hour-log) TOKENS-PER-HOUR))
  )
    (asserts! (is-eq tx-sender (get organization hour-log)) ERR-NOT-AUTHORIZED)
    (asserts! (get verified org-data) ERR-NOT-AUTHORIZED)
    (asserts! (not (get verified hour-log)) ERR-ALREADY-EXISTS)
    
    ;; Update hour log as verified
    (map-set volunteer-hours
      { volunteer: volunteer, log-id: log-id }
      (merge hour-log {
        verified: true,
        verifier: (some tx-sender),
        tokens-earned: tokens-to-mint
      })
    )
    
    ;; Update organization stats
    (map-set organization-approvers
      { organization: tx-sender }
      (merge org-data {
        total-hours-approved: (+ (get total-hours-approved org-data) (get hours hour-log))
      })
    )
    
    ;; Mint tokens to volunteer
    (unwrap-panic (mint-tokens volunteer tokens-to-mint))
    
    ;; Update global stats
    (var-set total-hours-verified (+ (var-get total-hours-verified) (get hours hour-log)))
    
    (ok tokens-to-mint)
  )
)

;; Request token redemption
(define-public (request-redemption 
  (tokens-amount uint) 
  (reward-type (string-ascii 50)) 
  (description (string-ascii 200))
)
  (let (
    (current-balance (default-to u0 (get balance (map-get? token-balances { holder: tx-sender }))))
    (request-id (var-get next-request-id))
  )
    (asserts! (> tokens-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance tokens-amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (> (len reward-type) u0) ERR-INVALID-AMOUNT)
    
    (map-set redemption-requests
      { volunteer: tx-sender, request-id: request-id }
      {
        tokens-amount: tokens-amount,
        reward-type: reward-type,
        description: description,
        status: "pending",
        requested-at: stacks-block-height,
        processed-at: u0
      }
    )
    
    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

;; Process redemption request (by contract owner)
(define-public (process-redemption (volunteer principal) (request-id uint) (approved bool))
  (let (
    (redemption (unwrap! (map-get? redemption-requests { volunteer: volunteer, request-id: request-id }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status redemption) "pending") ERR-ALREADY-EXISTS)
    
    (if approved
      (begin
        ;; Burn tokens from volunteer balance
        (try! (burn-tokens volunteer (get tokens-amount redemption)))
        
        ;; Update redemption status
        (map-set redemption-requests
          { volunteer: volunteer, request-id: request-id }
          (merge redemption {
            status: "approved",
            processed-at: stacks-block-height
          })
        )
        (ok true)
      )
      (begin
        ;; Update redemption status as rejected
        (map-set redemption-requests
          { volunteer: volunteer, request-id: request-id }
          (merge redemption {
            status: "rejected",
            processed-at: stacks-block-height
          })
        )
        (ok false)
      )
    )
  )
)

;; Read-only functions

(define-read-only (get-token-balance (holder principal))
  (default-to u0 (get balance (map-get? token-balances { holder: holder })))
)

(define-read-only (get-volunteer-hours (volunteer principal) (log-id uint))
  (map-get? volunteer-hours { volunteer: volunteer, log-id: log-id })
)

(define-read-only (get-organization-info (org principal))
  (map-get? organization-approvers { organization: org })
)

(define-read-only (get-redemption-request (volunteer principal) (request-id uint))
  (map-get? redemption-requests { volunteer: volunteer, request-id: request-id })
)

(define-read-only (get-contract-stats)
  {
    total-supply: (var-get total-supply),
    total-hours-verified: (var-get total-hours-verified),
    active-volunteers: (var-get active-volunteers),
    next-log-id: (var-get next-log-id),
    next-request-id: (var-get next-request-id),
    tokens-per-hour: TOKENS-PER-HOUR
  }
)

(define-read-only (get-token-info)
  {
    name: TOKEN-NAME,
    symbol: TOKEN-SYMBOL,
    decimals: DECIMALS,
    total-supply: (var-get total-supply)
  }
)

