;; Cars360 Staking Pool Contract
;; Enables users to stake STX tokens for rewards and governance rights

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_INVALID_AMOUNT (err u401))
(define-constant ERR_INVALID_POOL (err u402))
(define-constant ERR_STAKE_NOT_FOUND (err u403))
(define-constant ERR_STAKE_LOCKED (err u404))
(define-constant ERR_INSUFFICIENT_BALANCE (err u405))
(define-constant ERR_TRANSFER_FAILED (err u406))
(define-constant ERR_POOL_INACTIVE (err u407))
(define-constant ERR_INVALID_DURATION (err u408))

;; Pool constants
(define-constant POOL_30_DAYS u1)
(define-constant POOL_90_DAYS u2)
(define-constant POOL_180_DAYS u3)
(define-constant POOL_365_DAYS u4)

;; Time constants (in blocks, ~10 minutes per block)
(define-constant BLOCKS_PER_DAY u144)
(define-constant DAYS_30 (* u30 BLOCKS_PER_DAY))
(define-constant DAYS_90 (* u90 BLOCKS_PER_DAY))
(define-constant DAYS_180 (* u180 BLOCKS_PER_DAY))
(define-constant DAYS_365 (* u365 BLOCKS_PER_DAY))

;; Reward rates (APY in basis points, e.g., 500 = 5%)
(define-constant APY_30_DAYS u500)   ;; 5% APY
(define-constant APY_90_DAYS u800)   ;; 8% APY
(define-constant APY_180_DAYS u1200) ;; 12% APY
(define-constant APY_365_DAYS u1800) ;; 18% APY

;; Early withdrawal penalty rates (in basis points)
(define-constant PENALTY_30_DAYS u1000)  ;; 10%
(define-constant PENALTY_90_DAYS u1500)  ;; 15%
(define-constant PENALTY_180_DAYS u2000) ;; 20%
(define-constant PENALTY_365_DAYS u2500) ;; 25%

;; Data Variables
(define-data-var next-stake-id uint u1)
(define-data-var total-staked uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var reward-pool-balance uint u0)

;; Data Maps
(define-map staking-pools
  { pool-id: uint }
  {
    name: (string-ascii 50),
    lock-duration: uint,
    apy-rate: uint,
    penalty-rate: uint,
    active: bool,
    total-staked: uint,
    total-stakers: uint
  }
)

(define-map user-stakes
  { stake-id: uint }
  {
    staker: principal,
    pool-id: uint,
    amount: uint,
    start-block: uint,
    end-block: uint,
    rewards-claimed: uint,
    active: bool
  }
)

(define-map user-stake-ids
  { staker: principal }
  { stake-ids: (list 50 uint) }
)

(define-map staker-stats
  { staker: principal }
  {
    total-staked: uint,
    total-rewards: uint,
    active-stakes: uint,
    governance-weight: uint
  }
)

;; Initialize staking pools
(map-set staking-pools { pool-id: POOL_30_DAYS }
  {
    name: "30-Day Pool",
    lock-duration: DAYS_30,
    apy-rate: APY_30_DAYS,
    penalty-rate: PENALTY_30_DAYS,
    active: true,
    total-staked: u0,
    total-stakers: u0
  }
)

(map-set staking-pools { pool-id: POOL_90_DAYS }
  {
    name: "90-Day Pool",
    lock-duration: DAYS_90,
    apy-rate: APY_90_DAYS,
    penalty-rate: PENALTY_90_DAYS,
    active: true,
    total-staked: u0,
    total-stakers: u0
  }
)

(map-set staking-pools { pool-id: POOL_180_DAYS }
  {
    name: "180-Day Pool",
    lock-duration: DAYS_180,
    apy-rate: APY_180_DAYS,
    penalty-rate: PENALTY_180_DAYS,
    active: true,
    total-staked: u0,
    total-stakers: u0
  }
)

(map-set staking-pools { pool-id: POOL_365_DAYS }
  {
    name: "365-Day Pool",
    lock-duration: DAYS_365,
    apy-rate: APY_365_DAYS,
    penalty-rate: PENALTY_365_DAYS,
    active: true,
    total-staked: u0,
    total-stakers: u0
  }
)

;; Read-only functions

