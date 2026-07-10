---
name: onchain-toolkit
description: The standard execution flow for liquidity actions in this repo — how to chain the uniswap-tx-builder, cdp, and evm MCPs so no ad-hoc encoding or RPC code is ever written in the conversation. Use when executing any position action (mint, collect, close, rebalance, wrap, swap).
---

# onchain-toolkit

Everything is covered by the three MCPs — **write no inline encoding/RPC code.**
(The helper scripts that used to live here were absorbed into
`@yummybait/uniswap-tx-builder-mcp` v0.3.1 — see `docs/tasks/tx-builder-adjustments.md`.)

## Standard execution flow (per manage-liquidity)

1. **Plan (mint/rebalance only):** `get_pool_state` (uniswap-tx-builder MCP) with
   `rangePct` for suggested inward-rounded ticks, and with `balance0`/`balance1` + ticks for
   live-ratio `amount0Desired`/`amount1Desired`. **Always recompute amounts in the same breath
   as the mint** — stale ratios revert with "Price slippage check".
2. **Build:** `build_collect` / `build_close` / `build_mint` / `build_increase` /
   `build_wrap` / `build_swap`. Keep `simulate: true` wherever balances/approvals are already
   in place; never sign a tx that failed simulation.
3. **Send:** pass the response's **`rlp`** field directly to the cdp MCP's
   `send_transaction` (`network` "base" or "ethereum"). All signing goes through the cdp MCP —
   never bypass it.
4. **Verify:** `get_transaction_receipt` (evm MCP) — check `status`, and for mints extract the
   position tokenId from the NFPM Transfer-from-zero log.
5. **Journal** per `logs/README.md`.

## Notes

- Native ETH → position tokens: `build_swap` with `wrapWei` (wrap + partial swap + sweep in
  one Universal Router tx); `build_wrap` for wrap-only. Both need the UR in the CDP policy
  (README → "Enabling swaps").
- Mint prerequisites: ERC-20 approvals to the NFPM (`approve` txs are policy-scoped to
  NFPM/Permit2 as spender), plus token balances.
- Balances: evm MCP (`get_balance`, `get_token_balance`) — not curl.
