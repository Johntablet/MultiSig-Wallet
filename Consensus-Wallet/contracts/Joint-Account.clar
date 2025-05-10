;; Multi-signature Wallet Smart Contract

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_PARAMETER (err u101))
(define-constant ERR_TX_NOT_FOUND (err u102))
(define-constant ERR_TX_EXECUTED (err u103))
(define-constant ERR_TX_REJECTED (err u104))
(define-constant ERR_TX_EXPIRED (err u105))
(define-constant ERR_INSUFFICIENT_FUNDS (err u106))
(define-constant ERR_THRESHOLD_TOO_HIGH (err u107))
(define-constant ERR_OWNER_ALREADY_EXISTS (err u108))
(define-constant ERR_OWNER_NOT_FOUND (err u109))
(define-constant ERR_ALREADY_CONFIRMED (err u110))
(define-constant ERR_NOT_CONFIRMED (err u111))
(define-constant ERR_INVALID_DATA (err u112))

;; Data structures

;; Transaction status enum: 0 = pending, 1 = executed, 2 = rejected
(define-data-var tx-counter uint u0)

;; Transaction structure
(define-map transactions
  { tx-id: uint }
  {
    creator: principal,
    to: principal,
    amount: uint,
    data: (optional (buff 256)),
    executed: bool,
    rejected: bool,
    confirmations: uint,
    expiration: uint
  }
)

;; Confirmations mapping (tx-id, owner) -> confirmed
(define-map confirmations
  { tx-id: uint, owner: principal }
  { confirmed: bool }
)

;; Owners list
(define-map owners
  { owner: principal }
  { active: bool }
)

;; Store the number of active owners
(define-data-var owner-count uint u0)

;; Required confirmations threshold
(define-data-var threshold uint u0)

;; Helper function to validate data buffer
(define-private (validate-data (data-to-check (optional (buff 256))))
  (match data-to-check
    buffer-data (if (< (len buffer-data) u256) 
                    (some buffer-data)
                    none)
    none))

;; Contract initialization
(define-public (initialize (initial-owners (list 20 principal)) (required-confirmations uint))
  (begin
    ;; Check if contract is already initialized
    (asserts! (is-eq (var-get owner-count) u0) ERR_UNAUTHORIZED)
    ;; Validate threshold is not higher than owner count
    (asserts! (<= required-confirmations (len initial-owners)) ERR_THRESHOLD_TOO_HIGH)
    ;; Validate threshold is greater than 0
    (asserts! (> required-confirmations u0) ERR_INVALID_PARAMETER)
    
    ;; Set the confirmation threshold
    (var-set threshold required-confirmations)
    
    ;; Initialize owners
    (map add-initial-owner initial-owners)
    
    ;; Return success
    (ok true)
  )
)

;; Helper function for initialization
(define-private (add-initial-owner (owner principal))
  (begin
    (map-set owners { owner: owner } { active: true })
    (var-set owner-count (+ (var-get owner-count) u1))
    true
  )
)

;; Get threshold
(define-read-only (get-threshold)
  (var-get threshold)
)

;; Check if an address is an owner
(define-read-only (is-owner (address principal))
  (default-to false (get active (map-get? owners { owner: address })))
)

;; Check if sender is an owner
(define-private (is-sender-owner)
  (is-owner tx-sender)
)

;; Get owner count
(define-read-only (get-owner-count)
  (var-get owner-count)
)

;; Get transaction details
(define-read-only (get-transaction (tx-id uint))
  (map-get? transactions { tx-id: tx-id })
)

;; Check if transaction exists
(define-read-only (transaction-exists (tx-id uint))
  (is-some (map-get? transactions { tx-id: tx-id }))
)

;; Check if transaction is confirmed by an owner
(define-read-only (is-confirmed (tx-id uint) (owner principal))
  (default-to false 
    (get confirmed 
      (map-get? confirmations { tx-id: tx-id, owner: owner })))
)

;; Get transaction confirmation count
(define-read-only (get-confirmation-count (tx-id uint))
  (match (map-get? transactions { tx-id: tx-id })
    tx (get confirmations tx)
    u0
  )
)

;; Get contract balance
(define-read-only (get-balance)
  (stx-get-balance (as-contract tx-sender))
)

