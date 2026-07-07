# yummybait-agent

A reference for running a **local Claude agent** that watches **YummyBait** position signals and
manages Uniswap v3 positions — **no runner program**. It's just **CLAUDE.md + skills + config**
that your local Claude (Claude Code) follows, plus **MCP servers in docker-compose**. A
non-technical user adjusts behavior in plain English and never touches code.

## How it's wired

```
            ┌────────────────────── this repo (config + prompts) ───────────────────┐
 signals    │  CLAUDE.md  ── you (local Claude) follow this each poll cycle          │
 API  ◄─────┤  .claude/skills/  yummybait-signals (poll+translate) · manage-liquidity│
   curl     │  STRATEGY.md (intent, plain English)  ·  config/ wallets·rules·policy  │
            │  .mcp.json ──► http://localhost:8102  uniswap-tx-builder (keyless)      │
            │            └─► http://localhost:8101  cdp (sign/broadcast, policy-bound)│
            └────────────────────────────────────────────────────────────────────────┘
   the agent is LOCAL (Claude Code); the two MCPs + policy bootstrap run in docker-compose.
```

- **uniswap-tx-builder MCP** — public, keyless server
  ([repo](https://github.com/Yummybait-fin/uniswap-tx-builder-mcp); stdio or streamable HTTP).
  Builds unsigned `collect`/`close`/`mint`/`increase` txs (and `plan_position`/`simulate`), never
  signs. Runs as a compose service on `:8102`.
- **cdp MCP** — Coinbase's own wallet MCP, unmodified, exposed over HTTP/SSE by `mcp-proxy` on
  `:8101`. Its CDP Wallet Policy is something **you apply to your CDP project** (see "Apply the
  CDP policy") — enforced by Coinbase, not by this repo. We write no *signing* code.
- **Skills** carry the *behavior* (the decision playbook); **config** carries the *limits*.

## What a less-technical user edits

| File | Controls |
|------|----------|
| **`STRATEGY.md`** | **how the agent decides — the prompt. Edit it, see different behavior next poll.** |
| `config/wallets.json` | which addresses to watch |
| `config/rules.json` | which signals wake the agent (CEL rules) |
| `config/policy.json` | `mode` (observe/act) + caps: max USD/tx, slippage, allowed actions + chains |
| `.env` | the signals key + CDP wallet creds |

**No code.** Just `CLAUDE.md` + the two skills + config + `docker-compose.yml`; the agent is your
local Claude. Write `STRATEGY.md` in **plain English with no metric names** — the
`yummybait-signals` skill translates intent into `config/rules.json` (via the metrics catalog) and
the `manage-liquidity` skill carries the tool *mechanics*.

## Trust model

The agent's code has **no authority of its own**:
- **Keyless tx building** — `uniswap-tx-builder` never holds keys; it only builds + simulates.
- **CDP Wallet Policy you apply to your project** (see "Apply the CDP policy"). The **enforced**
  guarantee: the agent can call **only the Uniswap NFPM** contract — Coinbase rejects anything
  else before signing, regardless of prompt or bug. (Per-tx USD cap and method-level limits are
  refinements; see `SECURITY.md`.)
- **Non-custodial** — funds stay the user's, spent under a revocable Spend Permission.
- **Trim surface** — the wallet runs as a separate, audited Coinbase process, not bundled deps.

> **Hard vs soft:** the contract allowlist is *hard* (enforced by Coinbase). `maxTxUsd` /
> `maxSlippageBps` in `config/policy.json` are currently *soft* (surfaced in the prompt) until
> wired to CDP `netUSDChange` / built into the tx — see `SECURITY.md`.

## Observe vs act

There's no `EXECUTION_MODE` flag — the agent reads `mode` in `config/policy.json`:
- **`observe`** *(default)* — poll, reason, and report what it *would* do. Never signs.
- **`act`** — execute within policy. Asking the agent "just tell me / dry run" forces observe.

## Apply the CDP policy (do this first, before `act`)

The wallet's hard limits live in a **CDP Wallet Policy** you set on your CDP project — *not* in
this repo. Apply one that lets the agent call **only the Uniswap NonfungiblePositionManager**, so
a bug or bad prompt can't move funds anywhere else. The policy (matches `config/policy.json`
`allowedChains` 1 + 8453 → their NFPM contracts):

```json
{
  "scope": "project",
  "description": "yummybait-agent: Uniswap NFPM allowlist",
  "rules": [
    {
      "action": "reject",
      "operation": "signEvmTransaction",
      "criteria": [
        {
          "type": "evmAddress",
          "operator": "not in",
          "addresses": [
            "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"
          ]
        }
      ]
    }
  ]
}
```

Apply it by **either**:

- **CDP Portal** (easiest): <https://portal.cdp.coinbase.com/> → your project → Policies → create
  with the rules above.
- **CDP CLI** (`@coinbase/cdp-cli`, handles auth/JWT for you) — ask it (or the `cdp` MCP) to
  `POST /platform/v2/policy-engine/policies` with that body.
- **curl** (you must mint a JWT from your API key first — see
  [CDP API auth](https://docs.cdp.coinbase.com/api-reference/v2/authentication)):

  ```bash
  curl -X POST https://api.cdp.coinbase.com/platform/v2/policy-engine/policies \
    -H "Authorization: Bearer $CDP_JWT" \
    -H "Content-Type: application/json" \
    -d @cdp-policy.json
  ```

> Hard vs soft: this contract allowlist is **enforced by Coinbase**. The `maxTxUsd` /
> `maxSlippageBps` in `config/policy.json` are currently *soft* (prompt-only) — see `SECURITY.md`
> for wiring them to CDP `netUSDChange` / `evmData`.

### Enabling swaps (for "exit to USD")

The policy above allows **only** the NFPM, so LP actions (collect/close/rebalance) work but
**swaps are rejected**. To let the agent swap (e.g. exit a position to USDC), add your chain's
Uniswap **Universal Router** (and **Permit2**) to the `addresses` allowlist — see
[Uniswap deployment addresses](https://docs.uniswap.org/contracts/v3/reference/deployments/).
This is opt-in and *widens* what the agent can call, so only add it if you want the "exit to
stable / token" patterns. Leave it out for LP-only management.

## Run it

**1. Install the companion skills** (project-scoped, into `.claude/skills/`):

```bash
# a) uniswap-tx-builder — ships with the MCP repo:
npx -p github:Yummybait-fin/uniswap-tx-builder-mcp uniswap-tx-builder-skill --project
#    (or in Claude Code:  /plugin marketplace add Yummybait-fin/uniswap-tx-builder-mcp
#                          /plugin install uniswap-tx-builder@yummybait)

# b) swap-integration — the official Uniswap skill (only for the "exit to stable/token"
#    patterns):  npx skills add Uniswap/uniswap-ai
#    (or in Claude Code:  /plugin marketplace add uniswap/uniswap-ai → /plugin install uniswap-trading)
```

**2. Start the MCPs:**

```bash
cp .env.example .env          # YBT_API_URL, YBT_SIGNALS_KEY, CDP_* (for act)
docker compose up -d          # cdp-mcp(:8101) + uniswap-tx-builder-mcp(:8102, GHCR image)
```

No clone or build needed — the tx-builder MCP is pulled as a published image
(`ghcr.io/yummybait-fin/uniswap-tx-builder-mcp`); pin an exact tag for production.

**3. Set your intent:** edit `STRATEGY.md`, `config/wallets.json`, `config/rules.json`, and
`config/policy.json` (`mode`).

**4. Ask your local Claude (in this directory):** it reads `CLAUDE.md` automatically.

```bash
source .env                   # so the signals-poll curl sees YBT_API_URL / YBT_SIGNALS_KEY

# one-off:
claude "Poll my YummyBait signals once and tell me what you'd do."

# periodic — let the agent self-pace, or with an interval:
claude "/loop 5m Poll my YummyBait signals and act on them per my strategy."
```

To go live, apply the CDP policy (above), set `"mode": "act"` in `config/policy.json`, and ensure
`CDP_*` are set.

## Prereqs

- **A `ybt_live_*` signals key** — the signals API is built but not yet public, so run the
  backend locally and mint/seed one.
- **A Coinbase Developer Platform account** (for `act`). Register at
  <https://portal.cdp.coinbase.com/>, create a project, then generate:
  - a **Secret API Key** → `CDP_API_KEY_ID` + `CDP_API_KEY_SECRET`, and
  - a **Wallet Secret** → `CDP_WALLET_SECRET` (required for signing).

  Put these in `.env`, then apply the **CDP Wallet Policy** (see "Apply the CDP policy"). Not
  needed for `observe` mode.
- **Your local Claude Code** in this directory (it reads `CLAUDE.md`).
