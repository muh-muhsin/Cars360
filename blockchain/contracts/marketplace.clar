;; Cars360 Marketplace Contract
;; Handles STX payments, dataset purchases, and royalty distributions

;; Import dataset registry contract
(use-trait dataset-registry-trait .dataset-registry.dataset-registry-trait)

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_INSUFFICIENT_FUNDS (err u201))
(define-constant ERR_DATASET_NOT_FOUND (err u202))
(define-constant ERR_ALREADY_PURCHASED (err u203))
(define-constant ERR_DATASET_INACTIVE (err u204))
(define-constant ERR_TRANSFER_FAILED (err u205))
(define-constant ERR_INVALID_AMOUNT (err u206))

;; Data Variables
(define-data-var platform-wallet principal CONTRACT_OWNER)
(define-data-var total-volume uint u0)
(define-data-var total-transactions uint u0)

;; Data Maps
(define-map seller-earnings
  { seller: principal }
  { total-earned: uint, withdrawable: uint }
)

(define-map transaction-history
  { tx-id: uint }
  {
    buyer: principal,
    seller: principal,
    dataset-id: uint,
    amount: uint,
    platform-fee: uint,
    timestamp: uint
  }
)

(define-map purchase-receipts
  { buyer: principal, dataset-id: uint }
  {
    amount-paid: uint,
    purchase-date: uint,
    tx-id: uint
  }
)

;; Data variable for transaction counter
(define-data-var next-tx-id uint u1)

;; Read-only functions

(define-read-only (get-seller-earnings (seller principal))
  (default-to { total-earned: u0, withdrawable: u0 } 
              (map-get? seller-earnings { seller: seller }))
)

(define-read-only (get-transaction (tx-id uint))
  (map-get? transaction-history { tx-id: tx-id })
)

(define-read-only (get-purchase-receipt (buyer principal) (dataset-id uint))
  (map-get? purchase-receipts { buyer: buyer, dataset-id: dataset-id })
)

(define-read-only (get-platform-wallet)
  (var-get platform-wallet)
)

(define-read-only (get-marketplace-stats)
  {
    total-volume: (var-get total-volume),
    total-transactions: (var-get total-transactions)
  }
)

(define-read-only (calculate-fees (price uint))
  (let
    (
      (platform-fee-percentage (contract-call? .dataset-registry get-platform-fee-percentage))
      (platform-fee (/ (* price platform-fee-percentage) u100))
      (seller-amount (- price platform-fee))
    )
    {
      platform-fee: platform-fee,
      seller-amount: seller-amount,
      total-price: price
    }
  )
)

(define-read-only (calculate-fees-with-staking-discount (price uint) (buyer principal))
  (let
    (
      (base-platform-fee-percentage (contract-call? .dataset-registry get-platform-fee-percentage))
      (staking-discount (contract-call? .staking-pool get-staking-discount buyer))
      (discounted-fee-percentage (- base-platform-fee-percentage (/ (* base-platform-fee-percentage staking-discount) u100)))
      (platform-fee (/ (* price discounted-fee-percentage) u100))
      (seller-amount (- price platform-fee))
    )
    {
      platform-fee: platform-fee,
      seller-amount: seller-amount,
      total-price: price,
      discount-applied: staking-discount,
      savings: (- (/ (* price base-platform-fee-percentage) u100) platform-fee)
    }
  )
)

;; Public functions

