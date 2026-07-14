---
name: manage-liquidity
description: Orchestrate and execute the response to YummyBait position signals — pick an action per STRATEGY.md, build it with the uniswap-tx-builder MCP, sign with the cdp MCP, verify via the evm MCP, within policy. Use when acting on signal fires, and when executing any position action (mint, collect, close, rebalance, wrap, swap) — even outside a poll cycle.
---

# Manage Liquidity

This skill is the **yummybait-specific glue**: decide what to do (per `STRATEGY.md`), then
execute it by chaining the three MCPs. Tool mechanics for collect / close / mint (and the
close→mint rebalance sequence) live in the companion **`uniswap-tx-builder`** skill.

> **What** to do is governed by **`STRATEGY.md`** (read it each cycle, per `CLAUDE.md`) — treat it
> as authoritative. Respect `config/agent-config.json` `mode`: in **`observe`, never sign — only report
> (and journal what you *would* do)**.

## First: reconcile the signal config with the strategy

Before acting, check whether `config/rules.json` surfaces what `STRATEGY.md` cares about. If not,
edit `config/rules.json` (see the `yummybait-signals` skill). Never loosen `config/agent-config.json`.

## Patterns → how to execute

`STRATEGY.md` describes outcomes as patterns; carry them out with the execution flow below,
signing each unsigned tx via the **cdp** MCP:

| Pattern | Steps |
|---------|-------|
| **Collect** | `build_collect` → sign |
| **Rebalance** | `build_close` → sign; recentered mint on a later cycle (see `uniswap-tx-builder`) |
| **Exit to stable** | `build_close` → sign; then `build_swap` freed WETH → USDC → sign |
| **Exit to a token** | as above, with that token as `tokenOut` (`build_swap` swaps from WETH only) |
| **Hold** | nothing |

## Execution flow (every action)

Everything is covered by the three MCPs — **write no inline encoding/RPC code.**

1. **Stop-loss check (total wallet loss, before every action).** Skip only if both
   `maxLossUsd` and `maxLossEth` in `config/agent-config.json` are `null`/absent (they are
   optional and off by default). Otherwise:
   - **Current total wallet value (USD):** native ETH + the CDP-policy tokens' balances
     (evm MCP `get_balance` / `get_token_balance`), plus Σ over open positions of
     `liquidity_value_usd + uncollected_fees_usd` (signals metrics). **ETH-denominated
     total:** USD total ÷ the ETH/USD price from `get_pool_state` of the WETH/USDC pool.
   - **Baseline:** `.state/baseline.json` (`{"usd": …, "eth": …, "recordedAt": …}`). If it
     doesn't exist, record the current totals now (loss = 0) and continue. Never overwrite it
     yourself — the user resets the stop by deleting the file or raising the caps.
   - **Loss = baseline − current**, per denomination. If loss > `maxLossUsd` **or**
     loss > `maxLossEth`, **halt: sign nothing** — not even a close — unless `STRATEGY.md`
     explicitly says what to do on a stop-loss breach. Report the breach prominently, journal
     it (`decision: "halt"`, per `logs/README.md`), and wait for the user. A tripped stop means
     the strategy or the data needs human review, not an autonomous exit.
2. **Plan (mint/rebalance only):** `get_pool_state` (uniswap-tx-builder MCP) with
   `rangePct` for suggested inward-rounded ticks, and with `balance0`/`balance1` + ticks for
   live-ratio `amount0Desired`/`amount1Desired`. **Always recompute amounts in the same breath
   as the mint** — stale ratios revert with "Price slippage check".
3. **Build:** `build_collect` / `build_close` / `build_mint` / `build_increase` /
   `build_wrap` / `build_swap`. Keep `simulate: true` wherever balances/approvals are already
   in place; never sign a tx that failed simulation.
4. **Policy check.** Against `config/agent-config.json`: within the USD cap / slippage cap?
   If not, stop and report why. Which *actions, chains, and tokens* are allowed is not
   configured there — it's whatever the applied **CDP Wallet Policy** accepts. Read it once per
   session (cdp MCP → `policy_engine_policies_list`) and infer the allowances: NFPM accepted on
   a chain → LP actions there; token `approve` rules → mintable tokens; Universal Router
   (+ Permit2) accepted → swaps enabled. If the contract a tx must call isn't accepted, don't
   build it — report why instead.
5. **Send:** pass the response's **`rlp`** field directly to the cdp MCP's
   `send_transaction` (`network` "base" or "ethereum"). All signing goes through the cdp MCP —
   never bypass it. If CDP policy rejects the tx, report the rejection — never route around it.
6. **Verify:** `get_transaction_receipt` (evm MCP) — check `status`, and for mints extract the
   position tokenId from the NFPM Transfer-from-zero log.
7. **Journal** the decision to `logs/journal.jsonl` (per `logs/README.md`), then report
   (tx hashes or why you waited).

> **Swaps need policy.** A swap goes to the Uniswap **Universal Router**, not the NFPM, so the CDP
> policy rejects it unless the user added the router (README → "Enabling swaps"). You know from
> the policy read in step 4 whether it's there — if not, do the close, then report that swapping
> is disabled. Never discover allowances by trial-and-error signing.

## Notes

- Native ETH → position tokens: `build_swap` with `wrapWei` (wrap + partial swap + sweep in
  one Universal Router tx); `build_wrap` for wrap-only. Both need the UR in the CDP policy
  (README → "Enabling swaps").
- Mint prerequisites: ERC-20 approvals to the NFPM (`approve` txs are policy-scoped to the
  NFPM as spender — plus Permit2 if swaps are enabled), plus token balances.
- Balances: evm MCP (`get_balance`, `get_token_balance`) — not curl.

## Always

Simulate before signing. Prefer the cheapest effective action. Never exceed the policy. When
uncertain, hold and explain.
