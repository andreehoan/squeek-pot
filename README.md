# 🐹 Squeek Pot — a no-loss SQK lottery on Squeekchain

squeekchain-project: be7b1fb1-3801-4c84-8700-73e30e8b2273

Deposit SQK, **keep it forever** (always 100% withdrawable), and your deposit size is
your odds to win the **daily prize pot**. Your principal is never at risk — only the
prize (seeded on testnet, staking yield later) is ever paid out. Winner picked by
**Chainlink VRF 2.5** (provably fair). Wrapped in an **8-bit arcade** frontend.

Nothing like it exists on Squeekchain — the existing betting games (squeekbet, Hamster
Hour) are *loss-based* wagers; this is the only *no-loss* game.

## Layout

```
src/SqueekPot.sol              the contract (no-loss vault + VRF draw)
test/SqueekPot.t.sol           22 unit tests
test/SqueekPotInvariant.t.sol  3 no-loss invariants (128k fuzzed calls each)
script/DeploySqueekPot.s.sol   env-driven deploy
web/index.html                 the 8-bit arcade site (self-contained, ethers v6)
```

## How it stays no-loss (the one invariant that matters)

Deposits (`totalDeposits`) and the prize (`prizeReserve`) are **two separate
accumulators**. A draw only ever transfers `prizeReserve`; the draw math is
structurally unable to touch principal. Therefore the token balance held is always
`>= totalDeposits`, so every depositor can always withdraw in full. `withdraw` is
deliberately **not pausable**. Proven by the invariant suite (`balance >= totalDeposits`
held over 128k randomized calls, 0 reverts).

The owner can tune **only** VRF plumbing, `pause` (deposits + new draws, never
withdraw/settle), and `cancelStuckDraw` after a timeout. There is **no owner path to
deposits or the prize**.

## Draw lifecycle

1. `requestDraw()` — permissionless, once/day after the interval elapses. Snapshots the
   prize and asks VRF for randomness.
2. VRF calls back `fulfillRandomWords` — tiny, fixed-gas: just stores the random word.
3. `settleDraw()` — permissionless. Picks the weighted winner and pays the prize.
   (Split out of the callback so it can never run out of gas as players grow.)

Prize mode **v1 = seeded**: anyone calls `fundPrize(amount)` to top up the pot.
Prize mode **v2 = yield** (planned): pooled SQK is staked and the yield becomes the
prize — deposits stay 100% withdrawable either way. v2 is a separate, separately-audited
iteration once Squeekchain emission is live; **this contract is seeded-only**.

## Tests

```bash
export PATH="$PATH:$HOME/.foundry/bin"
forge test              # 28 tests: 25 unit + 3 invariants (128k calls each)
forge test --gas-report
slither src/SqueekPot.sol --exclude-dependencies   # clean (only block.timestamp notes)
```

Security audit record (findings + resolutions): **`AUDIT.md`**. Two P1s found by codex
and fixed: (1) post-randomness winner manipulation → eligibility is now frozen at
`requestDraw` and settled from that snapshot; (2) owner-rig via inherited
`setCoordinator` → coordinator is pinned immutably and re-checked on request + fulfill.

## Deploy (Sepolia)

Verified Sepolia addresses (Chainlink VRF 2.5 + staged-launch-1 SQK):

| What | Address |
|---|---|
| SQK (deposit token) | `0xd78a3956cf63164d1fa1c622ad3c66623162fa1e` |
| VRF 2.5 Coordinator | `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B` |
| VRF 2.5 key hash | `0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae` |
| LINK | `0x779877A7B0D9E8603169DdbD7836e478b4624789` |

1. **Create + fund a VRF subscription** at <https://vrf.chain.link/sepolia> (fund with
   testnet LINK from <https://faucets.chain.link>, or use native ETH). Note the **sub id**.
2. **Deploy:**
   ```bash
   export SQK=0xd78a3956cf63164d1fa1c622ad3c66623162fa1e
   export VRF_COORDINATOR=0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B
   export VRF_KEYHASH=0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae
   export VRF_SUB_ID=<your sub id>
   # optional: VRF_PAY_NATIVE=true to pay VRF in ETH instead of LINK
   forge script script/DeploySqueekPot.s.sol:DeploySqueekPot \
     --rpc-url <sepolia-rpc> --broadcast --account <your-keystore-acct>
   ```
3. **Add the deployed contract as a consumer** on your VRF subscription (vrf.chain.link,
   or `coordinator.addConsumer(subId, pot)`).
4. **Seed the prize** (mode "3"): `SQK.approve(pot, amount)` then `pot.fundPrize(amount)`.
5. **Point the site at it:** set `CONFIG.pot` in `web/index.html` to the deployed address,
   then host it (any static host — e.g. Cloudflare Workers like hamstermining.energy, or
   `python -m http.server` locally). Until then the page runs in a visible **demo mode**.

## Operating

- Anyone can call `requestDraw()` once the daily timer is up, then `settleDraw()` once VRF
  fulfills — so it's self-serve, but a tiny cron/keeper calling both makes draws reliable.
- Keep the VRF subscription funded with LINK (or native) or requests will revert.
- `syncPrize()` sweeps any SQK sent directly to the contract into the prize (harmless).

## Status

Contract + full test suite complete and green (**38 tests**: 35 unit + 3 invariants);
slither clean; **codex-audited over 4 rounds + two fresh agent reviews + a final adversarial
red-team pass** (all findings fixed and regression-tested — see `AUDIT.md`).

**Genesis NFT boost:** holding ≥1 **Squeek Genesis NFT**
(`0xc4c7982657f00509548f3a3a41db7fa439a6856b`) weights your draw snapshot by a fixed,
immutable **+20%** — the NFT's utility, costing the operator nothing. No-loss is untouched
(the boost only shifts odds; the prize still pays from the reserve).

**Provably-fair hardening:** the VRF coordinator is pinned **immutably** and the contract does
**not** inherit Chainlink's `setCoordinator`, so the owner cannot swap the coordinator to censor
an unfavourable draw and re-roll. See `src/PinnedVRFConsumerV2Plus.sol` and `AUDIT.md`.

**DEPLOYED (Sepolia, hardened build):** `0xb10f936e25458aea8f5a62a130b8f5cdd898ebcc`
(owner Main; VRF paid in native ETH; immutable coordinator, no `setCoordinator`; supersedes the
earlier `0x2a865555…` build, which carried the inherited coordinator setter). The contract is a
consumer of the operator's VRF subscription and seeded (5 SQK deposit + 2 SQK prize); the site in
`web/index.html` is live at <https://sqkpot.xyz>.
