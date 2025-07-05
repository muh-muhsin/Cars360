;; Cars360 Access Control Contract
;; Manages user permissions, roles, and dataset access verification

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_USER_NOT_FOUND (err u301))
(define-constant ERR_INVALID_ROLE (err u302))
(define-constant ERR_ACCESS_DENIED (err u303))
(define-constant ERR_ALREADY_EXISTS (err u304))

;; Role constants
(define-constant ROLE_ADMIN u1)
(define-constant ROLE_VERIFIED_SELLER u2)
(define-constant ROLE_PREMIUM_BUYER u3)
(define-constant ROLE_BASIC_USER u4)

;; Data Variables
(define-data-var total-users uint u0)

;; Data Maps
(define-map user-profiles
  { user: principal }
  {
    role: uint,
    verified: bool,
    reputation-score: uint,
    joined-at: uint,
    last-active: uint,
    total-uploads: uint,
    total-purchases: uint,
    banned: bool
  }
)

(define-map user-permissions
  { user: principal, permission: (string-ascii 50) }
  { granted: bool, granted-at: uint, granted-by: principal }
)

(define-map verification-requests
  { user: principal }
  {
    requested-at: uint,
    documents-uri: (string-utf8 256),
    status: (string-ascii 20),
    reviewed-by: (optional principal),
    reviewed-at: (optional uint)
  }
)

(define-map user-ratings
  { rater: principal, rated-user: principal }
  { rating: uint, comment: (string-utf8 256), created-at: uint }
)

;; Read-only functions

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-user-permission (user principal) (permission (string-ascii 50)))
  (default-to { granted: false, granted-at: u0, granted-by: CONTRACT_OWNER }
              (map-get? user-permissions { user: user, permission: permission }))
)

(define-read-only (get-verification-request (user principal))
  (map-get? verification-requests { user: user })
)

(define-read-only (get-user-rating (rater principal) (rated-user principal))
  (map-get? user-ratings { rater: rater, rated-user: rated-user })
)

(define-read-only (is-verified-seller (user principal))
  (match (get-user-profile user)
    profile (and (get verified profile) (>= (get role profile) ROLE_VERIFIED_SELLER))
    false
  )
)

(define-read-only (can-upload-dataset (user principal))
  (match (get-user-profile user)
    profile (and (not (get banned profile))
                 (or (>= (get role profile) ROLE_VERIFIED_SELLER)
                     (get-user-permission user "upload-dataset")
                     (contract-call? .staking-pool is-premium-staker user)))
    false
  )
)

(define-read-only (can-purchase-dataset (user principal))
  (match (get-user-profile user)
    profile (and (not (get banned profile)) (>= (get role profile) ROLE_BASIC_USER))
    false
  )
)

(define-read-only (get-total-users)
  (var-get total-users)
)

(define-read-only (has-premium-benefits (user principal))
  (or (>= (get role (default-to { role: u0, verified: false, reputation-score: u0, joined-at: u0, last-active: u0, total-uploads: u0, total-purchases: u0, banned: false } (get-user-profile user))) ROLE_PREMIUM_BUYER)
      (contract-call? .staking-pool is-premium-staker user))
)

;; Public functions

(define-public (register-user)
  (let
    (
      (user tx-sender)
      (current-time block-height)
    )
    
    ;; Check if user already exists
    (asserts! (is-none (get-user-profile user)) ERR_ALREADY_EXISTS)
    
    ;; Create user profile
    (map-set user-profiles
      { user: user }
      {
        role: ROLE_BASIC_USER,
        verified: false,
        reputation-score: u50, ;; Starting reputation
        joined-at: current-time,
        last-active: current-time,
        total-uploads: u0,
        total-purchases: u0,
        banned: false
      }
    )
    
    ;; Increment total users
    (var-set total-users (+ (var-get total-users) u1))
    
    (ok true)
  )
)

(define-public (update-last-active)
  (match (get-user-profile tx-sender)
    profile
      (begin
        (map-set user-profiles
          { user: tx-sender }
          (merge profile { last-active: block-height })
        )
        (ok true)
      )
    (err ERR_USER_NOT_FOUND)
  )
)

