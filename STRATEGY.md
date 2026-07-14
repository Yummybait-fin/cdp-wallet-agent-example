# Agent Strategy

Tell the agent, in plain English, how to look after your Uniswap liquidity. Edit this freely —
the agent re-reads it every cycle, so changes show up on the next run. **No code, no metric
names:** describe what you want using the patterns below, and the agent translates it into signal
rules + tool calls for you.

> This sets *intent* only. Your hard spending limits live in the **CDP Wallet Policy** (and
> `config/agent-config.json`); the agent can never exceed them — whatever you write here.

## The action patterns (building blocks)

The agent can do these. You compose them in "My preferences" below.

- **Collect** — claim a position's accrued fees, leave the position open.
- **Rebalance** — close a position and re-open it centered on the current price (a tighter or
  wider range). Use for *"exit and rebalance."*
- **Exit to stable** — close a position and **swap the freed tokens to a stablecoin** (e.g. USDC).
  Use for *"exit and swap to USD."* (Requires swaps to be enabled — see note.)
- **Exit to a token** — close and swap everything into one token you name.
- **Hold** — do nothing this cycle.

> *Swaps* (the two "exit to …" patterns) only work if the CDP Wallet Policy allows the Uniswap
> router — see README "Apply the CDP policy". If it doesn't, the agent will collect/close/rebalance
> but report that it can't swap.

## How careful to be

Cautious. Don't react to every wobble — treat an alert as a reason to *check*, not to act. Only
move when it clearly leaves me better off after fees and gas. When unsure, **hold** and explain.

## My preferences  ← edit this part to change behavior

- **When a position drifts off the current price and looks like it'll stay there:**
  exit and rebalance into a fresh range around the new price. (If it's likely a brief excursion,
  hold.)
- **When a position is meaningfully worse off than just holding the tokens (or impermanent loss is
  high):** exit to stable (USDC) — I'd rather sit in cash than keep bleeding.
- **When fees have built up beyond the gas to claim them:** collect.
- **When a position is dropping fast for a structural reason:** exit to stable.
- **My stablecoin:** USDC. **Re-balance width:** moderate (wider for volatile pairs, tighter for
  stable pairs).
- **Default when unsure:** hold and tell me.

## Always

Simulate before signing. Never exceed the policy. Prefer the cheapest effective action. Report
what you did (with tx hashes) or why you waited.

<!--
Rewrite "My preferences" to change behavior, e.g.:
  • "Always exit to USDC — never rebalance. I want out, not re-deployed."
  • "Aggressively rebalance on any drift; only exit to stable if IL is extreme."
  • "Fees only — collect when worthwhile, otherwise just tell me; never close or swap."
-->
