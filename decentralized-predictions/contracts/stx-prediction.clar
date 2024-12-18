;; Prediction Market Smart Contract

;; Define constants
(define-constant contract-administrator tx-sender)
(define-constant minimum-stake-amount u100000) ;; Minimum stake amount (100,000 microSTX)
(define-constant platform-fee-percentage u2) ;; 2% platform fee

;; Define error constants in uppercase
(define-constant ERROR_UNAUTHORIZED (err u100))
(define-constant ERROR_MARKET_ALREADY_RESOLVED (err u101))
(define-constant ERROR_MARKET_NOT_RESOLVED (err u102))
(define-constant ERROR_INVALID_STAKE_AMOUNT (err u103))
(define-constant ERROR_INSUFFICIENT_BALANCE (err u104))
(define-constant ERROR_MARKET_CANCELLED (err u105))
(define-constant ERROR_INVALID_OPTION (err u106))

;; Define data maps
(define-map market-registry
  { market-id: uint }
  {
    market-question: (string-ascii 256),
    market-description: (string-ascii 1024),
    market-end-block: uint,
    winning-option: (optional uint),
    option-stake-totals: (list 20 uint),
    market-is-resolved: bool,
    market-is-cancelled: bool
  }
)

(define-map participant-stakes
  { market-id: uint, staker-address: principal }
  {
    stake-distribution: (list 20 uint)
  }
)

(define-map market-options
  { market-id: uint }
  {
    available-options: (list 20 (string-ascii 64))
  }
)

;; Define variables
(define-data-var market-counter uint u0)

;; Custom maximum function
(define-private (find-maximum (first-number uint) (second-number uint))
  (if (> first-number second-number) first-number second-number)
)

;; Helper function to safely get an element from a list or return a default value
(define-private (get-list-element-or-default (input-list (list 20 uint)) (element-index uint) (default-value uint))
  (default-to default-value (element-at? input-list element-index))
)

;; Custom take function
(define-private (take-first-n (number-elements uint) (input-list (list 20 uint)))
  (let ((list-length (len input-list)))
    (if (>= number-elements list-length)
      input-list
      (concat (list) (unwrap-panic (slice? input-list u0 number-elements)))
    )
  )
)

;; Custom drop function
(define-private (drop-first-n (number-elements uint) (input-list (list 20 uint)))
  (let ((list-length (len input-list)))
    (if (>= number-elements list-length)
      (list)
      (concat (list) (unwrap-panic (slice? input-list number-elements list-length)))
    )
  )
)

;; Helper function to update a value at a specific index in a list
(define-private (update-list-element (input-list (list 20 uint)) (element-index uint) (new-value uint))
  (let ((prefix-elements (take-first-n element-index input-list))
        (suffix-elements (drop-first-n (+ element-index u1) input-list)))
    (unwrap-panic (as-max-len? (concat (concat prefix-elements (list new-value)) suffix-elements) u20))
  )
)

;; Functions

;; Create a new prediction market
(define-public (create-prediction-market (market-question (string-ascii 256)) (market-description (string-ascii 1024)) (market-end-block uint) (market-options-list (list 20 (string-ascii 64))))
  (let
    (
      (market-id (var-get market-counter))
      (number-of-options (len market-options-list))
      (initial-stake-totals (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0))
    )
    (asserts! (> number-of-options u1) ERROR_INVALID_OPTION)
    (map-set market-registry
      { market-id: market-id }
      {
        market-question: market-question,
        market-description: market-description,
        market-end-block: market-end-block,
        winning-option: none,
        option-stake-totals: initial-stake-totals,
        market-is-resolved: false,
        market-is-cancelled: false
      }
    )
    (map-set market-options
      { market-id: market-id }
      {
        available-options: market-options-list
      }
    )
    (var-set market-counter (+ market-id u1))
    (ok market-id)
  )
)

