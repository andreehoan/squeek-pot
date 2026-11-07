// Squeek Pot — 24h draw keeper (Cloudflare Worker, cron-driven).
//
// Calls the two PERMISSIONLESS draw functions on a schedule so the lottery runs
// itself: requestDraw() once a day (after nextDrawTime), then settleDraw() once
// Chainlink VRF has delivered randomness. Runs every 10 min and only acts when the
// on-chain state calls for it, so it is robust to the draw-time drifting.
//
// The keeper wallet needs ONLY Sepolia ETH for gas. It has no special powers — these
// functions are open to anyone, so a leaked keeper key could at worst trigger draws
// (which anyone can do) and spend the keeper's gas. It can never touch pot funds.

import { ethers } from "ethers";

const POT = "0x2a86555598d4951d2dbfcb545e12e5aab06204d4"; // SqueekPot (hardened + NFT boost), Sepolia
const CHAIN_ID = 11155111;
const POT_ABI = [
  "function canRequestDraw() view returns (bool)",
  "function drawState() view returns (uint8)",
  "function timeUntilDraw() view returns (uint256)",
  "function requestDraw() returns (uint256)",
  "function settleDraw()",
];

// DrawState enum: 0 Idle, 1 Requested (awaiting VRF), 2 Ready (settle now)
async function tick(env) {
  const out = { ts: new Date().toISOString(), actions: [] };
  try {
    const rpc = env.RPC_URL || "https://ethereum-sepolia-rpc.publicnode.com";
    const provider = new ethers.JsonRpcProvider(rpc, CHAIN_ID);
    const wallet = new ethers.Wallet(env.KEEPER_PK, provider);
    const pot = new ethers.Contract(POT, POT_ABI, wallet);

    const state = Number(await pot.drawState());
    out.drawState = state;

    if (state === 2) {
      // randomness is in — pay the winner
      const tx = await pot.settleDraw();
      out.actions.push({ settleDraw: tx.hash });
      await tx.wait(1);
    } else if (state === 0) {
      const can = await pot.canRequestDraw();
      out.canRequestDraw = can;
      if (can) {
        const tx = await pot.requestDraw();
        out.actions.push({ requestDraw: tx.hash });
        await tx.wait(1);
      } else {
        out.timeUntilDraw = Number(await pot.timeUntilDraw());
      }
    }
    // state 1 (Requested): VRF in flight, nothing to do this tick.
    out.ok = true;
  } catch (e) {
    out.ok = false;
    out.error = String((e && e.message) || e);
  }
  return out;
}

export default {
  // cron trigger
  async scheduled(event, env, ctx) {
    ctx.waitUntil(tick(env));
  },
  // manual trigger for testing: GET/POST /run
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === "/run") {
      const r = await tick(env);
      return new Response(JSON.stringify(r, null, 2), {
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(
      "squeek-pot keeper is live. GET /run to trigger a tick now; otherwise it runs on cron.\n",
      { headers: { "content-type": "text/plain" } }
    );
  },
};
