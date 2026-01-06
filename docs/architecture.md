# Architecture

Goals:
- Every host has a local landing page (works even if the hub is down).
- A hub landing page aggregates all hosts for convenience.
- Discovery supports: Docker, systemd/native apps, and anything described in YAML.
- Monitoring is configurable per service: http/tcp/none.
- Hub UI can later be made HA without rewriting the application.

Components:

## Per-host
- **svcindex-agent** (Python + systemd)
  - local UI on port 8080 by default
  - reads service definitions from `/etc/svcindex/services.d/*.yaml`
  - optional Docker label discovery (opt-in)
  - optional Consul registration

- **consul agent** (optional but recommended)
  - runs health checks and shares catalog to Consul servers

## Hub (single node for now)
- **svcindex-hub**
  - stateless UI that queries Consul HTTP API

- **consul server**
  - catalog source of truth
  - start with one server; scale to 3 later for HA

## HA later (no rewrite)
- Run a second HubUI instance and front with keepalived/VRRP to provide a stable `services.lan` virtual IP.