;; Place a stake on a prediction market
(define-public (place-market-stake (market-id uint) (selected-option-index uint) (stake-amount uint))
  (let
    (
      (market-data (unwrap! (map-get? market-registry { market-id: market-id }) (err u404)))
      (market-option-data (unwrap! (map-get? market-options { market-id: market-id }) (err u404)))
      (existing-stake-data (default-to { stake-distribution: (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0) } 
        (map-get? participant-stakes { market-id: market-id, staker-address: tx-sender })))
    )
    (asserts! (not (get market-is-resolved market-data)) ERROR_MARKET_ALREADY_RESOLVED)
    (asserts! (not (get market-is-cancelled market-data)) ERROR_MARKET_CANCELLED)
    (asserts! (>= stake-amount minimum-stake-amount) ERROR_INVALID_STAKE_AMOUNT)
    (asserts! (<= stake-amount (stx-get-balance tx-sender)) ERROR_INSUFFICIENT_BALANCE)
    (asserts! (< selected-option-index (len (get available-options market-option-data))) ERROR_INVALID_OPTION)
    
    (let
      (
        (current-option-stake (get-list-element-or-default (get option-stake-totals market-data) selected-option-index u0))
        (updated-option-stake (+ current-option-stake stake-amount))
        (updated-option-totals (update-list-element (get option-stake-totals market-data) selected-option-index updated-option-stake))
        (current-participant-stake (get-list-element-or-default (get stake-distribution existing-stake-data) selected-option-index u0))
        (updated-participant-stake (+ current-participant-stake stake-amount))
        (updated-participant-stakes (update-list-element (get stake-distribution existing-stake-data) selected-option-index updated-participant-stake))
      )
      (map-set market-registry { market-id: market-id }
        (merge market-data { option-stake-totals: updated-option-totals })
      )
      
      (map-set participant-stakes
        { market-id: market-id, staker-address: tx-sender }
        { stake-distribution: updated-participant-stakes }
      )
      
      (stx-transfer? stake-amount tx-sender (as-contract tx-sender))
    )
  )
)

;; Finalize a prediction market
(define-public (resolve-prediction-market (market-id uint) (winning-option-index uint))
  (let
    (
      (market-data (unwrap! (map-get? market-registry { market-id: market-id }) (err u404)))
      (market-option-data (unwrap! (map-get? market-options { market-id: market-id }) (err u404)))
    )
    (asserts! (is-eq tx-sender contract-administrator) ERROR_UNAUTHORIZED)
    (asserts! (not (get market-is-resolved market-data)) ERROR_MARKET_ALREADY_RESOLVED)
    (asserts! (not (get market-is-cancelled market-data)) ERROR_MARKET_CANCELLED)
    (asserts! (>= block-height (get market-end-block market-data)) ERROR_UNAUTHORIZED)
    (asserts! (< winning-option-index (len (get available-options market-option-data))) ERROR_INVALID_OPTION)
    
    (map-set market-registry { market-id: market-id }
      (merge market-data {
        winning-option: (some winning-option-index),
        market-is-resolved: true
      })
    )
    (ok true)
  )
)

;; Cancel a prediction market
(define-public (cancel-prediction-market (market-id uint))
  (let
    (
      (market-data (unwrap! (map-get? market-registry { market-id: market-id }) (err u404)))
    )
    (asserts! (is-eq tx-sender contract-administrator) ERROR_UNAUTHORIZED)
    (asserts! (not (get market-is-resolved market-data)) ERROR_MARKET_ALREADY_RESOLVED)
    (asserts! (not (get market-is-cancelled market-data)) ERROR_MARKET_CANCELLED)
    
    (map-set market-registry { market-id: market-id }
      (merge market-data {
        market-is-cancelled: true
      })
    )
    (ok true)
  )
)

;; Withdraw partial stake before prediction market resolution
(define-public (withdraw-partial-stake (market-id uint) (option-index uint) (withdrawal-amount uint))
  (let
    (
      (market-data (unwrap! (map-get? market-registry { market-id: market-id }) (err u404)))
      (participant-stake-data (unwrap! (map-get? participant-stakes { market-id: market-id, staker-address: tx-sender }) (err u404)))
    )
    (asserts! (not (get market-is-resolved market-data)) ERROR_MARKET_ALREADY_RESOLVED)
    (asserts! (not (get market-is-cancelled market-data)) ERROR_MARKET_CANCELLED)
    (asserts! (< option-index (len (get stake-distribution participant-stake-data))) ERROR_INVALID_OPTION)
    (let
      (
        (current-stake-amount (get-list-element-or-default (get stake-distribution participant-stake-data) option-index u0))
      )
      (asserts! (>= current-stake-amount withdrawal-amount) ERROR_INVALID_STAKE_AMOUNT)
      
      (let
        (
          (updated-option-totals (update-list-element (get option-stake-totals market-data) option-index 
            (- (get-list-element-or-default (get option-stake-totals market-data) option-index u0) withdrawal-amount)))
          (updated-stake-amounts (update-list-element (get stake-distribution participant-stake-data) option-index 
            (- current-stake-amount withdrawal-amount)))
        )
        (map-set market-registry { market-id: market-id }
          (merge market-data { option-stake-totals: updated-option-totals })
        )
        
        (map-set participant-stakes
          { market-id: market-id, staker-address: tx-sender }
          { stake-distribution: updated-stake-amounts }
        )
        
        (as-contract (stx-transfer? withdrawal-amount (as-contract tx-sender) tx-sender))
      )
    )
  )
)

