;; Volunteer Management Contract
;; Manages volunteer profiles, skills, and activity tracking for the Helptag system

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-ALREADY-EXISTS (err u202))
(define-constant ERR-NOT-FOUND (err u203))
(define-constant ERR-PROFILE-INCOMPLETE (err u204))
(define-constant ERR-INVALID-RATING (err u205))
(define-constant MAX-SKILLS u10)
(define-constant MAX-NAME-LENGTH u50)
(define-constant MAX-BIO-LENGTH u200)
(define-constant MAX-SKILL-LENGTH u30)
(define-constant MIN-RATING u1)
(define-constant MAX-RATING u5)

;; Data maps and variables
(define-map volunteer-profiles
  { volunteer: principal }
  {
    name: (string-ascii 50),
    bio: (string-ascii 200),
    location: (string-ascii 50),
    skills: (list 10 (string-ascii 30)),
    total-hours: uint,
    verified-hours: uint,
    rating: uint,
    rating-count: uint,
    join-date: uint,
    last-active: uint,
    is-active: bool,
    badges-earned: (list 5 (string-ascii 20))
  }
)

(define-map volunteer-activity
  { volunteer: principal, activity-id: uint }
  {
    organization: principal,
    activity-type: (string-ascii 50),
    description: (string-ascii 150),
    hours-logged: uint,
    date: uint,
    status: (string-ascii 20),
    feedback: (optional (string-ascii 200)),
    rating-received: uint
  }
)

(define-map organization-profiles
  { organization: principal }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    contact-email: (string-ascii 50),
    verification-status: (string-ascii 20),
    total-volunteers: uint,
    total-hours-managed: uint,
    join-date: uint,
    categories: (list 5 (string-ascii 30))
  }
)

(define-map volunteer-organization-relationships
  { volunteer: principal, organization: principal }
  {
    start-date: uint,
    hours-contributed: uint,
    last-activity: uint,
    status: (string-ascii 20),
    mutual-rating: uint
  }
)

(define-map activity-categories
  { category: (string-ascii 30) }
  {
    description: (string-ascii 100),
    total-hours: uint,
    volunteer-count: uint,
    is-active: bool
  }
)

(define-map volunteer-certifications
  { volunteer: principal, cert-id: uint }
  {
    certification-name: (string-ascii 50),
    issuing-organization: principal,
    issue-date: uint,
    expiry-date: uint,
    verification-status: (string-ascii 20)
  }
)

(define-data-var total-volunteers uint u0)
(define-data-var total-organizations uint u0)
(define-data-var next-activity-id uint u1)
(define-data-var next-cert-id uint u1)
(define-data-var platform-total-hours uint u0)

;; Private functions

;; Check if volunteer profile is complete
(define-private (is-profile-complete (volunteer principal))
  (match (map-get? volunteer-profiles { volunteer: volunteer })
    profile (and 
      (> (len (get name profile)) u0)
      (> (len (get skills profile)) u0)
      (> (len (get location profile)) u0)
    )
    false
  )
)

;; Calculate volunteer's overall rating
(define-private (calculate-rating (total-rating uint) (rating-count uint))
  (if (> rating-count u0)
    (/ total-rating rating-count)
    u0
  )
)

;; Update volunteer's activity timestamp
(define-private (update-volunteer-activity (volunteer principal))
  (match (map-get? volunteer-profiles { volunteer: volunteer })
    profile
    (map-set volunteer-profiles
      { volunteer: volunteer }
      (merge profile { last-active: stacks-block-height })
    )
    false
  )
)

;; Public functions

;; Register volunteer profile
(define-public (register-volunteer 
  (name (string-ascii 50))
  (bio (string-ascii 200))
  (location (string-ascii 50))
  (skills (list 10 (string-ascii 30)))
)
  (let (
    (existing-profile (map-get? volunteer-profiles { volunteer: tx-sender }))
  )
    (asserts! (is-none existing-profile) ERR-ALREADY-EXISTS)
    (asserts! (and (> (len name) u0) (<= (len name) MAX-NAME-LENGTH)) ERR-INVALID-INPUT)
    (asserts! (<= (len bio) MAX-BIO-LENGTH) ERR-INVALID-INPUT)
    (asserts! (and (> (len skills) u0) (<= (len skills) MAX-SKILLS)) ERR-INVALID-INPUT)
    
    (map-set volunteer-profiles
      { volunteer: tx-sender }
      {
        name: name,
        bio: bio,
        location: location,
        skills: skills,
        total-hours: u0,
        verified-hours: u0,
        rating: u0,
        rating-count: u0,
        join-date: stacks-block-height,
        last-active: stacks-block-height,
        is-active: true,
        badges-earned: (list)
      }
    )
    
    (var-set total-volunteers (+ (var-get total-volunteers) u1))
    (ok tx-sender)
  )
)

