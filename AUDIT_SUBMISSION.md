# EWB Vault Protocol — Audit Submission

## Frozen Commit
```
Tag:    v1.0-audit-candidate
Commit: 5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3
Date:   June 2026
```
> **This is the only hash auditors should review.** Do not audit `main` — it may receive non-audit commits.

---

## Scope
- **16 Solidity contracts** — `contracts/*.sol` (excluding `contracts/mocks/`)
- **~8,200 LOC**, Solidity 0.8.19, optimizer 200 runs
- **Target:** Ethereum mainnet
- **Deployment capital:** ~$211M (78,476 ETH)

---

## Capital Flow Architecture — Two Parallel Tracks

**IMPORTANT — no ETH is sent by NFT holders or end users.**

### Track A — NFT Collateral (token IDs only)
```
EWB NFT token IDs
  → EWBWhaleVault.lockMintingRights(tokenIds[])
      faceValueETH calculated from tier floors:
        EPIC:        315 ETH × 16 tokens  =   5,040 ETH
        SUPER RARE:   22 ETH × 362 tokens =   7,964 ETH
        RARE:         10 ETH × 1,492 tokens = 14,920 ETH
        STANDARD:      1 ETH × 8,130 tokens =  8,130 ETH
        TOTAL:                               36,054 ETH face (max)
  → lockId  (used as collateral in downstream contracts)
      ├─ EWBMintingRightsVault.openLoan(lockId)  → USDC loan vs LTV
      ├─ EWBPrivatePool.seedPool(lockId)          → internal credit line
      └─ EWBNFTHarvestVault.lockNFTs()            → harvest token issuance
```

### Track B — Delta-Neutral Yield (Safe multisig treasury ETH only)
```
Safe multisig treasury
  → EWBDeltaNeutralVault.deployLongLeg(){value: ethAmount}
      ETH → Lido.submit() → stETH
      stETH → IWstETH.wrap() → wstETH
      wstETH → AaveV3Pool.supply() → earns staking yield
  maxDeployment cap = 6,391 ETH = LAYER3_ETH_TOTAL
  (cap is set to match the L3 credit capacity from NFT face values)
```

### The Link
The `maxDeployment` cap in the delta vault is intentionally set equal to `LAYER3_ETH_TOTAL` (6,391 ETH). This means the ETH yield strategy never exceeds the notional value of the NFT collateral backing the L3 credit layer. They are parallel tracks, not sequential — NFT collateral enables lending, treasury ETH generates yield independently.

## Priority Audit Order

| Priority | Contract | Why |
|----------|----------|-----|
| P0 | `EWBDeltaNeutralVault.sol` | $211M exposure, Aave integration, ECDSA attestation, dYdX cross-check, emergency exit |
| P0 | `EWBMintingRightsVault.sol` | USDC lending pool, ERC-7621, KYC attestation, pool solvency |
| P0 | `EWBWhaleVault.sol` | Root registry — all lending and harvest contracts depend on it |
| P1 | `EWBGorillaOracle.sol` | Price oracle — manual floor trusted-admin surface, downstream impact on all credit |
| P1 | `EWBPrivatePool.sol` | 50/50 cross-collateral lending pool |
| P1 | `EWBNFTHarvestVault.sol` | NFT custody + harvest token distribution |
| P2 | `EWBPrivateHarvest.sol` | ECDSA harvest request system |
| P2 | `EWBRevenueRouter.sol` | Income routing — reentrancy surface |
| P3 | `EWBLayer1/2/3Token.sol` | ERC-20 layer tokens |
| P3 | All others | Legal registry, escrows, connectors |

---

## Known Limitations — Full Detail

### KL-1: dYdX Attestation Is Off-Chain (MOST SIGNIFICANT)

The dYdX short hedge position is not readable on-chain. A trusted bot EOA reads the dYdX API and submits a signed summary via `submitHedgeAttestation()`. The contract verifies:

1. Caller is registered `hedgeAttestor` EOA
2. Nonce has not been used before (replay prevention)
3. Data timestamp is within 15 minutes
4. ECDSA signature recovers to `hedgeAttestor`
5. Attested notional is within 20% of on-chain `totalDeployed`
6. **Aave `getUserAccountData()` is called on-chain** — HF must be ≥ 1.05x (F4 fix)

**What a compromised bot key cannot do:** move funds, bypass the Aave cross-check, replay old signatures, or change protocol parameters.

**Residual risk:** A sophisticated attacker who compromises the bot key AND drives Aave HF to exactly 1.05x (the cross-check floor) could pass a false attestation. This residual risk is accepted in v1.0. Mitigation in v1.1: N-of-M attestor signatures.

### KL-2: Manual Oracle Floor Is a Trusted-Admin Surface (SECOND MOST SIGNIFICANT)

`EWBGorillaOracle.setManualFloor()` allows the Safe multisig to set the EWB floor price directly when Uniswap V3 liquidity is unavailable (pre-launch or thin market). This floor propagates to all credit capacity calculations across `EWBLayer1/2/3Token`, `EWBMintingRightsVault`, and `EWBWhaleVault`.

**Mitigations:** M-of-N multisig required; 5% TWAP deviation cap when pool is available; 30-minute max age (hard cap); events emitted on every set.

**Residual risk:** When the TWAP pool is unavailable, the deviation cap is bypassed. The multisig can set any floor during this window. The 30-minute expiry limits but does not eliminate exposure.

### KL-3: No On-Chain Governance Veto

Parameter changes (via 48hr timelocked setters) can only be cancelled by the Safe multisig itself — the same party that queued them. A guardian-only-cancel role is not implemented in v1.0.

### KL-4: Single Attestor Bot (No N-of-M)

The hedge attestor and KYC attestor are each a single EOA. Rotation timelocks (48hr) mitigate key-loss, but not key-compromise. N-of-M attestation is deferred to v1.1.

---

## Pre-Audit Gates Completed

- [x] 24 findings resolved across two review passes (see `PRE_AUDIT_CHECKLIST.md`)
- [x] Static analysis pass: no `tx.origin`, `delegatecall`, `selfdestruct`, floating pragma, unchecked arithmetic
- [x] CEI enforced on all fund-moving functions
- [x] `approve()` zero-reset before every re-approval
- [x] 6 hardcoded mainnet addresses verified against official sources
- [x] 666 test cases (644 Hardhat + 22 Foundry invariant/fuzz)
- [x] `THREAT_MODEL.md` with full actor/asset/attack surface breakdown
- [x] `SAST_External_Scoping_EWB_FINAL.docx` prepared for Escode submission

---

## Repository Access

Provide auditors with:
1. Private GitHub repository invitation
2. Commit hash: `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3`
3. `THREAT_MODEL.md`, `AUDIT_SUBMISSION.md`, `PRE_AUDIT_CHECKLIST.md`

Do **not** send a zip as primary deliverable — provide a verified git commit for audit integrity.

---

## Engagement Instructions

- **Audit scope:** frozen commit `5d16e7622b5dcfe5ae7369a0928c186fa3a53ff3` only
- **Remediation review:** one round included in engagement
- **Timeline target:** 6–8 weeks from engagement start
- **Parallel audits:** Trail of Bits and Spearbit engaged simultaneously
- **Deployment gate:** zero Critical/High findings open across BOTH reports + Escode SAST clean
- **Contact:** Wayne Fyffe — Exposed Walls (EWB)