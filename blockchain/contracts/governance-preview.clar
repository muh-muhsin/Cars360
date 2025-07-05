;; Cars360 Governance Preview Contract
;; Demonstrates how staking system enables decentralized governance
;; This is a preview/example contract showing future governance capabilities

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u500))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u501))
(define-constant ERR_VOTING_ENDED (err u502))
(define-constant ERR_VOTING_NOT_ENDED (err u503))
(define-constant ERR_ALREADY_VOTED (err u504))
(define-constant ERR_INSUFFICIENT_STAKE (err u505))
(define-constant ERR_INVALID_PROPOSAL (err u506))

;; Proposal types
(define-constant PROPOSAL_TYPE_FEE_CHANGE u1)
(define-constant PROPOSAL_TYPE_POOL_PARAMS u2)
(define-constant PROPOSAL_TYPE_TREASURY u3)
(define-constant PROPOSAL_TYPE_GENERAL u4)

;; Voting parameters
(define-constant VOTING_PERIOD u4320) ;; 30 days in blocks
(define-constant MIN_STAKE_TO_PROPOSE u1000000000) ;; 1000 STX minimum to create proposal
(define-constant QUORUM_THRESHOLD u20) ;; 20% of total staked tokens needed

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var total-governance-weight uint u0)

;; Data Maps
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-utf8 100),
    description: (string-utf8 500),
    proposal-type: uint,
    target-contract: (optional principal),
    target-function: (optional (string-ascii 50)),
    parameters: (optional (string-utf8 200)),
    created-at: uint,
    voting-ends-at: uint,
    votes-for: uint,
    votes-against: uint,
    total-votes: uint,
    executed: bool,
    passed: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool, ;; true = for, false = against
    weight: uint,
    voted-at: uint
  }
)

(define-map user-voting-power
  { user: principal, block-height: uint }
  { voting-power: uint }
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (get-voting-power (user principal))
  (let
    (
      (staker-stats (contract-call? .staking-pool get-staker-stats user))
      (governance-weight (get governance-weight staker-stats))
    )
    governance-weight
  )
)

(define-read-only (can-create-proposal (user principal))
  (let
    (
      (staker-stats (contract-call? .staking-pool get-staker-stats user))
      (total-staked (get total-staked staker-stats))
    )
    (>= total-staked MIN_STAKE_TO_PROPOSE)
  )
)

