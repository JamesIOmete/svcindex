# svcindex (Service Index for homelabs)

`svcindex` gives you:

- **Per-host landing page**: each machine can serve a local "what's running here" dashboard.
- **Optional hub landing page**: one machine can show an aggregated view across hosts.
- **Mixed environments**: supports **Docker**, **systemd/native apps**, or anything else you can describe via a small YAML file.
- **Monitoring profiles**: HTTP checks, TCP checks, or explicitly **unmonitored** ("no monitoring at this time").

This repo is designed to be:
- Easy to script-install on Raspberry Pi OS/Debian/Ubuntu
- Able to add **Hub UI HA later** (keepalived/VRRP) with no app rewrite (Hub UI is stateless).

## Quickstart (unified bootstrap)

### Hub (catalog + hub UI)
On your designated hub machine:

```bash
sudo ./scripts/bootstrap.sh --role hub --this-ip 192.168.1.187
```

This installs:
- Consul server (single node, non-HA for now)
- svcindex-hub (global view)

Open: `http://<hub>:<hub-port>/`

### Host (catalog client + local UI)
On each host:

```bash
sudo ./scripts/bootstrap.sh --role host --consul-server 192.168.1.187 --this-ip 192.168.1.50
```

Open: `http://<host>:<agent-port>/`

### Hub + Host (same machine does both)
If you want the hub machine to also have a local "what's running here" page:

```bash
sudo ./scripts/bootstrap.sh --role hub+host --this-ip 192.168.1.187
```

## Ports: auto vs manual

By default, bootstrap uses **auto port selection** to avoid collisions.
You can override:

- `--hub-port 8099`
- `--agent-port 8098`

If you want to bind to port 80 on a machine without an existing web server, set:
- `--hub-port 80` and/or `--agent-port 80`

Note: ports <1024 require special privileges. Bootstrap can grant the Python interpreter the
`cap_net_bind_service` capability when you pass `--allow-low-ports true`.

## Service definitions

On each host, add YAML files here:

```bash
sudo mkdir -p /etc/svcindex/services.d
sudo cp examples/services.d/*.yaml /etc/svcindex/services.d/
sudo systemctl restart svcindex-agent
```

## Docker discovery (opt-in)

Docker containers are only listed if they include `svcindex.enable=true` labels.
See `docs/docker-labels.md`.

## Running Docker containers with svcindex labels

When the agent runs with `--docker`, svcindex auto-discovers containers that opt-in via labels. Use the helper script to launch images with the right metadata baked in:

```bash
./scripts/svcindex-docker-run.sh --name intercept --image intercept:latest \
  --publish 5050:5050 --publish 5000:5000 --ui-port 5050 --health-path /status \
  --description "Intercept // Signal Intelligence" --remove-existing
```

- Pick a health-style endpoint (e.g., `/status`). If the app lacks one, fall back to `/`.
- Dry run the command before launching:

  ```bash
  ./scripts/svcindex-docker-run.sh --name demo --image nginx:alpine \
    --publish 8080:80 --ui-port 8080 --dry-run
  ```

- Pass extra docker args with `--extra` (repeat as needed):

  ```bash
  ./scripts/svcindex-docker-run.sh --name grafana --image grafana/grafana \
    --publish 3000:3000 --ui-port 3000 \
    --extra "-e GF_SECURITY_ADMIN_PASSWORD=change_me" \
    --extra "-v /srv/grafana:/var/lib/grafana"
  ```

## Repo layout

- `svcindex/` Python app (agent + hub)
- `scripts/` installation scripts (unified bootstrap + Consul + svcindex)
- `examples/` sample service definitions + docker label examples
- `docs/` design + HA notes