(define-public (request-verification (documents-uri (string-utf8 256)))
  (let
    (
      (user tx-sender)
      (current-time block-height)
    )
    
    ;; Check if user exists
    (asserts! (is-some (get-user-profile user)) ERR_USER_NOT_FOUND)
    
    ;; Create verification request
    (map-set verification-requests
      { user: user }
      {
        requested-at: current-time,
        documents-uri: documents-uri,
        status: "pending",
        reviewed-by: none,
        reviewed-at: none
      }
    )
    
    (ok true)
  )
)

(define-public (rate-user 
  (rated-user principal) 
  (rating uint) 
  (comment (string-utf8 256))
)
  (let
    (
      (rater tx-sender)
      (current-time block-height)
    )
    
    ;; Validate rating (1-5 scale)
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_ROLE)
    
    ;; Check if both users exist
    (asserts! (is-some (get-user-profile rater)) ERR_USER_NOT_FOUND)
    (asserts! (is-some (get-user-profile rated-user)) ERR_USER_NOT_FOUND)
    
    ;; Users cannot rate themselves
    (asserts! (not (is-eq rater rated-user)) ERR_UNAUTHORIZED)
    
    ;; Record rating
    (map-set user-ratings
      { rater: rater, rated-user: rated-user }
      {
        rating: rating,
        comment: comment,
        created-at: current-time
      }
    )
    
    ;; Update rated user's reputation (simplified calculation)
    (match (get-user-profile rated-user)
      profile
        (let
          (
            (current-score (get reputation-score profile))
            (new-score (/ (+ (* current-score u9) (* rating u20)) u10)) ;; Weighted average
          )
          (map-set user-profiles
            { user: rated-user }
            (merge profile { reputation-score: new-score })
          )
        )
      false
    )
    
    (ok true)
  )
)

(define-public (increment-user-uploads (user principal))
  (begin
    ;; Only dataset registry can call this
    (asserts! (is-eq contract-caller .dataset-registry) ERR_UNAUTHORIZED)
    
    (match (get-user-profile user)
      profile
        (begin
          (map-set user-profiles
            { user: user }
            (merge profile { 
              total-uploads: (+ (get total-uploads profile) u1),
              last-active: block-height
            })
          )
          (ok true)
        )
      ERR_USER_NOT_FOUND
    )
  )
)

(define-public (increment-user-purchases (user principal))
  (begin
    ;; Only marketplace can call this
    (asserts! (is-eq contract-caller .marketplace) ERR_UNAUTHORIZED)
    
    (match (get-user-profile user)
      profile
        (begin
          (map-set user-profiles
            { user: user }
            (merge profile { 
              total-purchases: (+ (get total-purchases profile) u1),
              last-active: block-height
            })
          )
          (ok true)
        )
      ERR_USER_NOT_FOUND
    )
  )
)

;; Admin functions

(define-public (verify-user (user principal) (approved bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-user-profile user)
      profile
        (begin
          ;; Update user profile
          (map-set user-profiles
            { user: user }
            (merge profile { 
              verified: approved,
              role: (if approved ROLE_VERIFIED_SELLER (get role profile))
            })
          )
          
          ;; Update verification request
          (match (get-verification-request user)
            request
              (map-set verification-requests
                { user: user }
                (merge request {
                  status: (if approved "approved" "rejected"),
                  reviewed-by: (some tx-sender),
                  reviewed-at: (some block-height)
                })
              )
            false
          )
          
          (ok approved)
        )
      ERR_USER_NOT_FOUND
    )
  )
)

(define-public (grant-permission 
  (user principal) 
  (permission (string-ascii 50))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (map-set user-permissions
      { user: user, permission: permission }
      {
        granted: true,
        granted-at: block-height,
        granted-by: tx-sender
      }
    )
    
    (ok true)
  )
)

(define-public (ban-user (user principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    (match (get-user-profile user)
      profile
        (begin
          (map-set user-profiles
            { user: user }
            (merge profile { banned: true })
          )
          (ok true)
        )
      ERR_USER_NOT_FOUND
    )
  )
)
