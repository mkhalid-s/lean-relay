# LeanRelay in Linux and Devcontainers

LeanRelay (`apx`) supports two container topologies. Choose one deliberately; the correct Claude base URL depends on where the gateway runs.

## A. apx runs inside the same devcontainer

Copy [`examples/devcontainer/devcontainer.json`](../examples/devcontainer/devcontainer.json) into your project or merge its fields into the existing configuration.

The important settings are:

```json
{
  "containerEnv": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:8787",
    "APX_SERVICE_BACKEND": "nohup"
  },
  "postStartCommand": "apx start"
}
```

Use `apx run` instead when the container runtime or Compose should own the foreground process. Persist config/share/state volumes, but do not persist `$XDG_RUNTIME_DIR`; PID and lock files are intentionally ephemeral.

## B. Claude runs in a devcontainer and apx runs on macOS

Run apx normally on the host, then configure the container:

```json
{
  "containerEnv": {
    "ANTHROPIC_BASE_URL": "http://host.docker.internal:8787"
  }
}
```

Docker Desktop provides `host.docker.internal`. Native Linux Docker may require `--add-host=host.docker.internal:host-gateway`, and a host service bound only to loopback may still be unreachable. Do not broaden the gateway bind address without dashboard authentication and a network exposure review.

## Service backends

```text
macOS                         launchd
Linux with systemd --user     systemd
Linux/devcontainer otherwise  nohup
Container foreground          apx run
```

Override selection with `APX_SERVICE_BACKEND=launchd|systemd|nohup` or `--service-backend` during installation.

Noninteractive installs should also set `APX_CLIENT_TOPOLOGY=local` for the
same-container topology or `APX_CLIENT_TOPOLOGY=docker-host` when Claude runs
in Docker Desktop and apx runs on the host. Interactive installs prompt for
this choice.

## Claude endpoint commands

```bash
apx claude set local         # same host/container: 127.0.0.1
apx claude set docker-host   # Docker Desktop host.docker.internal
apx claude set https://...   # explicit URL
apx claude sync
apx claude clear
```

## Troubleshooting

```bash
apx status
curl -fsS http://127.0.0.1:8787/livez
apx logs supervisor
apx restart
```

On Linux, verify `systemctl --user show-environment` before explicitly choosing systemd. apx automatically falls back to nohup when no live user manager exists and never enables lingering automatically.