(define-read-only (get-proposal-status (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal
      (let
        (
          (current-block block-height)
          (voting-ends (get voting-ends-at proposal))
          (votes-for (get votes-for proposal))
          (votes-against (get votes-against proposal))
          (total-votes (get total-votes proposal))
          (quorum-met (>= total-votes (/ (* (var-get total-governance-weight) QUORUM_THRESHOLD) u100)))
          (majority-for (> votes-for votes-against))
        )
        {
          voting-active: (< current-block voting-ends),
          quorum-met: quorum-met,
          majority-for: majority-for,
          can-execute: (and (>= current-block voting-ends) quorum-met majority-for (not (get executed proposal))),
          participation-rate: (if (> (var-get total-governance-weight) u0)
                                (/ (* total-votes u100) (var-get total-governance-weight))
                                u0)
        }
      )
    { voting-active: false, quorum-met: false, majority-for: false, can-execute: false, participation-rate: u0 }
  )
)

;; Public functions

(define-public (create-proposal
  (title (string-utf8 100))
  (description (string-utf8 500))
  (proposal-type uint)
  (target-contract (optional principal))
  (target-function (optional (string-ascii 50)))
  (parameters (optional (string-utf8 200)))
)
  (let
    (
      (proposer tx-sender)
      (proposal-id (var-get next-proposal-id))
      (current-block block-height)
      (voting-ends (+ current-block VOTING_PERIOD))
    )
    
    ;; Check if user can create proposals
    (asserts! (can-create-proposal proposer) ERR_INSUFFICIENT_STAKE)
    
    ;; Validate proposal type
    (asserts! (and (>= proposal-type u1) (<= proposal-type u4)) ERR_INVALID_PROPOSAL)
    
    ;; Create proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: proposer,
        title: title,
        description: description,
        proposal-type: proposal-type,
        target-contract: target-contract,
        target-function: target-function,
        parameters: parameters,
        created-at: current-block,
        voting-ends-at: voting-ends,
        votes-for: u0,
        votes-against: u0,
        total-votes: u0,
        executed: false,
        passed: false
      }
    )
    
    ;; Update total governance weight from staking contract
    (var-set total-governance-weight (contract-call? .staking-pool get-total-staked))
    
    ;; Increment proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (match (get-proposal proposal-id)
    proposal
      (let
        (
          (voter tx-sender)
          (current-block block-height)
          (voting-power (get-voting-power voter))
        )
        
        ;; Check if voting is still active
        (asserts! (< current-block (get voting-ends-at proposal)) ERR_VOTING_ENDED)
        
        ;; Check if user hasn't voted already
        (asserts! (is-none (get-vote proposal-id voter)) ERR_ALREADY_VOTED)
        
        ;; Check if user has voting power
        (asserts! (> voting-power u0) ERR_INSUFFICIENT_STAKE)
        
        ;; Record vote
        (map-set votes
          { proposal-id: proposal-id, voter: voter }
          {
            vote: vote-for,
            weight: voting-power,
            voted-at: current-block
          }
        )
        
        ;; Update proposal vote counts
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal {
            votes-for: (if vote-for 
                         (+ (get votes-for proposal) voting-power)
                         (get votes-for proposal)),
            votes-against: (if vote-for
                            (get votes-against proposal)
                            (+ (get votes-against proposal) voting-power)),
            total-votes: (+ (get total-votes proposal) voting-power)
          })
        )
        
        (ok true)
      )
    ERR_PROPOSAL_NOT_FOUND
  )
)

(define-public (execute-proposal (proposal-id uint))
  (match (get-proposal proposal-id)
    proposal
      (let
        (
          (status (get-proposal-status proposal-id))
          (can-execute (get can-execute status))
        )
        
        ;; Check if proposal can be executed
        (asserts! can-execute ERR_VOTING_NOT_ENDED)
        
        ;; Mark as executed and passed
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal {
            executed: true,
            passed: true
          })
        )
        
        ;; Note: In a full implementation, this would execute the actual proposal
        ;; For now, we just mark it as executed for demonstration
        
        (ok true)
      )
    ERR_PROPOSAL_NOT_FOUND
  )
)

;; Example proposal creation functions

(define-public (propose-fee-change (new-fee-percentage uint))
  (create-proposal
    u"Platform Fee Change"
    (concat "Proposal to change platform fee to " (int-to-ascii new-fee-percentage) "%")
    PROPOSAL_TYPE_FEE_CHANGE
    (some .dataset-registry)
    (some "set-platform-fee")
    (some (int-to-ascii new-fee-percentage))
  )
)

(define-public (propose-pool-rate-change (pool-id uint) (new-apy uint))
  (create-proposal
    u"Staking Pool Rate Change"
    (concat "Proposal to change pool " (int-to-ascii pool-id) " APY to " (int-to-ascii new-apy) " basis points")
    PROPOSAL_TYPE_POOL_PARAMS
    (some .staking-pool)
    (some "update-pool-apy")
    (some (concat (int-to-ascii pool-id) "," (int-to-ascii new-apy)))
  )
)

;; Admin functions (for initial setup)

(define-public (update-governance-weight)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set total-governance-weight (contract-call? .staking-pool get-total-staked))
    (ok true)
  )
)

;; Helper function to convert uint to string (simplified)
(define-private (int-to-ascii (value uint))
  ;; Simplified conversion - in practice would need full implementation
  (if (is-eq value u0) "0"
  (if (is-eq value u1) "1"
  (if (is-eq value u2) "2"
  (if (is-eq value u3) "3"
  (if (is-eq value u4) "4"
  (if (is-eq value u5) "5"
  (if (is-eq value u10) "10"
  (if (is-eq value u20) "20"
  "unknown"))))))))
)