;; Submit a new transaction
(define-public (submit-transaction (to principal) (amount uint) (data (optional (buff 256))) (expiration uint))
  (let
    (
      (tx-id (var-get tx-counter))
      (contract-address (as-contract tx-sender))
      ;; Properly validate data buffer
      (validated-data (validate-data data))
    )
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Validate expiration block is in the future
    (asserts! (> expiration block-height) ERR_INVALID_PARAMETER)
    ;; Additional validations to address warnings
    (asserts! (not (is-eq to contract-address)) ERR_INVALID_PARAMETER) ;; Prevent sending to self
    (asserts! (> amount u0) ERR_INVALID_PARAMETER) ;; Ensure amount is greater than zero
    ;; Check that contract has sufficient balance for the transaction
    (asserts! (<= amount (stx-get-balance contract-address)) ERR_INSUFFICIENT_FUNDS)
    ;; Validate data is properly checked
    (asserts! (is-some validated-data) ERR_INVALID_DATA)
    
    ;; Create transaction
    (map-set transactions
      { tx-id: tx-id }
      {
        creator: tx-sender,
        to: to,
        amount: amount,
        data: validated-data,
        executed: false,
        rejected: false,
        confirmations: u1, ;; Creator automatically confirms
        expiration: expiration
      }
    )
    
    ;; Add confirmation for creator
    (map-set confirmations
      { tx-id: tx-id, owner: tx-sender }
      { confirmed: true }
    )
    
    ;; Increment transaction counter
    (var-set tx-counter (+ tx-id u1))
    
    ;; Try to execute if threshold is 1
    (if (is-eq (var-get threshold) u1)
      ;; Modified to handle type matching correctly
      (let ((result (execute-transaction tx-id)))
        (ok tx-id))  ;; Always return (ok tx-id) regardless of execution result
      (ok tx-id)
    )
  )
)

