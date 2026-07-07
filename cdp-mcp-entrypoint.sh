#!/bin/sh
# Configure the cdp CLI's "live" environment from the CDP_* env vars, then hand
# off to mcp-proxy. Needed because `cdp mcp` reads a configured environment
# (keyring/config), it does NOT auto-read CDP_API_KEY_ID/_SECRET/_WALLET_SECRET.
# Secrets are written with --plaintext (a container has no OS keychain) to the
# ephemeral container FS — nothing is baked into the image.
set -e

if [ -n "$CDP_API_KEY_ID" ] && [ -n "$CDP_API_KEY_SECRET" ]; then
  cdp env live --key-id="$CDP_API_KEY_ID" --key-secret="$CDP_API_KEY_SECRET" --plaintext >/dev/null 2>&1 \
    && echo "cdp: configured API key for 'live'" \
    || echo "cdp: WARNING failed to configure API key" >&2
  if [ -n "$CDP_WALLET_SECRET" ]; then
    cdp env live --wallet-secret="$CDP_WALLET_SECRET" --plaintext >/dev/null 2>&1 \
      && echo "cdp: configured wallet secret for 'live'" \
      || echo "cdp: WARNING failed to configure wallet secret" >&2
  fi
else
  echo "cdp: WARNING CDP_API_KEY_ID/_SECRET not set — server will be unauthenticated" >&2
fi

exec mcp-proxy --pass-environment --host 0.0.0.0 --port 8101 cdp mcp
