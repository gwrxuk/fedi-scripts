# How Bitcoin, Lightning, and Fedimint Work

## Bitcoin — The Base Layer

Bitcoin is a decentralized digital currency that operates without a central authority. It solves the **double-spend problem** — ensuring no one can spend the same money twice — using a distributed ledger called the **blockchain**.

### Core Concepts

**Blockchain** — A chain of blocks, each containing a batch of transactions. Every full node stores a complete copy. Once a block is buried under enough subsequent blocks, the transactions it contains are considered irreversible.

**Proof of Work** — Miners compete to find a number (nonce) that, when hashed with the block data, produces a hash below a target threshold. This is computationally expensive to produce but trivial to verify. The difficulty adjusts every 2016 blocks (~2 weeks) to maintain a ~10-minute average block interval.

**UTXO Model** — Bitcoin doesn't use account balances. Instead, it tracks **Unspent Transaction Outputs** (UTXOs). When you "have" 1 BTC, you control one or more UTXOs that sum to 1 BTC. Spending means consuming existing UTXOs and creating new ones.

**Script** — Each UTXO is locked with a small program (scriptPubKey). To spend it, you must provide data (scriptSig) that satisfies the locking conditions. The simplest case: prove you own the private key corresponding to a given public key.

### Transaction Lifecycle

```
1. Sender constructs a transaction
   - References one or more UTXOs as inputs
   - Creates new UTXOs as outputs (recipient + change)
   - Signs each input with the corresponding private key

2. Broadcast to the mempool
   - Nodes validate: Are inputs unspent? Are signatures valid?
   - Valid transactions propagate across the peer-to-peer network

3. Miner includes it in a block
   - Selects transactions (usually by highest fee per byte)
   - Performs proof-of-work to mine the block

4. Block propagates, nodes verify and append
   - After ~6 confirmations, the transaction is considered final
```

### Limitations That Motivated Lightning

- **Throughput**: ~7 transactions per second globally
- **Latency**: 10-minute average block time; practical finality takes ~1 hour
- **Cost**: Fees spike during congestion — a $5 coffee can cost $20 in fees
- **Privacy**: All transactions are publicly visible on-chain

---

## Lightning Network — The Speed Layer

Lightning is a **Layer 2** protocol built on top of Bitcoin. It enables instant, low-cost payments by moving most transactions off-chain while preserving Bitcoin's security guarantees.

### The Key Insight: Payment Channels

Two parties lock Bitcoin into a **2-of-2 multisig** address on-chain. They can then exchange signed transactions between themselves — updating who owns how much of the locked funds — without broadcasting anything to the blockchain. Only the final state needs to go on-chain.

```
   On-chain (opening tx)
   ┌──────────────────────────┐
   │  2-of-2 Multisig         │
   │  Alice: 0.5 BTC          │
   │  Bob:   0.5 BTC          │
   └──────────────────────────┘
            │
            │  Off-chain updates (instant, free)
            │
            ▼
   State 1: Alice 0.5 → Bob 0.5
   State 2: Alice 0.4 → Bob 0.6   (Alice paid Bob 0.1)
   State 3: Alice 0.3 → Bob 0.7   (Alice paid Bob 0.1 again)
            │
            │  Either party can close the channel
            ▼
   On-chain (closing tx)
   ┌──────────────────────────┐
   │  Alice receives 0.3 BTC  │
   │  Bob receives 0.7 BTC    │
   └──────────────────────────┘
```

### Routing — Paying Without a Direct Channel

You don't need a channel with everyone. Lightning routes payments across a **network of channels** using **Hash Time-Locked Contracts (HTLCs)**.

```
Alice ──channel──> Carol ──channel──> Bob

Alice wants to pay Bob 0.01 BTC:

1. Bob generates a random secret (preimage) and sends its hash to Alice
2. Alice pays Carol 0.01 BTC, locked by the condition:
   "Carol can claim this if she reveals the preimage within 2 hours"
3. Carol pays Bob 0.01 BTC with the same condition but a shorter timeout
4. Bob reveals the preimage to Carol to claim his payment
5. Carol uses that same preimage to claim Alice's payment

Result: Alice paid Bob through Carol, atomically.
No one can steal funds — either the entire chain completes or nothing moves.
```

### Lightning Properties

| Property | Value |
|----------|-------|
| Speed | Milliseconds |
| Cost | Sub-satoshi fees typical |
| Privacy | Only sender and recipient know the full path |
| Throughput | Millions of TPS theoretically |
| Finality | Instant (but channel close requires on-chain confirmation) |

### The Tradeoffs

- **Liquidity**: You can only send up to the amount in your side of a channel
- **Online requirement**: Your node must be online to receive payments
- **Channel management**: Opening/closing channels costs on-chain fees
- **Routing complexity**: Finding paths with sufficient liquidity is non-trivial

---

## Fedimint — The Community Custody Layer

Fedimint is a **federated e-cash** protocol built on Bitcoin and Lightning. It addresses the UX and custody challenges that make Bitcoin and Lightning difficult for everyday users.

### The Problem Fedimint Solves

Self-custody is hard. Managing private keys, running nodes, maintaining channel liquidity — these are significant burdens. Most users end up trusting a single custodian (an exchange), creating a single point of failure.

Fedimint offers a **middle ground**: trust is distributed across a federation of guardians rather than concentrated in one entity.