;; Update volunteer profile
(define-public (update-volunteer-profile
  (name (string-ascii 50))
  (bio (string-ascii 200))
  (location (string-ascii 50))
  (skills (list 10 (string-ascii 30)))
)
  (let (
    (profile (unwrap! (map-get? volunteer-profiles { volunteer: tx-sender }) ERR-NOT-FOUND))
  )
    (asserts! (and (> (len name) u0) (<= (len name) MAX-NAME-LENGTH)) ERR-INVALID-INPUT)
    (asserts! (<= (len bio) MAX-BIO-LENGTH) ERR-INVALID-INPUT)
    (asserts! (and (> (len skills) u0) (<= (len skills) MAX-SKILLS)) ERR-INVALID-INPUT)
    
    (map-set volunteer-profiles
      { volunteer: tx-sender }
      (merge profile {
        name: name,
        bio: bio,
        location: location,
        skills: skills,
        last-active: stacks-block-height
      })
    )
    (ok true)
  )
)

;; Register organization profile
(define-public (register-organization
  (name (string-ascii 50))
  (description (string-ascii 200))
  (contact-email (string-ascii 50))
  (categories (list 5 (string-ascii 30)))
)
  (let (
    (existing-org (map-get? organization-profiles { organization: tx-sender }))
  )
    (asserts! (is-none existing-org) ERR-ALREADY-EXISTS)
    (asserts! (and (> (len name) u0) (<= (len name) MAX-NAME-LENGTH)) ERR-INVALID-INPUT)
    (asserts! (> (len contact-email) u0) ERR-INVALID-INPUT)
    
    (map-set organization-profiles
      { organization: tx-sender }
      {
        name: name,
        description: description,
        contact-email: contact-email,
        verification-status: "pending",
        total-volunteers: u0,
        total-hours-managed: u0,
        join-date: stacks-block-height,
        categories: categories
      }
    )
    
    (var-set total-organizations (+ (var-get total-organizations) u1))
    (ok tx-sender)
  )
)

;; Log volunteer activity
(define-public (log-activity
  (organization principal)
  (activity-type (string-ascii 50))
  (description (string-ascii 150))
  (hours-logged uint)
)
  (let (
    (volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: tx-sender }) ERR-NOT-FOUND))
    (org-profile (unwrap! (map-get? organization-profiles { organization: organization }) ERR-NOT-FOUND))
    (activity-id (var-get next-activity-id))
  )
    (asserts! (is-profile-complete tx-sender) ERR-PROFILE-INCOMPLETE)
    (asserts! (> hours-logged u0) ERR-INVALID-INPUT)
    (asserts! (> (len activity-type) u0) ERR-INVALID-INPUT)
    
    (map-set volunteer-activity
      { volunteer: tx-sender, activity-id: activity-id }
      {
        organization: organization,
        activity-type: activity-type,
        description: description,
        hours-logged: hours-logged,
        date: stacks-block-height,
        status: "logged",
        feedback: none,
        rating-received: u0
      }
    )
    
    ;; Update volunteer's total hours
    (map-set volunteer-profiles
      { volunteer: tx-sender }
      (merge volunteer-profile {
        total-hours: (+ (get total-hours volunteer-profile) hours-logged),
        last-active: stacks-block-height
      })
    )
    
    ;; Update relationship if exists, create if not
    (let (
      (relationship (map-get? volunteer-organization-relationships 
        { volunteer: tx-sender, organization: organization })
      )
    )
      (if (is-some relationship)
        (let ((rel-data (unwrap-panic relationship)))
          (map-set volunteer-organization-relationships
            { volunteer: tx-sender, organization: organization }
            (merge rel-data {
              hours-contributed: (+ (get hours-contributed rel-data) hours-logged),
              last-activity: stacks-block-height
            })
          )
        )
        (map-set volunteer-organization-relationships
          { volunteer: tx-sender, organization: organization }
          {
            start-date: stacks-block-height,
            hours-contributed: hours-logged,
            last-activity: stacks-block-height,
            status: "active",
            mutual-rating: u0
          }
        )
      )
    )
    
    (var-set next-activity-id (+ activity-id u1))
    (var-set platform-total-hours (+ (var-get platform-total-hours) hours-logged))
    (ok activity-id)
  )
)

