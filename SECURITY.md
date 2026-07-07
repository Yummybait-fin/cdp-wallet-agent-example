# Security

This agent can move funds. Its trust model is **defense in depth**: even a fully
compromised codebase cannot move money outside the wallet policy. This document
describes the guarantees and the practices that back them.

## Trust model (authority is not in this code)

- **Non-custodial.** Funds stay in the user's account. The agent spends only under
  a capped, revocable **CDP Spend Permission**.
- **CDP Wallet Policy** (enforced by Coinbase, server-side / in-enclave — *not* by
  this repo): the agent may call **only** the Uniswap NFPM / v4 PositionManager /
  Universal Router, **only** the methods collect / decreaseLiquidity / mint / swap,
  under per-transaction and per-session amount caps. Anything else is rejected
  before signing.
- **Official transaction payloads.** Swaps come from the Uniswap Trading API; LP
  calldata from the official `@uniswap/v3-sdk` / `@uniswap/v4-sdk`. This repo only
  orchestrates — it never hand-rolls calldata.

The practical consequence: the worst a backdoor in our code (or a dependency) can
do is request a transaction the policy will reject.

## The CDP Wallet Policy (applied by you, enforced by Coinbase)

The wallet's hard limit is a **CDP Wallet Policy** you set on your CDP project — see README
"Apply the CDP policy" (Portal / CDP CLI / curl). It is **not** in this repo and not in the
agent's prompt; Coinbase enforces it server-side at signing time.

**Hard (enforced by Coinbase, not our code):** the policy rejects any `signEvmTransaction` whose
`to` is not the Uniswap NonfungiblePositionManager — so a hijacked agent still can't call an
arbitrary contract. Apply the policy **before** switching `config/policy.json` to `mode: act`;
until then the wallet has whatever policy (if any) your project already had.

**Soft / follow-ups (validate against live CDP):**
- Per-tx **USD cap** (`maxTxUsd`) → the `netUSDChange` criterion can enforce this; not yet wired.
- **Method allowlist** (collect/decreaseLiquidity/mint) → the `evmData` criterion; not yet wired.
- **Chain limits** — `evmNetwork` is not valid on `signEvmTransaction`, so reach is bounded by the
  NFPM contract allowlist rather than by network here.
- **Spend Permission** (capped, revocable token allowance) — provisioned separately.

## Process isolation

`docker-compose.yml` runs the two MCPs as services (the agent is a local process that connects to
them over HTTP). The **cdp-mcp** service is the only one that touches keys — for hardening, give it
a **network egress allowlist** (only `api.cdp.coinbase.com`), no host filesystem mounts, and
secrets via env at run time (never baked into an image). The **uniswap-tx-builder-mcp** service is
keyless — it runs the published image
[`ghcr.io/yummybait-fin/uniswap-tx-builder-mcp`](https://github.com/Yummybait-fin/uniswap-tx-builder-mcp);
**pin an exact tag** (not `:latest`) so the image is reproducible and auditable.

## Supply chain

This repo has **no application code or npm dependencies** — just config, prompts, and
`docker-compose.yml`. The supply-chain surface is the three things compose pulls/builds:

- **`@coinbase/cdp-cli`** (the key-touching one) — **pin an exact version** in `cdp-mcp.Dockerfile`
  (not `@latest`), verify npm provenance (`npm audit signatures`), and review every bump.
- **`mcp-proxy`** — pin the version in `cdp-mcp.Dockerfile`.
- **`ghcr.io/yummybait-fin/uniswap-tx-builder-mcp`** image — pin the tag + verify the digest;
  keyless, so bounded by the wallet policy anyway.

Before bumping any of these: diff the release for new network calls / `child_process` / env-var
access, prefer provenance-signed publishes, and run under egress monitoring in a sandbox first.

## Reporting

Report suspected vulnerabilities privately to the maintainers (do not open a public
issue). Include affected version, impact, and reproduction steps.
