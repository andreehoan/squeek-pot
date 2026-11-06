# Squeek Pot — draw keeper (Cloudflare Worker)

Runs the lottery on autopilot. Every 10 minutes it checks the pot and:

- if a draw is due (`canRequestDraw()`) → calls **`requestDraw()`** (freezes the snapshot, asks Chainlink VRF for randomness)
- once VRF has delivered (`drawState == Ready`) → calls **`settleDraw()`** (pays the winner)

Both functions are **permissionless** — the keeper has no special powers. It just needs gas.

## Why a Worker (not wraith / a local script)

Always-on, free tier, no machine to keep running. The 10-minute cron catches the daily
window even as the exact draw time drifts, and settles the moment randomness lands.

## Deploy (one-time, ~5 min)

```bash
cd keeper
npm install
npx wrangler login            # authorise your Cloudflare account

# 1. Make a THROWAWAY keeper wallet (NOT Main, NOT aviann). Any new EOA.
#    Fund it with a little Sepolia ETH (0.05 is plenty for months of daily draws).

# 2. Store its private key as an encrypted Worker secret (never in the repo):
npx wrangler secret put KEEPER_PK      # paste the 0x… key when prompted

# 3. (optional) a private RPC if the public node rate-limits:
# npx wrangler secret put RPC_URL      # e.g. https://eth-sepolia.g.alchemy.com/v2/<key>

# 4. Ship it:
npm run deploy
```

That's it — the cron starts immediately. Watch it with `npm run tail`, or hit
`https://squeek-pot-keeper.<your-subdomain>.workers.dev/run` to trigger a tick by hand.

## Security

- `KEEPER_PK` is a **Cloudflare secret** (encrypted at rest, not in git, not in the bundle).
- Use a **dedicated throwaway wallet** that holds only gas. Worst case if the key ever
  leaked: someone triggers draws (which anyone already can) and burns the keeper's gas.
  **It can never reach pot funds** — `requestDraw`/`settleDraw` move nothing to the caller.
- The keeper address is **not** privileged on the contract and is **not** the VRF sub owner.

## Config

- Target contract + chain live in `src/index.js` (`POT`, `CHAIN_ID`). If you ever redeploy
  the pot, bump `POT` and `npm run deploy` again.
- Cron cadence is in `wrangler.toml` (`*/10 * * * *`). Loosen to `*/15` or tighten to `*/5`
  if you like; 10 min keeps settle latency low at negligible cost.