(define-read-only (get-staking-pool (pool-id uint))
  (map-get? staking-pools { pool-id: pool-id })
)

(define-read-only (get-user-stake (stake-id uint))
  (map-get? user-stakes { stake-id: stake-id })
)

(define-read-only (get-user-stake-ids (staker principal))
  (default-to { stake-ids: (list) } (map-get? user-stake-ids { staker: staker }))
)

(define-read-only (get-staker-stats (staker principal))
  (default-to 
    { total-staked: u0, total-rewards: u0, active-stakes: u0, governance-weight: u0 }
    (map-get? staker-stats { staker: staker })
  )
)

(define-read-only (get-total-staked)
  (var-get total-staked)
)

(define-read-only (get-reward-pool-balance)
  (var-get reward-pool-balance)
)

(define-read-only (calculate-rewards (stake-id uint))
  (match (get-user-stake stake-id)
    stake-info
      (match (get-staking-pool (get pool-id stake-info))
        pool-info
          (let
            (
              (amount (get amount stake-info))
              (apy-rate (get apy-rate pool-info))
              (blocks-staked (- block-height (get start-block stake-info)))
              (annual-blocks (* u365 BLOCKS_PER_DAY))
              (rewards (/ (* (* amount apy-rate) blocks-staked) (* u10000 annual-blocks)))
            )
            (ok rewards)
          )
        ERR_INVALID_POOL
      )
    ERR_STAKE_NOT_FOUND
  )
)

(define-read-only (calculate-early-withdrawal-penalty (stake-id uint))
  (match (get-user-stake stake-id)
    stake-info
      (if (>= block-height (get end-block stake-info))
        (ok u0) ;; No penalty if lock period completed
        (match (get-staking-pool (get pool-id stake-info))
          pool-info
            (let
              (
                (amount (get amount stake-info))
                (penalty-rate (get penalty-rate pool-info))
                (penalty (/ (* amount penalty-rate) u10000))
              )
              (ok penalty)
            )
          ERR_INVALID_POOL
        )
      )
    ERR_STAKE_NOT_FOUND
  )
)

(define-read-only (get-staking-discount (staker principal))
  (let
    (
      (stats (get-staker-stats staker))
      (total-staked (get total-staked stats))
    )
    (cond
      ((>= total-staked u10000000000) u50) ;; 50% discount for 10,000+ STX
      ((>= total-staked u5000000000) u30)  ;; 30% discount for 5,000+ STX
      ((>= total-staked u1000000000) u20)  ;; 20% discount for 1,000+ STX
      ((>= total-staked u100000000) u10)   ;; 10% discount for 100+ STX
      (u0) ;; No discount
    )
  )
)

(define-read-only (is-premium-staker (staker principal))
  (let
    (
      (stats (get-staker-stats staker))
      (total-staked (get total-staked stats))
    )
    (>= total-staked u1000000000) ;; Premium status for 1,000+ STX staked
  )
)

;; Public functions

(define-public (stake-tokens (amount uint) (pool-id uint))
  (let
    (
      (staker tx-sender)
      (stake-id (var-get next-stake-id))
      (current-block block-height)
    )

    ;; Validate inputs
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (stx-get-balance staker) amount) ERR_INSUFFICIENT_BALANCE)

    ;; Validate pool exists and is active
    (match (get-staking-pool pool-id)
      pool-info
        (begin
          (asserts! (get active pool-info) ERR_POOL_INACTIVE)

          ;; Transfer STX to contract
          (unwrap! (stx-transfer? amount staker (as-contract tx-sender)) ERR_TRANSFER_FAILED)

          ;; Create stake record
          (map-set user-stakes
            { stake-id: stake-id }
            {
              staker: staker,
              pool-id: pool-id,
              amount: amount,
              start-block: current-block,
              end-block: (+ current-block (get lock-duration pool-info)),
              rewards-claimed: u0,
              active: true
            }
          )

          ;; Update user stake IDs
          (let
            (
              (current-stake-ids (get stake-ids (get-user-stake-ids staker)))
              (updated-stake-ids (unwrap! (as-max-len? (append current-stake-ids stake-id) u50) ERR_INVALID_AMOUNT))
            )
            (map-set user-stake-ids
              { staker: staker }
              { stake-ids: updated-stake-ids }
            )
          )

          ;; Update staker stats
          (let
            (
              (current-stats (get-staker-stats staker))
              (new-total-staked (+ (get total-staked current-stats) amount))
              (new-active-stakes (+ (get active-stakes current-stats) u1))
              (new-governance-weight (+ (get governance-weight current-stats) amount))
            )
            (map-set staker-stats
              { staker: staker }
              {
                total-staked: new-total-staked,
                total-rewards: (get total-rewards current-stats),
                active-stakes: new-active-stakes,
                governance-weight: new-governance-weight
              }
            )
          )

          ;; Update pool stats
          (map-set staking-pools
            { pool-id: pool-id }
            (merge pool-info {
              total-staked: (+ (get total-staked pool-info) amount),
              total-stakers: (+ (get total-stakers pool-info) u1)
            })
          )

          ;; Update global stats
          (var-set total-staked (+ (var-get total-staked) amount))
          (var-set next-stake-id (+ stake-id u1))

          (ok stake-id)
        )
      ERR_INVALID_POOL
    )
  )
)

