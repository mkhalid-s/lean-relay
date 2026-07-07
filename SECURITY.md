# Security Policy

apx runs local proxies and can observe LLM request/response traffic.
Treat its logs and dashboards as sensitive.

## Reporting

Please report security issues privately to the project maintainer rather than
opening a public issue with sensitive details.

## Operational Notes

- Bind to `127.0.0.1` unless you intentionally need remote access. The apx
  dashboard at `http://127.0.0.1:8787/` exposes request history and log tails;
  do not expose the gateway port to a public network.
- Review any third-party dependencies before installing them.
- Do not publish `~/.local/state/apx`, `~/.pxpipe`, `~/.headroom`, or
  `~/.squeezr` logs/caches.
- Do not commit API keys or provider tokens.
