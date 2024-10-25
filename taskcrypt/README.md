# TaskCrypt

TaskCrypt is a decentralized freelance marketplace smart contract built on the Stacks blockchain. It provides a secure, transparent platform for managing freelance jobs, payments, milestones, and dispute resolution.

## Features

- **Secure Payment Management**: Automated escrow system for milestone-based payments
- **Stake-Based Verification**: Freelancers must stake tokens to participate, ensuring accountability
- **Milestone Management**: Support for up to 10 milestones per project
- **Service Categories**: Customizable service categories with minimum stake requirements
- **Dispute Resolution**: Built-in evidence submission system for conflict resolution
- **Rating System**: Comprehensive user rating and statistics tracking
- **Platform Fee**: 2.5% platform fee on all transactions

## Smart Contract Details

### Constants

- **Minimum Stake**: 1,000,000 STX
- **Maximum Milestones**: 10 per job
- **Maximum Deadline**: ~100 days
- **Timeout Period**: ~10 days
- **Platform Fee**: 2.5%

### Core Functions

#### For Clients

```clarity
(create-job freelancer total-amount description category deadline)
(add-milestone job-id description amount)
(complete-milestone job-id milestone-id)
```

#### For Freelancers

```clarity
(stake-tokens amount)
(withdraw-stake)
```

#### For Dispute Resolution

```clarity
(submit-dispute-evidence job-id evidence-hash)
```

#### Read-Only Functions

```clarity
(get-job job-id)
(get-milestone job-id milestone-id)
(get-user-rating user)
(get-freelancer-stats freelancer)
(get-service-category category-id)
(get-dispute-evidence job-id party)
```

## Data Structures

### Jobs
- Client and freelancer information
- Total and remaining amount
- Project description and category
- Status tracking
- Milestone management
- Arbitration information

### Milestones
- Description
- Amount
- Status
- Deadline

### User Ratings
- Total ratings
- Rating sum
- Jobs completed
- Dispute statistics

### Service Categories
- Category name
- Description
- Minimum stake requirement

## Usage Guide

### For Clients

1. **Creating a Job**
   - Call `create-job` with freelancer's address, total amount, description, category, and deadline
   - Funds will be automatically locked in the contract
   - Platform fee will be deducted

2. **Managing Milestones**
   - Add milestones using `add-milestone`
   - Complete milestones using `complete-milestone`
   - Funds are automatically released upon milestone completion

### For Freelancers

1. **Getting Started**
   - Stake required tokens using `stake-tokens`
   - Minimum stake amount: 1,000,000 STX

2. **Managing Stakes**
   - Stakes can be withdrawn after the timeout period
   - Use `withdraw-stake` to retrieve staked tokens

### For Dispute Resolution

1. **Submitting Evidence**
   - Both parties can submit evidence using `submit-dispute-evidence`
   - Evidence is stored as a hash for verification

## Error Codes

- `ERR-NOT-AUTHORIZED (u1)`: Unauthorized access
- `ERR-INVALID-JOB (u2)`: Invalid job ID or access
- `ERR-INSUFFICIENT-FUNDS (u3)`: Insufficient funds for operation
- `ERR-ALREADY-COMPLETED (u4)`: Operation on completed job/milestone
- `ERR-INVALID-MILESTONE (u5)`: Invalid milestone ID or access
- `ERR-TIMEOUT-NOT-REACHED (u6)`: Timeout period not reached
- `ERR-INVALID-AMOUNT (u7)`: Invalid amount specified
- `ERR-TOO-MANY-MILESTONES (u8)`: Exceeds maximum milestone limit
- `ERR-INVALID-FREELANCER (u9)`: Invalid freelancer address
- `ERR-INVALID-DESCRIPTION (u10)`: Invalid description
- `ERR-INVALID-CATEGORY (u11)`: Invalid category
- `ERR-INVALID-DEADLINE (u12)`: Invalid deadline
- `ERR-INVALID-NAME (u13)`: Invalid name
- `ERR-INVALID-JOB-ID (u14)`: Invalid job ID
- `ERR-INVALID-MILESTONE-ID (u15)`: Invalid milestone ID
- `ERR-INVALID-EVIDENCE (u16)`: Invalid evidence hash

## Security Considerations

- All funds are held in the contract until milestone completion
- Freelancers must stake tokens to participate
- Evidence hashing for dispute resolution
- Timeout periods for stake withdrawals
- Authorization checks on all sensitive operations

## Development and Testing

To interact with the contract:

1. Deploy the contract to the Stacks blockchain
2. Use the provided function calls to interact with the contract
3. Ensure proper error handling in your application
4. Test thoroughly with various scenarios and edge cases


## Contributing

EDOZIE