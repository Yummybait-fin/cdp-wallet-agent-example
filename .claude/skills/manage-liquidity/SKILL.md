---
name: manage-liquidity
description: Orchestrate the response to YummyBait position signals — pick an action per STRATEGY.md, build it via the uniswap-tx-builder / swap-integration skills, sign with the cdp MCP, within policy. Use after polling signals (per CLAUDE.md) when deciding how to act on fires.
---

# Manage Liquidity (orchestration)

This skill is the **yummybait-specific glue**. The *mechanics* live in companion skills:

- **`uniswap-tx-builder`** — how to build/simulate collect / close / mint with the
  uniswap-tx-builder MCP, and the close→mint rebalance sequence.
- **`swap-integration`** — how to build a Uniswap swap (for "exit to stable/token").

Your job here: read the user's intent, choose an action, drive those skills, sign, and log.

> **What** to do is governed by **`STRATEGY.md`** (read it each cycle, per `CLAUDE.md`) — treat it
> as authoritative. Respect `config/policy.json` `mode`: in **`observe`, never sign — only report
> (and journal what you *would* do)**.

## First: reconcile the signal config with the strategy

Before acting, check whether `config/rules.json` surfaces what `STRATEGY.md` cares about. If not,
edit `config/rules.json` (see the `yummybait-signals` skill). Never loosen `config/policy.json`.

## Patterns → how to execute

`STRATEGY.md` describes outcomes as patterns; carry them out with the companion skills, then sign
each unsigned tx via the **cdp** MCP:

| Pattern | Steps |
|---------|-------|
| **Collect** | `uniswap-tx-builder` build_collect → sign |
| **Rebalance** | `uniswap-tx-builder` close → sign; recentered mint on a later cycle (see that skill) |
| **Exit to stable** | `uniswap-tx-builder` close → sign; then `swap-integration` swap freed tokens → USDC → sign |
| **Exit to a token** | as above, swapping into the named token |
| **Hold** | nothing |

## Per action

1. Build + **simulate** via the companion skill (keep simulate on).
2. Check `config/policy.json`: action allowed? chain allowed? within USD cap / slippage? If not,
   stop and report why.
3. **Sign** the unsigned tx via the **cdp** MCP. If CDP policy rejects it, report the rejection —
   never route around it.
4. **Log** the decision to `logs/journal.jsonl` (per `logs/README.md`), then report (tx hashes or
   why you waited).

> **Swaps need policy.** A swap goes to the Uniswap **Universal Router**, not the NFPM, so the CDP
> policy rejects it unless the user added the router (README → "Enabling swaps"). If swapping is
> disabled, do the close, then report that you couldn't swap.

## Always

Simulate before signing. Prefer the cheapest effective action. Never exceed the policy. When
uncertain, hold and explain.
