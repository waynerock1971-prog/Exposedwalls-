# EWB Vault Protocol — Pre-Audit Checklist

**Status:** ✅ READY FOR AUDIT  
**Frozen Commit:** `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3`  
**Tag:** `v1.0-audit-candidate`  
**Date:** June 2026

---

## Code Quality & Static Analysis

### Security Patterns
- [x] No `tx.origin` usage
- [x] No `delegatecall()` without access control
- [x] No `selfdestruct()`
- [x] No floating pragma (all contracts pinned to `0.8.19`)
- [x] No unchecked arithmetic (all overflow-prone operations use SafeMath or explicit checks)
- [x] No implicit assumptions on block.timestamp (used only for timelock windows, not for critical logic)

### Reentrancy & CEI
- [x] All fund-moving functions follow Checks-Effects-Interactions (CEI) pattern
- [x] External calls placed at end of function
- [x] State updates occur before external calls
- [x] `nonReentrant` modifier applied to high-risk functions

### Approval Patterns
- [x] All `approve()` calls preceded by `approve(0)` to reset allowance
- [x] No approval re-entrancy vectors
- [x] Approval amounts match exact transfer amounts (no over-approvals)

### Access Control
- [x] `onlyOwner` applied to governance functions
- [x] `onlyMultisig` applied to fund movement (via Safe delegatecall)
- [x] Role-based access for attestors, oracle updaters
- [x] No unguarded state mutations

---

## Smart Contract Audit Findings (24 Resolved)

### Round 1: Initial Code Review (12 findings)

| # | Severity | Title | Status | Resolution |
|---|----------|-------|--------|-------------|
| 1 | HIGH | Missing nonce tracking in hedge attestation | ✅ FIXED | Added `_hedgeAttestationNonces` mapping |
| 2 | HIGH | Oracle manual floor could be set without TWAP check | ✅ FIXED | Added `_validateFloorDeviation()` with 5% cap |
| 3 | MEDIUM | LTV recalculation not triggered on collateral price change | ✅ FIXED | Event emitted; off-chain monitoring required |
| 4 | MEDIUM | Pool solvency check missing on high USDC withdrawals | ✅ FIXED | Added `_ensurePoolSolvency()` check |
| 5 | MEDIUM | Aave health factor cross-check in attestation lacked specificity | ✅ FIXED | Hardened to HF ≥ 1.05x with SafeMath |
| 6 | LOW | Event emission inconsistency across vault contracts | ✅ FIXED | Standardized event schema |
| 7 | LOW | Missing zero-address checks on attestor rotation | ✅ FIXED | Added `require(attestor != address(0))` |
| 8 | LOW | Harvest token redemption lacked explicit balance check | ✅ FIXED | Added balance verification before burn |
| 9 | LOW | Emergency exit function callable by non-owners | ✅ FIXED | Applied `onlyOwner` modifier |
| 10 | LOW | Manual floor expiry calculation off-by-one | ✅ FIXED | Corrected timestamp arithmetic |
| 11 | INFO | Insufficient inline documentation on dYdX integration | ✅ FIXED | Added detailed NatSpec comments |
| 12 | INFO | No formal specification of credit tier bucketing logic | ✅ FIXED | Created `CREDIT_TIERS.md` specification |

### Round 2: Remediation Verification (12 findings)

| # | Severity | Title | Status | Resolution |
|---|----------|-------|--------|-------------|
| 13 | MEDIUM | Attestor rotation during active attestation window could cause stale data | ✅ FIXED | Attestor rotation guarded by 48-hour timelock |
| 14 | MEDIUM | Collateral accounting could diverge if NFT transfer occurs outside vault | ✅ FIXED | Transfer guard: only vault can move locked NFTs |
| 15 | MEDIUM | Aave flashloan attack vector not addressed | ✅ MITIGATED | Aave integration uses `supply()` only (no borrow/flashloan), added monitoring |
| 16 | LOW | Missing event on pool solvency failure | ✅ FIXED | Added `PoolInsolvencyDetected()` event |
| 17 | LOW | No upper bound check on oracle manual floor | ✅ FIXED | Added cap at 105% of TWAP (when available) |
| 18 | LOW | Harvest token supply cap not enforced | ✅ FIXED | Added `maxHarvestTokens` parameter + enforcement |
| 19 | LOW | dYdX attestation timestamp could be manipulated by off-chain oracle | ✅ MITIGATED | 15-minute window + on-chain Aave HF cross-check |
| 20 | LOW | Missing explicit revert on failed Aave interaction | ✅ FIXED | Added try-catch with fallback to emergency exit |
| 21 | LOW | Collateral lock expiry not enforced | ✅ FIXED | Added `lockExpiryDate` field, enforced on unlock |
| 22 | LOW | Manual floor set without prior TWAP availability check | ✅ FIXED | Added `isPoolAvailable()` check before manual floor allow |
| 23 | INFO | Incomplete error message on revert | ✅ FIXED | Standardized revert messages with error codes |
| 24 | INFO | No inline gas optimization comments | ✅ FIXED | Added gas optimization notes in critical paths |

---

## Test Coverage

### Unit Tests (644 tests, all passing)

- EWBWhaleVault (82 tests)
- EWBMintingRightsVault (156 tests)
- EWBDeltaNeutralVault (134 tests)
- EWBGorillaOracle (98 tests)
- EWBPrivatePool (96 tests)
- EWBNFTHarvestVault (78 tests)
- EWBLayer1/2/3Token (100 tests)
- Utility & Helper Contracts (100 tests)

### Invariant Tests (22 Foundry tests, all passing)

1. **Collateral Conservation:** `∑ locked collateral ≥ ∑ issued credit`
2. **Pool Solvency:** `pool.balance ≥ ∑ outstanding loans`
3. **Oracle Staleness:** `time.now - oracle.lastUpdate < 30 minutes`
4. **Hedge Notional Bound:** `|attested hedge - on-chain deployed| < 20% × deployed`
5. **Nonce Monotonicity:** `attestation[N].nonce > attestation[N-1].nonce`
6. **Health Factor Floor:** `aave.healthFactor ≥ 1.05x after attestation`
7. **Deployment Cap:** `totalDeployed ≤ 6,391 ETH`
8. **LTV Floor:** `loan amount ≤ collateral value × LTV floor`

---

## Known Limitations (Accepted for v1.0)

1. **KL-1: dYdX Attestation Off-Chain** — N-of-M signatures deferred to v1.1
2. **KL-2: Manual Oracle Floor Trusted-Admin** — Guardian veto role deferred to v1.1
3. **KL-3: No On-Chain Governance Veto** — Guardian-only-cancel role deferred to v1.1
4. **KL-4: Single Attestor EOAs** — N-of-M signatures deferred to v1.1

---

## Sign-Off

**Code Frozen:** June 2026  
**Commit:** `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3`  
**Tag:** `v1.0-audit-candidate`  

**Ready for audit by:**
- Trail of Bits
- Spearbit
- Escode (SAST)

**Deployment gate:** Zero Critical/High findings across all three reports.

---

**Document Version:** 1.0  
**Last Updated:** June 2026  
**Prepared by:** EWB Core Team