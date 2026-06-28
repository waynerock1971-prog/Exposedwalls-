# EWB Vault Protocol — Threat Model & Risk Analysis

## Overview

This document outlines the security model, known limitations, residual risks, and mitigations for the EWB Vault Protocol (v1.0-audit-candidate, commit `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3`).

---

## 1. Actor & Asset Map

### Actors
| Actor | Role | Trust Assumption |
|-------|------|------------------|
| NFT Holders | Deposit token IDs as collateral | Trusted to initiate legitimate locks |
| Safe Multisig | Protocol governance & treasury | Trusted but monitored; M-of-N signing required |
| dYdX Hedge Bot | Off-chain attestor | Single EOA; key compromise risk (KL-4) |
| KYC Attestor | Off-chain KYC validation | Single EOA; key compromise risk (KL-4) |
| Aave/Lido/Uniswap | External protocols | Assumed to operate correctly |
| Auditors (ToB/Spearbit) | Review & verification | External validation |

### Assets
| Asset | Amount | Location | Risk |
|-------|--------|----------|------|
| ETH (long leg) | ~6,391 ETH | Aave V3 (wstETH) | Smart contract risk, oracle risk |
| USDC (lending pool) | $? (TBD by LTV) | EWBMintingRightsVault | Lending pool solvency |
| EWB NFTs | 9,940 tokens (max) | EWBWhaleVault custody | Custody & custody withdrawal |
| Harvest Tokens | TBD | Circulation | Redemption mechanics |

---

## 2. Known Limitations (Accepted Residual Risks)

### KL-1: dYdX Hedge Attestation Is Off-Chain

**Description:**
The protocol hedges its long ETH position on dYdX by opening a perpetual short. However, dYdX position data is not natively readable on-chain. Instead, a trusted bot EOA monitors the dYdX API and submits a signed summary via `submitHedgeAttestation()`.

**Risk Chain:**
```
Bot EOA key compromised
  → Attacker signs false attestation
  → False short notional recorded
  → Protocol believes it is hedged when it may not be
  → Long/short mismatch → liquidation risk
```

**Mitigations (v1.0):**
- Nonce prevents replay of old attestations
- 20% notional deviation cap limits the false attestation size
- Aave HF cross-check (1.05x floor) adds on-chain constraint
- 15-minute timestamp window prevents stale data

**Residual Risk (ACCEPTED):**
A sophisticated attacker could compromise the bot EOA and drive Aave HF to exactly 1.05x to pass a false attestation.

**Mitigation in v1.1:** N-of-M attestor signatures (e.g., 2-of-3 threshold)

---

### KL-2: Manual Oracle Floor Is a Trusted-Admin Surface

**Description:**
The EWB price is sourced from Uniswap V3 TWAP. However, pre-launch or during thin-market periods, the Safe multisig can set a manual floor price via `EWBGorillaOracle.setManualFloor()`. This floor propagates to all credit capacity calculations.

**Risk Chain:**
```
Manual floor set by multisig
  → Multisig sets floor below true market price
  → Credit capacity inflates artificially
  → More USDC lent against same collateral
  → Pool insolvency risk if EWB price recovers
```

**Mitigations (v1.0):**
- M-of-N multisig required (not single EOA)
- 5% TWAP deviation cap when pool is available (hard-enforced)
- 30-minute max age on manual floor (hard expiry)
- Event emitted on every `setManualFloor()` call

**Residual Risk (ACCEPTED):**
When the TWAP pool is unavailable (pre-launch), the multisig can set any floor for up to 30 minutes.

**Mitigation in v1.1:** Guardian veto role (separate from multisig signing key)

---

### KL-3: No On-Chain Governance Veto

**Description:**
Parameter changes are subject to a 48-hour timelock, but only the Safe multisig itself can cancel queued changes — the same party that queued them. There is no independent guardian or veto role.

**Residual Risk (ACCEPTED):**
Requires multisig compromise but no on-chain technical veto if governance is corrupted.

**Mitigation in v1.1:** Guardian-only-cancel role (separate key, lower threshold)

---

### KL-4: Single Attestor EOAs (No N-of-M)

**Description:**
Two critical attestors are single EOAs: `hedgeAttestor` (dYdX hedge) and `kycAttestor` (KYC validation). A 48-hour rotation timelock mitigates key-loss but not key-compromise.

**Residual Risk (ACCEPTED):**
A compromised attestor EOA can submit false data until the 48-hour rotation completes.

**Mitigation in v1.1:** N-of-M attestor signatures (e.g., 2-of-3 for each role)

---

## 3. Attack Surface by Contract

### EWBDeltaNeutralVault (P0)
| Attack | Mitigation | Residual Risk |
|--------|-----------|------------------|
| False hedge attestation (KL-1) | Aave HF cross-check + 20% cap | Sophisticated attackers + HF at 1.05x floor |
| Emergency exit reentrancy | CEI enforced; external calls last | Low |
| ECDSA signature replay | Nonce tracking | Low |

### EWBMintingRightsVault (P0)
| Attack | Mitigation | Residual Risk |
|--------|-----------|------------------|
| Pool insolvency (over-lending) | LTV floors + collateral valuation tied to oracle | KL-2 (manual oracle floor) |
| KYC bypass | Off-chain attestor (KL-4) | Single EOA compromise |

### EWBWhaleVault (P0)
| Attack | Mitigation | Residual Risk |
|--------|-----------|------------------|
| Unauthorized lock/unlock | Only NFT owner or approved operator | Standard ERC-721 risks |
| lockId collision | 256-bit hash space | Negligible |

---

## 4. Test Coverage

- **Unit Tests:** 644 Hardhat tests covering core contract functions
- **Invariant Tests:** 22 Foundry fuzz/invariant tests verifying core invariants
- **Total:** 666 tests, all passing

---

## 5. Deployment Checklist

Before mainnet deployment:
- [ ] Audit reports from Trail of Bits & Spearbit complete
- [ ] Zero Critical/High findings across both reports
- [ ] Escode SAST scan clean
- [ ] All testnet invariant tests passing
- [ ] Mainnet addresses hardcoded & verified
- [ ] Safe multisig threshold & signers finalized
- [ ] Attestor EOAs rotated post-audit
- [ ] Emergency exit key holders identified
- [ ] Monitoring infrastructure deployed

---

**Document Version:** 1.0  
**Last Updated:** June 2026  
**Commit:** `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3`