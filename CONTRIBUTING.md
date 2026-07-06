# Contributing

Thanks for improving AI Proxy Stack.

## Development

Run these checks before sending changes:

```bash
bash -n install.sh
bash -n bin/ai-proxy-stack
./install.sh --check-only
```

Keep scripts portable:

- Do not commit user-specific absolute paths.
- Do not commit runtime logs, PID files, or generated LaunchAgent output.
- Keep dependency installation explicit and visible to the user.

## Security

Do not include API keys, provider tokens, local credentials, or private logs in
issues or pull requests.
