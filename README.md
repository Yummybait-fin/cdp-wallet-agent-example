# yummybait-agent

A reference for running a **local Claude agent** that watches **YummyBait** position signals and
manages Uniswap v3 positions — **no runner program**. It's just **CLAUDE.md + skills + config**
that your local Claude (Claude Code) follows, plus **stdio MCP servers** it spawns on demand
(`.mcp.json`). A non-technical user adjusts behavior in plain English and never touches code.

## How it's wired

```
            ┌────────────────────── this repo (config + prompts) ───────────────────┐
 signals    │  CLAUDE.md  ── you (local Claude) follow this each poll cycle          │
 API  ◄─────┤  .claude/skills/  yummybait-signals (poll+translate) · manage-liquidity│
   curl     │  STRATEGY.md (intent, plain English)  ·  config/ wallets·rules·policy  │
            │  .mcp.json ──► uniswap-tx-builder (keyless, npx stdio)                  │
            │            ├─► cdp (sign/broadcast, policy-bound, npx stdio)            │
            │            └─► evm (read-only chain access, npx stdio)                  │
            └────────────────────────────────────────────────────────────────────────┘
   the agent is LOCAL (Claude Code); it spawns each MCP as a stdio child process per session.
```

- **uniswap-tx-builder MCP** — public, keyless server
  ([repo](https://github.com/Yummybait-fin/uniswap-tx-builder-mcp) ·
  [npm](https://www.npmjs.com/package/@yummybait/uniswap-tx-builder-mcp); stdio or streamable
  HTTP). Builds unsigned `collect`/`close`/`mint`/`increase`/`wrap`/`swap` txs (plus
  `get_pool_state`, `plan_position`, `simulate`, and ready-to-sign `rlp` output), never signs.
- **cdp MCP** — Coinbase's own wallet MCP, unmodified (`npx @coinbase/cdp-cli mcp`). Its CDP
  Wallet Policy is something **you apply to your CDP project** (see "Apply the CDP policy") —
  enforced by Coinbase, not by this repo. We write no *signing* code. One-time authorization:
  `cdp env live` (see "Run it" step 2).
- **evm MCP** — read-only chain access (receipts with decoded logs, balances, contract reads),
  `npx @mcpdotdirect/evm-mcp-server`. Keyless.
- **Skills** carry the *behavior* (the decision playbook); **config** carries the *limits*.

> **Remote deployments:** the tx-builder MCP also supports streamable HTTP (`MCP_HTTP_PORT`,
> see its [repo](https://github.com/Yummybait-fin/uniswap-tx-builder-mcp)) if you ever need the
> agent and MCPs on different hosts — point `.mcp.json` at the URL instead of a stdio command.
> Out of scope for this repo.

## What a less-technical user edits

| File | Controls |
|------|----------|
| **`STRATEGY.md`** | **how the agent decides — the prompt. Edit it, see different behavior next poll.** |
| `config/wallets.json` | which addresses to watch |
| `config/rules.json` | which signals wake the agent (CEL rules) |
| `config/policy.json` | `mode` (observe/act) + caps: max USD/tx, slippage, allowed actions + chains |
| `.env` | the signals key + CDP wallet creds |

**No code.** Just `CLAUDE.md` + the skills + config + `.mcp.json`; the agent is your
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
this repo. Apply one that lets the agent call **only the Uniswap NonfungiblePositionManager**
(plus ERC-20 `approve` scoped to the NFPM as spender — required to *mint* new positions), so a
bug or bad prompt can't move funds anywhere else. CDP policies are default-deny: a request that
matches no `accept` rule is rejected. The policy (matches `config/policy.json` `allowedChains`
1 + 8453 → their NFPM contracts, and `allowedTokens` → Base WETH/USDC for approvals):

```json
{
  "scope": "project",
  "description": "yummybait agent. NFPM, approvals, swaps, no raw",
  "rules": [
    { "action": "reject", "operation": "signEvmHash" },
    {
      "action": "reject",
      "operation": "signEvmMessage",
      "criteria": [{ "type": "evmMessage", "match": "(?s).*" }]
    },
    {
      "action": "accept",
      "operation": "signEvmTransaction",
      "criteria": [
        {
          "type": "evmAddress",
          "operator": "in",
          "addresses": [
            "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
            "0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"
          ]
        }
      ]
    },
    {
      "action": "accept",
      "operation": "signEvmTransaction",
      "criteria": [
        {
          "type": "evmAddress",
          "operator": "in",
          "addresses": [
            "0x4200000000000000000000000000000000000006",
            "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
          ]
        },
        {
          "type": "evmData",
          "abi": "erc20",
          "conditions": [
            {
              "function": "approve",
              "params": [
                {
                  "name": "spender",
                  "operator": "in",
                  "values": ["0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"]
                }
              ]
            }
          ]
        }
      ]
    },
    {
      "action": "accept",
      "operation": "sendEvmTransaction",
      "criteria": [
        { "type": "evmNetwork", "operator": "in", "networks": ["ethereum"] },
        {
          "type": "evmAddress",
          "operator": "in",
          "addresses": ["0xC36442b4a4522E871399CD717aBDD847Ab11FE88"]
        }
      ]
    },
    {
      "action": "accept",
      "operation": "sendEvmTransaction",
      "criteria": [
        { "type": "evmNetwork", "operator": "in", "networks": ["base"] },
        {
          "type": "evmAddress",
          "operator": "in",
          "addresses": ["0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"]
        }
      ]
    },
    {
      "action": "accept",
      "operation": "sendEvmTransaction",
      "criteria": [
        { "type": "evmNetwork", "operator": "in", "networks": ["base"] },
        {
          "type": "evmAddress",
          "operator": "in",
          "addresses": [
            "0x4200000000000000000000000000000000000006",
            "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
          ]
        },
        {
          "type": "evmData",
          "abi": "erc20",
          "conditions": [
            {
              "function": "approve",
              "params": [
                {
                  "name": "spender",
                  "operator": "in",
                  "values": ["0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1"]
                }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

Rule notes: the two `evmData` rules let the wallet approve **only Base WETH/USDC** and **only
with the Base NFPM or Permit2 as spender** — any other calldata to a token contract (e.g.
`transfer`) falls through and is rejected. `evmNetwork` pins each contract address to its chain
(supported on `sendEvmTransaction`; the `signEvmTransaction` rules are address-only, as the
policy engine does not accept a network criterion there).

> ⚠️ **The two `reject` rules at the top are load-bearing.** Operations with **no rules at all
> are allowed by default** (verified empirically 2026-07-10: with no `signEvmHash` rule, the
> wallet happily signed an arbitrary raw hash). A raw 32-byte hash can be the keccak of a
> serialized transaction, so allowing `signEvmHash` is a full bypass of the address allowlist.
> If you write your own policy, always end with explicit rejects for `signEvmHash` and
> `signEvmMessage`.

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

With only the rules above, LP actions (collect/close/mint/rebalance) work but **swaps are
rejected**. To let the agent swap (e.g. exit a position to USDC, or convert native ETH into
position tokens), add `accept` rules for your chain's Uniswap **Universal Router** and
**Permit2** — see
[Uniswap deployment addresses](https://docs.uniswap.org/contracts/v3/reference/deployments/).
This is opt-in and *widens* what the agent can call; leave it out for LP-only management.
For Base, that means three more rules:

- `signEvmTransaction` + `sendEvmTransaction` (network `base`) accepting calls to the official
  Universal Router deployments — v1.2 `0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD`,
  v2.0 `0x6fF5693b99212Da76ad316178A184AB56D299b43`, v2.1
  `0xf3A4F4094BD2C6C06cA2F61789d8727b8d1e7259` (the Trading API picks the router per route type);
- Permit2 `0x000000000022D473030F116dDEE9F6B43aC78BA3` added as an allowed `approve` spender in
  the ERC-20 rules above;
- a `signEvmTypedData` rule accepting typed data whose verifying contract is Permit2, so the
  wallet can sign Permit2 permits for CLASSIC routes.

## Run it

**1. Install the companion skills** (project-scoped, into `.claude/skills/`):

```bash
# a) uniswap-tx-builder — ships with the MCP package:
npx -p @yummybait/uniswap-tx-builder-mcp uniswap-tx-builder-skill --project
#    (or in Claude Code:  /plugin marketplace add Yummybait-fin/uniswap-tx-builder-mcp
#                          /plugin install uniswap-tx-builder@yummybait)

# b) swap-integration — the official Uniswap skill (only for the "exit to stable/token"
#    patterns):  npx skills add Uniswap/uniswap-ai
#    (or in Claude Code:  /plugin marketplace add uniswap/uniswap-ai → /plugin install uniswap-trading)
```

**2. Configure credentials** (the MCPs themselves need no starting — Claude Code spawns them
from `.mcp.json` per session):

```bash
cp .env.example .env          # YBT_API_URL, YBT_SIGNALS_KEY

# authorize the cdp MCP (one-time, only needed for act mode):
npx -y @coinbase/cdp-cli env live --key-file path/to/key.json   # API key from the CDP portal
npx -y @coinbase/cdp-cli env live --wallet-secret=<your-wallet-secret>
npx -y @coinbase/cdp-cli env                                    # verify: shows "live" + key ID
```

Secrets land in your OS keyring. (Keyring-less host? `--plaintext` has a known cdp-cli bug —
see `docs/mcp-issues.md` #2 for the workaround.)

All three MCPs are spawned via `npx` from published packages (versions pinned in `.mcp.json`).

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
- **Node 18+** (`npx` spawns all three MCPs).
