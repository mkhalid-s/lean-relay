# Security Policy

AI Proxy Stack runs local proxies and can observe LLM request/response traffic.
Treat its logs and dashboards as sensitive.

## Reporting

Please report security issues privately to the project maintainer rather than
opening a public issue with sensitive details.

## Operational Notes

- Bind to `127.0.0.1` unless you intentionally need remote access.
- Review any third-party dependencies before installing them.
- Do not publish `~/.local/state/ai-proxy-stack`, `~/.pxpipe`, `~/.headroom`, or `~/.squeezr` logs/caches.
- Do not commit API keys or provider tokens.
