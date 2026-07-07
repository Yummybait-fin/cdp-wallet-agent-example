# Exposes Coinbase's stdio `cdp mcp` over HTTP/SSE via mcp-proxy, so a local
# agent can reach it as a docker-compose service. Keys are passed at run time.
#
# mcp-proxy flags vary by version — validate against the installed version.

FROM node:22-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends pipx \
  && rm -rf /var/lib/apt/lists/* \
  && pipx install mcp-proxy
ENV PATH="/root/.local/bin:${PATH}"

# Pin an exact version for production (SECURITY.md).
RUN npm install -g @coinbase/cdp-cli@latest

EXPOSE 8101
# SSE endpoint on :8101 → agent connects to http://localhost:8101/sse
#
# The entrypoint first configures the cdp CLI's "live" env from the CDP_* vars
# (cdp mcp needs a configured environment; it does not auto-read the env vars),
# then launches mcp-proxy 0.12.x with --host/--port (the old --sse-host/
# --sse-port aliases don't bind — proxy fell back to 127.0.0.1:<random>).
# --host 0.0.0.0 makes the published port reachable; --pass-environment forwards
# the CDP_* vars to the spawned `cdp mcp` child.
COPY cdp-mcp-entrypoint.sh /usr/local/bin/cdp-mcp-entrypoint.sh
RUN chmod +x /usr/local/bin/cdp-mcp-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/cdp-mcp-entrypoint.sh"]
