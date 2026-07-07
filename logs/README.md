# Execution journal

The agent appends one JSON object per line to **`logs/journal.jsonl`** (append-only, git-ignored)
on every poll cycle — one record per position decision, including in `observe` mode (where it
records what it *would* have done). This is the human-readable "why"; the authoritative "what was
signed" lives in your **CDP activity log** (Coinbase, keyed on timestamp/signer/counterparty).

## Record schema

```json
{
  "ts": "2026-06-23T15:20:00Z",     // ISO-8601 UTC
  "mode": "observe",                  // observe | act
  "position_id": "1:12345",           // "{chain_id}:{token_id}" (or null for a no-position cycle)
  "signals": ["went_oor"],            // rule names that fired for this position
  "decision": "exit_to_stable",       // collect | rebalance | exit_to_stable | exit_to_token | hold
  "rationale": "OOR 40m, IL 6% > fees; strategy prefers cash",
  "txs": [                             // [] in observe mode
    { "action": "close", "hash": "0x…", "status": "confirmed" },
    { "action": "swap",  "hash": "0x…", "status": "confirmed", "detail": "WETH→USDC" }
  ],
  "outcome": "closed + swapped ~$120 to USDC",
  "cursor": "1717761600"              // signals cursor at this cycle (for correlation)
}
```

## Uses

- **Audit** — what the agent did and why, line by line.
- **Forward-test** — run in `observe` for a while; the `decision`/`rationale` stream is a paper
  record of how a `STRATEGY.md` behaves on live signals before you switch to `act`.
- **Tuning** — grep for `"decision":"hold"` vs acts, or per-rule fire counts, to refine
  `STRATEGY.md` / `config/rules.json`.

```bash
# quick views
jq -c 'select(.mode=="act")' logs/journal.jsonl
jq -r '.decision' logs/journal.jsonl | sort | uniq -c
```
