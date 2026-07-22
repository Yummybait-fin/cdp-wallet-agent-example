---
name: yummybait-signals
description: Translate the plain-English STRATEGY.md into concrete YummyBait signal rules (config/rules.json) using the metrics catalog, and interpret fired signals. Use when reconciling the strategy with the signal config, or interpreting fires before acting.
---

# YummyBait Signals — translation & reference

`STRATEGY.md` is written in human terms ("when a position drifts away from the price and stays
there…"). **Your job here is to translate that intent into concrete signal rules** — CEL
expressions over YummyBait metrics in `config/rules.json` — and to interpret the fires that come
back. The user should never have to know metric names; you map them.

## How signals work

Pull-based: a sampler snapshots every open position ~once a minute; **you** poll
`POST /v1/signals` with the wallets + your `config/rules.json`. A **fire** means a rule's CEL
condition held for a position. Fires identify a position by `position_id = "{chain_id}:{token_id}"`.

Full wire contract in the public docs — <https://docs.yummybait.finance/signals/> (overview),
[`signals/polling/`](https://docs.yummybait.finance/signals/polling/),
[`signals/payload/`](https://docs.yummybait.finance/signals/payload/),
[`signals/versioning/`](https://docs.yummybait.finance/signals/versioning/), and
[`signals/webhooks/`](https://docs.yummybait.finance/signals/webhooks/) if you ever move off
polling.

## Polling (do this each cycle)

Build the request body from config + the persisted cursor, then POST it. Requires `YBT_API_URL`
and `YBT_SIGNALS_KEY` in your environment (the user sources `.env`).

```bash
# The API returns the cursor as a STRING and requires it sent back as a string — send it with
# --arg (not --argjson, which would coerce a numeric-looking cursor to a number → 400). Missing
# or "null" state means "no cursor yet" → send JSON null.
CURSOR=$(cat .state/cursor 2>/dev/null || true)
BODY=$(jq -n \
  --arg cursor "$CURSOR" \
  --slurpfile wallets config/wallets.json \
  --slurpfile rules config/rules.json \
  '{cursor: (if ($cursor == "" or $cursor == "null") then null else $cursor end),
    wallets: $wallets[0], rules: $rules[0]}')

RESP=$(curl -s -X POST "$YBT_API_URL/v1/signals" \
  -H "Authorization: Bearer $YBT_SIGNALS_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY")

# Persist the advanced cursor ONLY if the poll returned one — never clobber a good cursor with
# "null" when the poll errored (a 4xx/5xx body has no .cursor).
NEW=$(echo "$RESP" | jq -r '.cursor // empty')
[ -n "$NEW" ] && { mkdir -p .state && printf '%s' "$NEW" > .state/cursor; }
echo "$RESP" | jq '{fires, rule_errors}'
```

- Send `?dry_run=1` (append to the URL) to *explain* rules without firing or advancing state —
  useful right after editing `config/rules.json`.
- Each `fires[i]` has `rule`, `severity`, `note`, `position_id`, `chain_id`, `token_id`.
- The **cursor is an opaque string** — persist and resend it verbatim; never cast it to a number.

## Translating strategy → rules

1. Read the intent in `STRATEGY.md`.
2. For each thing the user cares about, find the metric(s) that express it — see
   **[references/metrics-catalog.md](references/metrics-catalog.md)** (the live, rule-usable
   surface with human meanings + a phrase→expression table). The full catalog, if you need more
   context, is the public docs at <https://docs.yummybait.finance/reference/metrics-catalog/>.
3. Write or adjust `config/rules.json` (Read, then Edit/Write). You send it on the next poll —
   edits tune *future* detection, not fires you've already pulled.
4. Keep it **valid JSON** (an array of rule objects) and reference only the **live** metric
   surface — see the reference. A bad `when` becomes a `rule_error` and is skipped.

Rule shape:

```json
{ "name": "drifted_and_staying", "when": "!in_range", "for": "30m", "cooldown": "1h", "severity": "warn", "note": "Out of range and not snapping back" }
```

- `for` makes a condition hold continuously before firing (good for "and stays there").
- `cooldown` suppresses re-fires for a while after one fires.
- Durations: `s` / `m` / `h` / `d`, or an integer of seconds.

## Off-limits when editing config

- **Never loosen `config/agent-config.json`** (USD cap, slippage). You may
  *tighten* it if the strategy is more conservative — never widen it. (The CDP Wallet Policy
  enforces the real ceiling regardless, but treat `agent-config.json` as the user's.)
- **Don't add addresses to `config/wallets.json`** — surface a suggestion in your report instead.

## Interpreting a position's live state

To learn a position's details (token pair, range, liquidity) when deciding, call the
uniswap-tx-builder MCP `build_close` with `simulate: true` — its response includes the read
position.
