# EWB Whale Vault — Auditor First 30 Minutes Guide
## What to read, where to start, what to trust

---

## What this system is (read this first)

This is **not** a general DeFi lending protocol.

It is a **private single-actor credit engine**. One owner. One Ballet cold wallet.
No public depositors. No external borrowers. All value flows to one address.

This distinction changes your threat model completely. Standard DeFi attack vectors
— flash loan manipulation, sandwich attacks, cross-protocol reentrancy, multi-user
credit stacking — do not apply here.

The correct question is: *can any sequence of owner-signed transactions produce an
outcome that violates the system's stated economic intent?*

---

## The three contracts that matter most

Start here. Everything else is supporting infrastructure.

**1. `EWBWhaleVault.sol`** — The collateral registry

The root of everything. `lockMintingRights()` is the entry point for all credit.
It accepts unminted EWB token IDs, assigns floor values from immutable tier constants,
and issues a `lockId` used by everything downstream.

Key audit question: Can a lockId be issued without Wayne signing? Can a lock be
double-counted?

**2. `EWBMintingRightsVault.sol`** — The credit engine

Reads `lockId` from WhaleVault. Calls Aave v3 `borrow()`. Sends USDC to
`BALLET_WALLET` constant — hardcoded, not a variable. Also handles `repayUSDC()`
and `autoRepay()` from harvested yield.

Key audit question: Can USDC go anywhere other than `BALLET_WALLET`? Can the LTV
cap be exceeded? Can `autoRepay()` be called by an unauthorised address?

**3. `vault/VaultCore.sol`** — The yield engine

Deploys ETH to Lido → stETH → Aave. Harvests yield via `harvestToUSDC()` which
swaps stETH → WETH → USDC via Uniswap V3 and auto-repays Aave debt.

Key audit question: Can yield be redirected away from Ballet wallet? Does the
Uniswap swap have slippage protection?

---

## Five invariants to verify

These are the system's safety guarantees. Verify each one against the code.

| Invariant | Where enforced | Test |
|---|---|---|
| INV-1: Loans immutable after open | `credits[id].borrowed` set once in `borrowUSDC()` | Verify no function modifies it after creation |
| INV-2: Revalue non-retroactive | `revalueLock()` only updates `mintingLocks[id]` | Verify no loan struct is touched |
| INV-3: One loan per lock | `lockToCredit[lockId] != 0` reverts | Check `LockAlreadyHasCredit` revert |
| INV-4: USDC only to Ballet wallet | `BALLET_WALLET` is a `constant` | Verify every `safeTransfer` destination |
| INV-5: Oracle only at lock time | No oracle call in `borrowUSDC()` or `autoRepay()` | Grep for `oracle.` across all contracts |

INV-3 is the only one not fully enforced in code — it relies on single-actor
operational assumption. Documented in `EWB_INV3_OPERATING_ENVELOPE.md`.

---

## What will probably take your time

**CEI ordering** — Check all three core functions for correct
Checks-Effects-Interactions ordering. The `repayUSDC()` function had a CEI
violation that was fixed (H-1 in the finding register). Verify the fix is correct.

**Aave integration** — `borrow()` and `repay()` are called directly. Verify
the health factor check before every borrow. Verify the approve-zero-then-approve
pattern before every repay.

**autoRepay access control** — Only `owner` and `deltaVault` can call it.
`deltaVault` is set via `setDeltaVault()` which now requires a non-zero address.
Verify this cannot be called by an arbitrary address.

**Oracle price path** — Chainlink 8-decimal output is multiplied by `1e10` to
produce 18-decimal output. Verify this is correct throughout the calculation chain.
Previous finding H-3 was exactly this issue — confirm fix is applied.

**TWAP overflow** — `_tickToPrice()` in GorillaOracle uses hi/lo 128-bit split
to prevent sqrtPriceX96 overflow. Verify the `hi == 0` assertion is correct for
all valid Uniswap V3 tick ranges.

---

## What you can trust quickly

**Static analysis is clean:**
- No `tx.origin`
- No `delegatecall`
- No `selfdestruct`
- No floating pragma
- No unchecked arithmetic
- All approvals zero-reset before re-approval

Run `sha256sum -c checksums.txt` to confirm files match the reviewed source.

**Access control is simple:**
- `onlyOwner` — Ballet wallet `0xc82A...D46cf` — hardcoded as `immutable`
- `onlyWhaleVault` — CreditBridge only accepts calls from WhaleVault
- `onlyDeltaVault` or `onlyOwner` — autoRepay only

No role hierarchies. No timelocks on the owner functions. No proxy patterns.
No upgradability.

---

## What will not waste your time

Do not spend time on:
- Flash loan attacks — no flash-loanable assets in the vault
- Front-running attacks — single actor, no competing transactions
- Governance attacks — no governance module
- Multi-user reentrancy — no external depositors or borrowers
- Sandwich attacks on lending — no public lending functions

---

## The one architectural gap to note

**INV-3 is not code-enforced.**

`lockToCredit[lockId]` resets to 0 after repay. A second `borrowUSDC()` call
on the same lockId after repayment is valid by design — that is the intended
re-borrow cycle.

However there is no ceiling on *concurrent* loans against the same lockId if
somehow two borrows were opened simultaneously. The `LockAlreadyHasCredit` check
prevents this, but verify it holds under all call sequences.

This is acceptable under the single-actor threat model — Wayne cannot profitably
exploit himself. But note it as architectural for the report.

---

## Suggested 30-minute sequence

```
0:00 — Read this document
0:05 — Read SYSTEM_MANIFEST.md (2 pages)
0:10 — Read EWBWhaleVault.sol (lockMintingRights + unlockMintingRights)
0:15 — Read EWBMintingRightsVault.sol (borrowUSDC + repayUSDC + autoRepay)
0:20 — Check all five invariants against the code
0:25 — Run: npm ci && npm run build:reproducible && npm test && forge
```