# Ports

- svcindex uses port 8080 by default when installed directly via `install-svcindex.sh`.
- The unified `bootstrap.sh` defaults to **auto** selecting ports from a safe list to avoid collisions.

## Using port 80 (no reverse proxy)

Binding to ports <1024 normally requires root.
If you pass `--allow-low-ports true` to `bootstrap.sh`, it will install `libcap2-bin`
and apply:

```bash
setcap 'cap_net_bind_service=+ep' /opt/svcindex/.venv/bin/python3
```

This allows the `svcindex` systemd service (running as user `svcindex`) to bind to port 80.