(define-public (purchase-dataset (dataset-id uint))
  (let
    (
      (dataset-info (unwrap! (contract-call? .dataset-registry get-dataset dataset-id) ERR_DATASET_NOT_FOUND))
      (buyer tx-sender)
      (seller (get owner dataset-info))
      (price (get price dataset-info))
      (fee-calculation (calculate-fees-with-staking-discount price buyer))
      (platform-fee (get platform-fee fee-calculation))
      (seller-amount (get seller-amount fee-calculation))
      (tx-id (var-get next-tx-id))
    )
    
    ;; Validate dataset is active
    (asserts! (get active dataset-info) ERR_DATASET_INACTIVE)
    
    ;; Check if already purchased
    (asserts! (is-none (get-purchase-receipt buyer dataset-id)) ERR_ALREADY_PURCHASED)
    
    ;; Check if buyer has sufficient funds
    (asserts! (>= (stx-get-balance buyer) price) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer STX from buyer to seller
    (unwrap! (stx-transfer? seller-amount buyer seller) ERR_TRANSFER_FAILED)
    
    ;; Transfer platform fee to platform wallet
    (unwrap! (stx-transfer? platform-fee buyer (var-get platform-wallet)) ERR_TRANSFER_FAILED)
    
    ;; Grant access to dataset
    (unwrap! (contract-call? .dataset-registry grant-access dataset-id buyer) ERR_TRANSFER_FAILED)
    
    ;; Update seller earnings
    (let
      (
        (current-earnings (get-seller-earnings seller))
        (new-total (+ (get total-earned current-earnings) seller-amount))
        (new-withdrawable (+ (get withdrawable current-earnings) seller-amount))
      )
      (map-set seller-earnings
        { seller: seller }
        { total-earned: new-total, withdrawable: new-withdrawable }
      )
    )
    
    ;; Record transaction
    (map-set transaction-history
      { tx-id: tx-id }
      {
        buyer: buyer,
        seller: seller,
        dataset-id: dataset-id,
        amount: price,
        platform-fee: platform-fee,
        timestamp: block-height
      }
    )
    
    ;; Record purchase receipt
    (map-set purchase-receipts
      { buyer: buyer, dataset-id: dataset-id }
      {
        amount-paid: price,
        purchase-date: block-height,
        tx-id: tx-id
      }
    )
    
    ;; Update marketplace stats
    (var-set total-volume (+ (var-get total-volume) price))
    (var-set total-transactions (+ (var-get total-transactions) u1))
    (var-set next-tx-id (+ tx-id u1))
    
    (ok tx-id)
  )
)

(define-public (withdraw-earnings)
  (let
    (
      (seller tx-sender)
      (earnings (get-seller-earnings seller))
      (withdrawable-amount (get withdrawable earnings))
    )
    
    ;; Check if there are earnings to withdraw
    (asserts! (> withdrawable-amount u0) ERR_INSUFFICIENT_FUNDS)
    
    ;; Transfer earnings to seller
    (unwrap! (as-contract (stx-transfer? withdrawable-amount tx-sender seller)) ERR_TRANSFER_FAILED)
    
    ;; Update seller earnings (set withdrawable to 0)
    (map-set seller-earnings
      { seller: seller }
      { 
        total-earned: (get total-earned earnings),
        withdrawable: u0
      }
    )
    
    (ok withdrawable-amount)
  )
)

(define-public (bulk-purchase (dataset-ids (list 10 uint)))
  (let
    (
      (buyer tx-sender)
      (total-cost (fold calculate-total-cost dataset-ids u0))
    )
    
    ;; Check if buyer has sufficient funds for all purchases
    (asserts! (>= (stx-get-balance buyer) total-cost) ERR_INSUFFICIENT_FUNDS)
    
    ;; Process each purchase
    (fold process-bulk-purchase dataset-ids (ok (list)))
  )
)

;; Private functions

(define-private (calculate-total-cost (dataset-id uint) (current-total uint))
  (match (contract-call? .dataset-registry get-dataset dataset-id)
    dataset-info (+ current-total (get price dataset-info))
    current-total
  )
)

(define-private (process-bulk-purchase 
  (dataset-id uint) 
  (previous-result (response (list 10 uint) uint))
)
  (match previous-result
    success-list
      (match (purchase-dataset dataset-id)
        tx-id (ok (unwrap! (as-max-len? (append success-list tx-id) u10) ERR_INVALID_AMOUNT))
        error-code (err error-code)
      )
    error-code (err error-code)
  )
)

;; Admin functions

(define-public (set-platform-wallet (new-wallet principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set platform-wallet new-wallet)
    (ok true)
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (unwrap! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)) ERR_TRANSFER_FAILED)
    (ok true)
  )
)