### How It Works

#### Federated Custody

A **federation** is a group of **guardians** (typically 4-7) who collectively manage Bitcoin on behalf of their community. They use **threshold cryptography** — for example, in a 3-of-4 federation, any 3 guardians must agree to move funds. No single guardian can steal or block transactions.

```
                    ┌─────────────┐
                    │  Community  │
                    │   Members   │
                    └──────┬──────┘
                           │
                    deposit BTC / receive e-cash
                           │
              ┌────────────┼────────────┐
              │            │            │
         ┌────▼───┐  ┌────▼───┐  ┌────▼───┐  ┌────────┐
         │Guard 1 │  │Guard 2 │  │Guard 3 │  │Guard 4 │
         └────┬───┘  └────┬───┘  └────┬───┘  └────┬───┘
              │            │            │            │
              └────────────┴────────────┴────────────┘
                           │
                    Threshold multisig
                    (3-of-4 required)
                           │
                    ┌──────▼──────┐
                    │   Bitcoin   │
                    │  On-Chain   │
                    └─────────────┘
```

#### E-Cash — Chaumian Blind Signatures

When you deposit Bitcoin into a federation, you receive **e-cash tokens** — digital bearer instruments backed by the federation's Bitcoin reserves.

The critical innovation is **blind signatures** (invented by David Chaum in 1982):

```
1. User creates a random token and "blinds" it (cryptographic envelope)
2. User sends the blinded token to the federation along with a BTC deposit
3. Federation signs the blinded token (without seeing its contents)
4. User "unblinds" the signed token

Result: The federation certified the token's value
        but CANNOT link it to the original depositor.
        → Perfect transaction privacy within the federation.
```

When you spend e-cash, the federation verifies the signature is valid and the token hasn't been spent before (preventing double-spends), but it **cannot trace** who originally owned it.

#### Lightning Gateway

A **gateway** bridges the federation to the Lightning Network, enabling federation members to send and receive Lightning payments without running their own Lightning node.

```
┌──────────────────────────────────────────────────────┐
│                    Federation                         │
│                                                      │
│  Alice (member)                                      │
│    │                                                 │
│    │ pays e-cash to gateway                          │
│    ▼                                                 │
│  Gateway ──── Lightning ────> External recipient     │
│  (has LN node)   invoice                             │
│                                                      │
│  Bob (member)                                        │
│    ▲                                                 │
│    │ receives e-cash from gateway                    │
│    │                                                 │
│  Gateway <──── Lightning ──── External sender        │
│                  payment                             │
└──────────────────────────────────────────────────────┘
```

### Fedimint Modules

Fedimint is modular. Each federation runs a set of **consensus modules**:

| Module | Purpose |
|--------|---------|
| **wallet** | Manages on-chain Bitcoin deposits and withdrawals via threshold multisig |
| **mint** | Issues and redeems e-cash tokens using blind signatures |
| **ln** | Handles Lightning payments through gateways using HTLCs |
| **meta** | Stores federation metadata (name, welcome message, etc.) |

### The Trust Model

```
┌────────────────────────────────────────────────────────────┐
│                      Trust Spectrum                         │
│                                                            │
│  Full custody        Fedimint           Self-custody       │
│  (exchange)          (federation)       (your own keys)    │
│                                                            │
│  ● Single point      ● Distributed     ● No trust needed  │
│    of failure           trust           ● Full sovereignty │
│  ● Easy UX           ● Good UX         ● Complex UX       │
│  ● No privacy        ● Strong privacy  ● Varies           │
│  ● Seizure risk      ● Resilient       ● You are the risk │
│                                                            │
│  ◄────────────────────────────────────────────────────────►│
│  Less sovereignty                       More sovereignty   │
└────────────────────────────────────────────────────────────┘
```

Fedimint is designed for **communities** — a local group, a company, a family — where members know and trust the guardians to some degree, but no single guardian is trusted completely.

---

## How They Fit Together

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   Layer 3: Fedimint                                         │
│   ┌───────────────────────────────────────────────────┐     │
│   │  E-cash tokens    Blind signatures    Privacy     │     │
│   │  Community custody    Modular consensus           │     │
│   └────────────────────────┬──────────────────────────┘     │
│                            │                                │
│   Layer 2: Lightning       │ Gateway                        │
│   ┌────────────────────────▼──────────────────────────┐     │
│   │  Payment channels    HTLCs    Instant payments    │     │
│   │  Routing network     Sub-satoshi fees             │     │
│   └────────────────────────┬──────────────────────────┘     │
│                            │                                │
│   Layer 1: Bitcoin         │ On-chain                       │
│   ┌────────────────────────▼──────────────────────────┐     │
│   │  Blockchain    Proof of Work    UTXOs    Script   │     │
│   │  21M supply cap    ~10 min blocks    Final settlement│  │
│   └───────────────────────────────────────────────────┘     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Bitcoin** provides the foundation — decentralized, censorship-resistant money with final settlement.

**Lightning** adds speed and scale — instant payments across a global network without touching the blockchain for every transaction.

**Fedimint** adds usability and privacy — community-managed custody with strong privacy guarantees, accessible to anyone without technical expertise, bridged to Lightning for interoperability with the broader Bitcoin economy.

Together, they form a stack where each layer compensates for the limitations of the one below it.
