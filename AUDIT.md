# SqueekPot — audit record

Target: `src/SqueekPot.sol`. Auditor: codex (gpt-5.6, xhigh, read-only) + slither 0.11.5.
Date: 2026-11-05.

## Findings & resolution

### P1 — Winner could be changed after the VRF word was public (FIXED)
`settleDraw` picked the winner from the **live** participant list/weights, but
`pendingRandomWord` is public once the draw is `Ready`. An attacker could withdraw+
redeposit (reordering the swap-pop list) or deposit (changing `total`) so the winning
slot landed on them, then settle atomically.
**Fix:** `requestDraw` now calls `_freezeEligibility()`, snapshotting the player set +
cumulative weights + total into `_snapWho/_snapCum/_snapTotal`. `settleDraw` selects
strictly from that frozen snapshot, so any deposit/withdraw after a request only affects
the **next** round. Regression: `test_WinnerImmuneToPostReadyReorder`,
`test_WinnerImmuneToPostReadyDeposit`.

### P1 — Owner could rig the draw via inherited `setCoordinator` (FIXED)
`VRFConsumerBaseV2Plus` exposes an owner-callable, non-virtual `setCoordinator`. A
malicious owner could point `s_vrfCoordinator` at a fake coordinator that supplies a
chosen word (it can reenter `rawFulfillRandomWords` while `pendingRequestId == 0`).
**Fix:** the coordinator is pinned at deploy in `i_coordinator` (immutable); both
`requestDraw` and `fulfillRandomWords` revert `CoordinatorChanged` if
`s_vrfCoordinator != i_coordinator`. A swapped coordinator can neither start nor fulfill
a draw. Coordinator migration therefore requires a redeploy (acceptable; documented).
Regression: `test_CoordinatorSwapBlocksDraw`.

## Accepted / scoped (no code change)

- **P2 — participant-cap admission DoS.** An attacker can fill all `MAX_PARTICIPANTS`
  (500) slots with `MIN_DEPOSIT` each (capital fully recoverable) to block new entrants
  with `PotFull`. It biases nothing; it only blocks admission while slots stay filled.
  Accepted for v1 (testnet, play-money). A v2 fix is a Fenwick/cumulative-weight tree
  (removes the cap) or a non-refundable admission cost (conflicts with the no-loss ethos).
- **P2 — fee-on-transfer.** `_pull` already credits the net received on deposit. Generic
  full-principal withdrawal is incompatible with an OUTBOUND transfer tax. The contract is
  **scoped to non-taxing, non-rebasing SQK** — the staged-launch-1 SQK ERC-20
  (`0xd78a3956…`) is the standard reward token with no transfer fee.