(define-public (unstake-tokens (stake-id uint))
  (match (get-user-stake stake-id)
    stake-info
      (begin
        ;; Verify ownership
        (asserts! (is-eq (get staker stake-info) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get active stake-info) ERR_STAKE_NOT_FOUND)

        (let
          (
            (amount (get amount stake-info))
            (pool-id (get pool-id stake-info))
            (is-early (< block-height (get end-block stake-info)))
            (penalty (if is-early
                       (unwrap! (calculate-early-withdrawal-penalty stake-id) ERR_INVALID_AMOUNT)
                       u0))
            (withdrawal-amount (- amount penalty))
          )

          ;; Transfer tokens back to user (minus penalty)
          (unwrap! (as-contract (stx-transfer? withdrawal-amount tx-sender (get staker stake-info))) ERR_TRANSFER_FAILED)

          ;; If there's a penalty, add it to reward pool
          (if (> penalty u0)
            (var-set reward-pool-balance (+ (var-get reward-pool-balance) penalty))
            true
          )

          ;; Mark stake as inactive
          (map-set user-stakes
            { stake-id: stake-id }
            (merge stake-info { active: false })
          )

          ;; Update staker stats
          (let
            (
              (current-stats (get-staker-stats tx-sender))
              (new-total-staked (- (get total-staked current-stats) amount))
              (new-active-stakes (- (get active-stakes current-stats) u1))
              (new-governance-weight (- (get governance-weight current-stats) amount))
            )
            (map-set staker-stats
              { staker: tx-sender }
              {
                total-staked: new-total-staked,
                total-rewards: (get total-rewards current-stats),
                active-stakes: new-active-stakes,
                governance-weight: new-governance-weight
              }
            )
          )

          ;; Update pool stats
          (match (get-staking-pool pool-id)
            pool-info
              (map-set staking-pools
                { pool-id: pool-id }
                (merge pool-info {
                  total-staked: (- (get total-staked pool-info) amount),
                  total-stakers: (- (get total-stakers pool-info) u1)
                })
              )
            false
          )

          ;; Update global stats
          (var-set total-staked (- (var-get total-staked) amount))

          (ok { withdrawal-amount: withdrawal-amount, penalty: penalty })
        )
      )
    ERR_STAKE_NOT_FOUND
  )
)