;; Rate volunteer performance (by organization)
(define-public (rate-volunteer-activity
  (volunteer principal)
  (activity-id uint)
  (rating uint)
  (feedback (string-ascii 200))
)
  (let (
    (activity (unwrap! (map-get? volunteer-activity { volunteer: volunteer, activity-id: activity-id }) ERR-NOT-FOUND))
    (volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: volunteer }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (get organization activity)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= rating MIN-RATING) (<= rating MAX-RATING)) ERR-INVALID-RATING)
    (asserts! (is-eq (get status activity) "logged") ERR-INVALID-INPUT)
    
    ;; Update activity with rating and feedback
    (map-set volunteer-activity
      { volunteer: volunteer, activity-id: activity-id }
      (merge activity {
        status: "rated",
        feedback: (some feedback),
        rating-received: rating
      })
    )
    
    ;; Update volunteer's overall rating
    (let (
      (new-rating-count (+ (get rating-count volunteer-profile) u1))
      (new-total-rating (+ (* (get rating volunteer-profile) (get rating-count volunteer-profile)) rating))
      (new-average (/ new-total-rating new-rating-count))
    )
      (map-set volunteer-profiles
        { volunteer: volunteer }
        (merge volunteer-profile {
          rating: new-average,
          rating-count: new-rating-count
        })
      )
    )
    
    (ok rating)
  )
)

;; Issue certification to volunteer (by organization)
(define-public (issue-certification
  (volunteer principal)
  (certification-name (string-ascii 50))
  (expiry-date uint)
)
  (let (
    (org-profile (unwrap! (map-get? organization-profiles { organization: tx-sender }) ERR-NOT-FOUND))
    (volunteer-profile (unwrap! (map-get? volunteer-profiles { volunteer: volunteer }) ERR-NOT-FOUND))
    (cert-id (var-get next-cert-id))
  )
    (asserts! (is-eq (get verification-status org-profile) "verified") ERR-NOT-AUTHORIZED)
    (asserts! (> (len certification-name) u0) ERR-INVALID-INPUT)
    (asserts! (> expiry-date stacks-block-height) ERR-INVALID-INPUT)
    
    (map-set volunteer-certifications
      { volunteer: volunteer, cert-id: cert-id }
      {
        certification-name: certification-name,
        issuing-organization: tx-sender,
        issue-date: stacks-block-height,
        expiry-date: expiry-date,
        verification-status: "valid"
      }
    )
    
    (var-set next-cert-id (+ cert-id u1))
    (ok cert-id)
  )
)

;; Verify organization (only contract owner)
(define-public (verify-organization (org principal))
  (let (
    (org-profile (unwrap! (map-get? organization-profiles { organization: org }) ERR-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (map-set organization-profiles
      { organization: org }
      (merge org-profile { verification-status: "verified" })
    )
    (ok org)
  )
)

;; Read-only functions

(define-read-only (get-volunteer-profile (volunteer principal))
  (map-get? volunteer-profiles { volunteer: volunteer })
)

(define-read-only (get-organization-profile (org principal))
  (map-get? organization-profiles { organization: org })
)

(define-read-only (get-volunteer-activity (volunteer principal) (activity-id uint))
  (map-get? volunteer-activity { volunteer: volunteer, activity-id: activity-id })
)

(define-read-only (get-volunteer-organization-relationship (volunteer principal) (organization principal))
  (map-get? volunteer-organization-relationships { volunteer: volunteer, organization: organization })
)

(define-read-only (get-volunteer-certification (volunteer principal) (cert-id uint))
  (map-get? volunteer-certifications { volunteer: volunteer, cert-id: cert-id })
)

(define-read-only (get-platform-stats)
  {
    total-volunteers: (var-get total-volunteers),
    total-organizations: (var-get total-organizations),
    platform-total-hours: (var-get platform-total-hours),
    next-activity-id: (var-get next-activity-id),
    next-cert-id: (var-get next-cert-id)
  }
)

(define-read-only (is-volunteer-registered (volunteer principal))
  (is-some (map-get? volunteer-profiles { volunteer: volunteer }))
)

(define-read-only (is-organization-verified (org principal))
  (match (map-get? organization-profiles { organization: org })
    org-data (is-eq (get verification-status org-data) "verified")
    false
  )
)