;; Confirm a transaction
(define-public (confirm-transaction (tx-id uint))
  (begin
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Check if owner has not already confirmed
          (asserts! (not (is-confirmed tx-id tx-sender)) ERR_ALREADY_CONFIRMED)
          
          ;; Update confirmations
          (map-set confirmations
            { tx-id: tx-id, owner: tx-sender }
            { confirmed: true }
          )
          
          ;; Update transaction confirmations count
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { confirmations: (+ (get confirmations tx) u1) })
          )
          
          ;; Try to execute if threshold met
          (if (>= (+ (get confirmations tx) u1) (var-get threshold))
            ;; Modified to handle type matching correctly
            (let ((result (execute-transaction tx-id)))
              (ok tx-id))  ;; Always return (ok tx-id) regardless of execution result
            (ok tx-id)
          )
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Revoke confirmation
(define-public (revoke-confirmation (tx-id uint))
  (begin
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if owner has confirmed
          (asserts! (is-confirmed tx-id tx-sender) ERR_NOT_CONFIRMED)
          
          ;; Update confirmations
          (map-set confirmations
            { tx-id: tx-id, owner: tx-sender }
            { confirmed: false }
          )
          
          ;; Update transaction confirmations count
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { confirmations: (- (get confirmations tx) u1) })
          )
          
          (ok tx-id)
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Execute transaction
(define-public (execute-transaction (tx-id uint))
  (begin
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Check if threshold is met
          (asserts! (>= (get confirmations tx) (var-get threshold)) ERR_UNAUTHORIZED)
          
          ;; Update transaction to executed
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { executed: true })
          )
          
          ;; Execute the transfer
          (as-contract 
            (stx-transfer? (get amount tx) tx-sender (get to tx))
          )
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Reject transaction (requires threshold confirmations to reject)
(define-public (reject-transaction (tx-id uint))
  (begin
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Only require one owner to reject their own submitted transaction
          (if (is-eq (get creator tx) tx-sender)
            (begin
              (map-set transactions
                { tx-id: tx-id }
                (merge tx { rejected: true })
              )
              (ok tx-id)
            )
            ;; Otherwise, require threshold confirmations
            (if (>= (get confirmations tx) (var-get threshold))
              (begin
                (map-set transactions
                  { tx-id: tx-id }
                  (merge tx { rejected: true })
                )
                (ok tx-id)
              )
              ERR_UNAUTHORIZED
            )
          )
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Add a new owner
(define-public (add-owner (new-owner principal))
  (let
    (
      (tx-id (var-get tx-counter))
    )
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if the new owner doesn't already exist
    (asserts! (not (is-owner new-owner)) ERR_OWNER_ALREADY_EXISTS)
    
    ;; Create a special transaction for adding an owner
    (map-set transactions
      { tx-id: tx-id }
      {
        creator: tx-sender,
        to: new-owner, ;; Using 'to' field to store the new owner
        amount: u0,
        data: none,
        executed: false,
        rejected: false,
        confirmations: u1, ;; Creator automatically confirms
        expiration: (+ block-height u144) ;; ~1 day expiration
      }
    )
    
    ;; Add confirmation for creator
    (map-set confirmations
      { tx-id: tx-id, owner: tx-sender }
      { confirmed: true }
    )
    
    ;; Increment transaction counter
    (var-set tx-counter (+ tx-id u1))
    
    (ok tx-id)
  )
)

;; Execute add owner (internal)
(define-public (execute-add-owner (tx-id uint))
  (begin
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Check if threshold is met
          (asserts! (>= (get confirmations tx) (var-get threshold)) ERR_UNAUTHORIZED)
          
          ;; Update transaction to executed
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { executed: true })
          )
          
          ;; Add new owner
          (map-set owners 
            { owner: (get to tx) } 
            { active: true }
          )
          
          ;; Increment owner count
          (var-set owner-count (+ (var-get owner-count) u1))
          
          (ok tx-id)
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Remove an owner
(define-public (remove-owner (owner-to-remove principal))
  (let
    (
      (tx-id (var-get tx-counter))
    )
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if the owner exists
    (asserts! (is-owner owner-to-remove) ERR_OWNER_NOT_FOUND)
    ;; Check that we're not removing the last owner
    (asserts! (> (var-get owner-count) u1) ERR_INVALID_PARAMETER)
    ;; Check that threshold won't be higher than owner count after removal
    (asserts! (<= (var-get threshold) (- (var-get owner-count) u1)) ERR_THRESHOLD_TOO_HIGH)
    
    ;; Create a special transaction for removing an owner
    (map-set transactions
      { tx-id: tx-id }
      {
        creator: tx-sender,
        to: owner-to-remove, ;; Using 'to' field to store the owner to remove
        amount: u0,
        data: none,
        executed: false,
        rejected: false,
        confirmations: u1, ;; Creator automatically confirms
        expiration: (+ block-height u144) ;; ~1 day expiration
      }
    )
    
    ;; Add confirmation for creator
    (map-set confirmations
      { tx-id: tx-id, owner: tx-sender }
      { confirmed: true }
    )
    
    ;; Increment transaction counter
    (var-set tx-counter (+ tx-id u1))
    
    (ok tx-id)
  )
)

;; Execute remove owner (internal)
(define-public (execute-remove-owner (tx-id uint))
  (begin
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Check if threshold is met
          (asserts! (>= (get confirmations tx) (var-get threshold)) ERR_UNAUTHORIZED)
          
          ;; Update transaction to executed
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { executed: true })
          )
          
          ;; Remove owner
          (map-set owners 
            { owner: (get to tx) } 
            { active: false }
          )
          
          ;; Decrement owner count
          (var-set owner-count (- (var-get owner-count) u1))
          
          (ok tx-id)
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Change threshold
(define-public (change-threshold (new-threshold uint))
  (let
    (
      (tx-id (var-get tx-counter))
    )
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Validate new threshold
    (asserts! (> new-threshold u0) ERR_INVALID_PARAMETER)
    (asserts! (<= new-threshold (var-get owner-count)) ERR_THRESHOLD_TOO_HIGH)
    
    ;; Create a special transaction for changing threshold
    (map-set transactions
      { tx-id: tx-id }
      {
        creator: tx-sender,
        to: tx-sender, ;; Not relevant for this operation
        amount: new-threshold, ;; Using amount to store new threshold
        data: none,
        executed: false,
        rejected: false,
        confirmations: u1, ;; Creator automatically confirms
        expiration: (+ block-height u144) ;; ~1 day expiration
      }
    )
    
    ;; Add confirmation for creator
    (map-set confirmations
      { tx-id: tx-id, owner: tx-sender }
      { confirmed: true }
    )
    
    ;; Increment transaction counter
    (var-set tx-counter (+ tx-id u1))
    
    (ok tx-id)
  )
)

;; Execute change threshold (internal)
(define-public (execute-change-threshold (tx-id uint))
  (begin
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has not expired
          (asserts! (<= block-height (get expiration tx)) ERR_TX_EXPIRED)
          ;; Check if threshold is met
          (asserts! (>= (get confirmations tx) (var-get threshold)) ERR_UNAUTHORIZED)
          
          ;; Update transaction to executed
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { executed: true })
          )
          
          ;; Change threshold
          (var-set threshold (get amount tx))
          
          (ok tx-id)
        )
      ERR_TX_NOT_FOUND
    )
  )
)

;; Receive STX to contract
(define-public (deposit (amount uint))
  (begin
    (stx-transfer? amount tx-sender (as-contract tx-sender))
  )
)

;; Emergency method to clear expired transactions
(define-public (clear-expired-transaction (tx-id uint))
  (begin
    ;; Check if sender is an owner
    (asserts! (is-sender-owner) ERR_UNAUTHORIZED)
    ;; Check if transaction exists
    (asserts! (transaction-exists tx-id) ERR_TX_NOT_FOUND)
    
    ;; Get transaction
    (match (map-get? transactions { tx-id: tx-id })
      tx
        (begin
          ;; Check if transaction is still pending
          (asserts! (not (get executed tx)) ERR_TX_EXECUTED)
          (asserts! (not (get rejected tx)) ERR_TX_REJECTED)
          ;; Check if transaction has expired
          (asserts! (> block-height (get expiration tx)) ERR_INVALID_PARAMETER)
          
          ;; Mark transaction as rejected
          (map-set transactions
            { tx-id: tx-id }
            (merge tx { rejected: true })
          )
          
          (ok tx-id)
        )
      ERR_TX_NOT_FOUND
    )
  )
)