(define-public (claim-rewards (stake-id uint))
  (match (get-user-stake stake-id)
    stake-info
      (begin
        ;; Verify ownership and active stake
        (asserts! (is-eq (get staker stake-info) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get active stake-info) ERR_STAKE_NOT_FOUND)

        (let
          (
            (rewards (unwrap! (calculate-rewards stake-id) ERR_INVALID_AMOUNT))
            (unclaimed-rewards (- rewards (get rewards-claimed stake-info)))
          )

          ;; Check if there are rewards to claim
          (asserts! (> unclaimed-rewards u0) ERR_INVALID_AMOUNT)

          ;; Check if reward pool has sufficient balance
          (asserts! (>= (var-get reward-pool-balance) unclaimed-rewards) ERR_INSUFFICIENT_BALANCE)

          ;; Transfer rewards to user
          (unwrap! (as-contract (stx-transfer? unclaimed-rewards tx-sender (get staker stake-info))) ERR_TRANSFER_FAILED)

          ;; Update stake record
          (map-set user-stakes
            { stake-id: stake-id }
            (merge stake-info { rewards-claimed: rewards })
          )

          ;; Update staker stats
          (let
            (
              (current-stats (get-staker-stats tx-sender))
              (new-total-rewards (+ (get total-rewards current-stats) unclaimed-rewards))
            )
            (map-set staker-stats
              { staker: tx-sender }
              (merge current-stats { total-rewards: new-total-rewards })
            )
          )

          ;; Update global stats
          (var-set reward-pool-balance (- (var-get reward-pool-balance) unclaimed-rewards))
          (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) unclaimed-rewards))

          (ok unclaimed-rewards)
        )
      )
    ERR_STAKE_NOT_FOUND
  )
)

(define-public (compound-stake (stake-id uint))
  (match (get-user-stake stake-id)
    stake-info
      (begin
        ;; Verify ownership and active stake
        (asserts! (is-eq (get staker stake-info) tx-sender) ERR_UNAUTHORIZED)
        (asserts! (get active stake-info) ERR_STAKE_NOT_FOUND)

        (let
          (
            (rewards (unwrap! (calculate-rewards stake-id) ERR_INVALID_AMOUNT))
            (unclaimed-rewards (- rewards (get rewards-claimed stake-info)))
            (new-amount (+ (get amount stake-info) unclaimed-rewards))
          )

          ;; Check if there are rewards to compound
          (asserts! (> unclaimed-rewards u0) ERR_INVALID_AMOUNT)

          ;; Check if reward pool has sufficient balance
          (asserts! (>= (var-get reward-pool-balance) unclaimed-rewards) ERR_INSUFFICIENT_BALANCE)

          ;; Update stake with compounded amount
          (map-set user-stakes
            { stake-id: stake-id }
            (merge stake-info {
              amount: new-amount,
              rewards-claimed: rewards
            })
          )

          ;; Update staker stats
          (let
            (
              (current-stats (get-staker-stats tx-sender))
              (new-total-staked (+ (get total-staked current-stats) unclaimed-rewards))
              (new-total-rewards (+ (get total-rewards current-stats) unclaimed-rewards))
              (new-governance-weight (+ (get governance-weight current-stats) unclaimed-rewards))
            )
            (map-set staker-stats
              { staker: tx-sender }
              {
                total-staked: new-total-staked,
                total-rewards: new-total-rewards,
                active-stakes: (get active-stakes current-stats),
                governance-weight: new-governance-weight
              }
            )
          )

          ;; Update pool stats
          (match (get-staking-pool (get pool-id stake-info))
            pool-info
              (map-set staking-pools
                { pool-id: (get pool-id stake-info) }
                (merge pool-info {
                  total-staked: (+ (get total-staked pool-info) unclaimed-rewards)
                })
              )
            false
          )

          ;; Update global stats
          (var-set total-staked (+ (var-get total-staked) unclaimed-rewards))
          (var-set reward-pool-balance (- (var-get reward-pool-balance) unclaimed-rewards))
          (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) unclaimed-rewards))

          (ok unclaimed-rewards)
        )
      )
    ERR_STAKE_NOT_FOUND
  )
)

;; Admin functions

(define-public (add-rewards-to-pool (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)

    ;; Transfer STX to contract for rewards
    (unwrap! (stx-transfer? amount tx-sender (as-contract tx-sender)) ERR_TRANSFER_FAILED)

    ;; Add to reward pool
    (var-set reward-pool-balance (+ (var-get reward-pool-balance) amount))

    (ok amount)
  )
)

(define-public (update-pool-status (pool-id uint) (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)

    (match (get-staking-pool pool-id)
      pool-info
        (begin
          (map-set staking-pools
            { pool-id: pool-id }
            (merge pool-info { active: active })
          )
          (ok true)
        )
      ERR_INVALID_POOL
    )
  )
)

(define-public (emergency-withdraw (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)

    ;; Transfer from contract to owner
    (unwrap! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)) ERR_TRANSFER_FAILED)

    (ok amount)
  )
)
