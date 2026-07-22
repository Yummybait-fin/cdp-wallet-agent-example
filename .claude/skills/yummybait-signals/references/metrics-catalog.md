# Signals metrics — live, rule-usable surface

These are the metrics a `config/rules.json` CEL expression can reference **today** (the sampler
populates them per position). This is the subset of the full YummyBait metrics catalog that is
live on the signals path. Use it to translate `STRATEGY.md` intent into rules.

## Current values

| Metric | Type | Human meaning |
|--------|------|---------------|
| `in_range` | bool | Is the current pool price inside the position's range? `false` = out of range, earning no fees. |
| `pnl_usd` | usd | Profit/loss vs what you put in. |
| `pnl_hodl` | usd | Profit/loss **vs simply holding the entry tokens**. Negative = you'd have been better off not LPing (captures impermanent-loss underperformance). |
| `il_pct` | percent | Impermanent loss, as a percent. |
| `liquidity_value_usd` | usd | Current USD value of the tokens in the position. |
| `uncollected_fees_usd` | usd | Fees earned but not yet collected. |
| `breakeven_margin` | usd-ish | Distance from breaking even. Near `0` = hovering at breakeven; negative = underwater. |
| `tvl_usd` | usd | Total value locked in the pool (pool size). |

## Windowed change (current minus one window ago)

For `pnl_usd`, `pnl_hodl`, `liquidity_value_usd`, `uncollected_fees_usd`, `tvl_usd`, and
`breakeven_margin`, suffix with `_change_1h`, `_change_1d`, or `_change_1w`:
e.g. `pnl_usd_change_1d`, `breakeven_margin_change_1w`.

## Phrase → expression (translate STRATEGY.md like this)

| Strategy says… | CEL `when` | Notes |
|----------------|-----------|-------|
| drifted off the price | `!in_range` | add `"for": "30m"` for "…and stays there" |
| worse off than just holding | `pnl_hodl < 0` | tighten the threshold for "meaningfully", e.g. `< -50.0` |
| impermanent loss is high | `il_pct > 5.0` | raise to `> 20.0` for "extreme" |
| fees worth collecting | `uncollected_fees_usd > 25.0` | threshold ≈ the gas to claim |
| losing value quickly | `pnl_usd_change_1d < -50.0` | or `liquidity_value_usd_change_1d < -100.0` |
| hovering at breakeven | `breakeven_margin > -1.0 && breakeven_margin < 1.0` | pair with `"for"` to avoid flicker |

Thresholds are judgement calls — pick sensible numbers for the user's risk tolerance and adjust.
Use `for` for "sustained / and stays there" and `cooldown` to avoid repeated firing.

## Not yet usable (will silently never fire)

`pool.*`, `range_analysis.*` (distance-to-bound, volatility, ETA-to-bound, days-to-breakeven),
and `market.*` (ETH/BTC, Fear & Greed) exist in the full catalog but are **not populated** on
the signals path yet — a rule referencing them evaluates to null and won't fire. A null metric
makes the whole expression false, so rules degrade safely. (Full catalog:
<https://docs.yummybait.finance/reference/metrics-catalog/>.)