;; Claim winnings or refund
(define-public (claim-rewards-or-refund (market-id uint))
  (let
    (
      (market-data (unwrap! (map-get? market-registry { market-id: market-id }) (err u404)))
      (participant-stake-data (unwrap! (map-get? participant-stakes { market-id: market-id, staker-address: tx-sender }) (err u404)))
    )
    (asserts! (or (get market-is-resolved market-data) (get market-is-cancelled market-data)) ERROR_MARKET_NOT_RESOLVED)
    
    (if (get market-is-cancelled market-data)
      (let
        (
          (refund-amount (fold + (get stake-distribution participant-stake-data) u0))
        )
        (map-delete participant-stakes { market-id: market-id, staker-address: tx-sender })
        (as-contract (stx-transfer? refund-amount (as-contract tx-sender) tx-sender))
      )
      (let
        (
          (winning-option-index (unwrap! (get winning-option market-data) ERROR_MARKET_NOT_RESOLVED))
          (winning-stake-amount (get-list-element-or-default (get stake-distribution participant-stake-data) winning-option-index u0))
          (total-winning-pool (get-list-element-or-default (get option-stake-totals market-data) winning-option-index u0))
          (total-market-pool (fold + (get option-stake-totals market-data) u0))
          (gross-payout (/ (* winning-stake-amount total-market-pool) total-winning-pool))
          (platform-fee (/ (* gross-payout platform-fee-percentage) u100))
          (net-payout (- gross-payout platform-fee))
        )
        (map-delete participant-stakes { market-id: market-id, staker-address: tx-sender })
        (as-contract (stx-transfer? net-payout (as-contract tx-sender) tx-sender))
      )
    )
  )
)

;; Time-based automatic resolution
(define-public (auto-resolve-markets (max-markets-to-process uint))
  (let
    (
      (total-markets (var-get market-counter))
      (initial-state { current-market-id: u0, total-market-count: total-markets, remaining-iterations: max-markets-to-process })
    )
    (ok (get current-market-id (fold process-market-resolution
                              (list initial-state)
                              initial-state)))
  )
)

(define-private (process-market-resolution
  (current-state { current-market-id: uint, total-market-count: uint, remaining-iterations: uint }) 
  (accumulator { current-market-id: uint, total-market-count: uint, remaining-iterations: uint })
)
  (let (
    (current-market-id (get current-market-id current-state))
    (total-markets (get total-market-count current-state))
    (remaining-iterations (get remaining-iterations current-state))
  )
    (if (and (< current-market-id total-markets) (> remaining-iterations u0))
      (let
        (
          (market-data (map-get? market-registry { market-id: current-market-id }))
        )
        (if (is-some market-data)
          (let
            (
              (market-resolved (match market-data market-info (resolve-if-expired current-market-id market-info) false))
            )
            { 
              current-market-id: (+ current-market-id u1),
              total-market-count: total-markets,
              remaining-iterations: (- remaining-iterations u1)
            }
          )
          { 
            current-market-id: (+ current-market-id u1),
            total-market-count: total-markets,
            remaining-iterations: (- remaining-iterations u1)
          }
        )
      )
      current-state
    )
  )
)

(define-private (resolve-if-expired (market-id uint) (market-data { market-question: (string-ascii 256), market-description: (string-ascii 1024), market-end-block: uint, winning-option: (optional uint), option-stake-totals: (list 20 uint), market-is-resolved: bool, market-is-cancelled: bool }))
  (if (and (>= block-height (get market-end-block market-data)) 
           (not (get market-is-resolved market-data)) 
           (not (get market-is-cancelled market-data)))
    (let
      (
        (winning-option-index (determine-winning-option (get option-stake-totals market-data)))
      )
      (map-set market-registry 
        { market-id: market-id }
        (merge market-data {
          winning-option: (some winning-option-index),
          market-is-resolved: true
        })
      )
      true
    )
    false
  )
)

(define-private (determine-winning-option (stake-amounts (list 20 uint)))
  (let
    (
      (highest-stake-amount (fold find-maximum stake-amounts u0))
    )
    (unwrap-panic (index-of stake-amounts highest-stake-amount))
  )
)

;; Read-only functions

;; Get prediction market details
(define-read-only (get-market-details (market-id uint))
  (map-get? market-registry { market-id: market-id })
)

;; Get prediction market options
(define-read-only (get-market-options-list (market-id uint))
  (map-get? market-options { market-id: market-id })
)

;; Get participant stake details
(define-read-only (get-participant-stake-details (market-id uint) (staker-address principal))
  (map-get? participant-stakes { market-id: market-id, staker-address: staker-address })
)

;; Get contract balance
(define-read-only (get-contract-stx-balance)
  (stx-get-balance (as-contract tx-sender))
)