- **Flash-odds timing.** Odds are measured at the (permissionless, once-daily)
  `requestDraw` instant, so a large deposit placed just before a request gets full weight
  for that round even if withdrawn right after. This is inherent to any instantaneous-
  snapshot lottery; the v2 fix is time-weighted average balances (PoolTogether's TWAB).
  Accepted for v1.
- **P3 — invariant equality.** The balance==accounted invariant was relaxed to `>=`
  (`invariant_NoLeak`) because a raw transfer into the pot creates a transient surplus
  until `syncPrize`. The `strayTransfer` handler action now exercises that path.

## Assessed and clean

Prize/deposit accounting is separated (no-loss holds: `balance >= totalDeposits`, proven
by invariant over 128k calls); `settleDraw` clears state before paying (CEI +
ReentrancyGuard); stale request IDs are ignored; swap-pop bookkeeping is correct; VRF 2.5
request fields + coordinator-only callback are correct. `rand % total` modulo bias is
negligible. slither: only `block.timestamp` notes (irrelevant for a daily cadence).

Tests: 28 passing (25 unit + 3 invariants).

## Round 2 (confirmation, 2026-11-05)
Codex re-audit of the fixes: **both P1s confirmed closed, no new P0–P2.** Snapshot
integrity sound (live deposit/withdraw/reorder/re-entry cannot alter target or winner;
`rand % total` + `target < cumulative` has no boundary error; snapshot cleared on
settle/cancel/rebuild). Coordinator pinning sound (swapped coordinator can neither start
nor fulfill). No-loss preserved. One new **P3 (FIXED):** `canRequestDraw()` could return
true after an owner coordinator-swap though `requestDraw` would revert — added the
`s_vrfCoordinator == i_coordinator` check to the view. 28 tests still green.

## Round 3 — fresh 4-agent swarm (2026-11-06, independent, no sight of this file)
Four fresh reviewers (no-loss, VRF, access/DoS, reentrancy), each unanchored.
**Core CONFIRMED sound: no P0/P1 to funds or draw integrity.** No-loss proven
(`balance >= totalDeposits + prizeReserve`), draw un-riggable (snapshot frozen,
coordinator pinned both legs, winner immune post-reveal), owner has no path to funds
and cannot block `withdraw`. New findings (all DoS / liveness / defense-in-depth —
none steals principal or rigs the winner):

- **P1 — `requestDraw` gas-wedge.** `_freezeEligibility` rebuilds two cold storage
  arrays every round → ~45.7k gas/participant → **22.94M at the 500 cap** (measured).
  Sepolia (36M limit): fits but soft-DoS (nobody pays a 23M tx permissionlessly).
  Any chain <~23M (Squeekchain limit UNKNOWN): hard permanent wedge, prize stranded.
- **P2 — `syncPrize` missing `nonReentrant`** (`:243`): only mutator without it; a
  callback-token could inflate `prizeReserve` into principal mid-`_pull`. Unreachable
  for plain SQK.
- **P2 — stuck `Ready` draw** (`:343`/`:373`): a persistently-reverting prize transfer
  pins `drawState=Ready` forever; `cancelStuckDraw` only recovers `Requested`.
- **P2 — participant-cap flood** (`:199`, `MIN_DEPOSIT=1`): 500×1-SQK blocks new
  entrants (`PotFull`); near-free on testnet; drives P1 to worst-case.
- **P3** — lost-owner-key → permanent `Requested` wedge (add permissionless fallback);
  `setCoordinator` not `Idle`-guarded (liveness grief); `pendingRequestId` set after the
  VRF call (awaiting-id sentinel); document token precondition (non-fee/non-rebasing/
  non-blocklist); donated prize non-refundable.

### HARDENING PASS — APPLIED + REDEPLOYED (2026-11-06, operator kept cap 500)
Hardened contract deployed Sepolia at **`0x5e34c1b56768fc2858c3f1bca394d76a5d2039d5`**
(owner Main, deploy tx `0xd614e6a840fe4f8cb91d4d3f9b9d17b54375e532d175e87cd8e3537cfc736a01`).
Pre-hardening `0x63b18f4b…` is superseded (never had a consumer added; abandoned).

Applied:
1. **Packed snapshot** — `_snapWho`+`_snapCum` → one `uint256[] _snap`
   (`(uint160(addr)<<96)|uint96(cum)`) + `MAX_TOTAL = type(uint96).max` constant and a
   `deposit` guard (`TotalCapExceeded`). P1 gas-wedge **measured 22.94M → 11.75M @ 500**.
2. `syncPrize` → `nonReentrant` (P2).
3. permissionless `forceRecoverStuckDraw` after `STUCK_FALLBACK_TIMEOUT = 7 days` (P3-1);
   `cancelStuckDraw` refactored onto shared `_recoverStuck`.
4. awaiting-id sentinel (`pendingRequestId = type(uint256).max`) before the VRF request (P3-2).
5. token precondition documented in NatSpec.
**Dropped:** setCoordinator Idle-guard (P3-3) — base `setCoordinator` is `external`
non-virtual, cannot be overridden; risk already covered by the `i_coordinator` pin + the
recovery path. Participant-flood P2 accepted for testnet (mitigate via `MIN_DEPOSIT` at mainnet).

### Round 3 codex re-audit of the diff (2 passes)
Pass 1 confirmed packing lossless + selection-equivalent, `syncPrize` lock, sentinel, no-loss
preserved, both original P1s still closed — and **found ONE NEW P1 introduced by the hardening:**
`_recoverStuck` accepted the `Ready` state, letting the owner (or the 7-day public path)
**censor an already-randomized, unfavorable winner** by cancelling the Ready draw. **FIXED:**
`_recoverStuck` now gates `drawState != Requested` → a Ready draw (determined, public winner)
can NEVER be cancelled and stays permanently settleable (standard-token payout can't be
blocked). Pass 2 **confirmed the P1 closed, no new issue.** 33 tests green (30 unit + 3
invariant ×128k); slither clean.

### Round 4 — Genesis NFT odds boost (2026-11-06) — REDEPLOYED
New feature: holding ≥1 **Squeek Genesis NFT `0xc4c7982657f00509548f3a3a41db7fa439a6856b`**
weights a depositor's draw snapshot by **+20%** (`boostBps`), applied equally to every holder,
captured at `requestDraw`. No-loss untouched (boost only shifts `_snap`/`_snapTotal` weights;
prize still pays from `prizeReserve`). Deployed Sepolia at
**`0x2a86555598d4951d2dbfcb545e12e5aab06204d4`** (owner Main, deploy tx
`0xed0c4fa080541f42fc478182b0c354655e3e4f8ac36002bb4a2e34f269d0c1c6`, gas 14.76M).
Supersedes the hardened `0x5e34c1b5…`.

**Audit: codex ×3 passes + a 2-agent swarm (boost-math + boost-safety) on the boost diff.**

- **P1 — unbounded NFT `balanceOf` staticcall could wedge `requestDraw`** (gas-burn or
  returndata-bomb across up to 500 iterations). **CLOSED.** `_holdsBoostNft` is now an assembly
  `staticcall{gas:30000}` with a **zero-length output buffer** (no auto-copy), accepting a result
  only when `returndatasize()==32` and copying exactly those 32 bytes. A reverting / gas-burning /
  returndata-bombing collection → `held=false`, never reverts the draw. codex round-3 confirmed
  fully closed. Regression test `test_BadBoostNftCannotBrickDraw` (reverting / 4KB-return /
  gas-burn mocks) asserts `requestDraw` still succeeds with no boost.
- **P2 — owner self-tilt via tunable `setBoost`** (owner could crank their own cohort's odds to
  2× right before a draw). **CLOSED.** `boostBps` is now **`immutable`** (fixed 2000 in the
  constructor); `setBoost`, the `BoostTooHigh` error and the `BoostUpdated` event were removed.
  No owner knob remains. `boostNft` is immutable too (no owner repoint).
- **P3 — snapshot-ownership is rentable** (borrow a Genesis NFT for the `requestDraw` tx to
  capture the boost). **Accepted v1** — bounded to the +20%, zero fund/draw-integrity impact,
  impossible post-randomness; durable/time-weighted eligibility is a v2 nicety.
- **External-contract trust:** Genesis NFT `0xc4c7982657…` verified on-chain as a **non-proxy**
  standard ERC-721 (EIP-1967 impl slot empty), so the "malicious proxy upgrade manipulates
  eligibility" concern is excluded — and moot regardless, given the bounded assembly read.
- **Packing still lossless** (bps immutable 2000 → cum ≤ 1.2× deposits ≤ `MAX_TOTAL`), selection
  correct, no-loss intact, prior P1s + hardening fixes still hold.

**38 tests green** (35 unit + 3 invariant ×128k with the boost active on fuzzed actors); slither
clean. On-chain getters confirmed: `boostNft=0xC4C7982657…`, `boostBps=2000`, `MAX_BOOST_BPS=10000`,
`owner=Main`, `sqk=0xd78a3956…`, `i_coordinator=0x9Ddf…8B1B`, `payInNative=true`, `drawState=Idle`.
