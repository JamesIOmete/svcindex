# Service Definition Schema

Place YAML files in:
- `/etc/svcindex/services.d/*.yaml`

Minimal example:

```yaml
name: grafana
type: native            # docker | systemd | native | other
url: http://host.lan:3000
description: Dashboards
monitor:
  mode: http            # http | tcp | none
  target: http://host.lan:3000/api/health
  interval_s: 30
  timeout_s: 2
tags:
  - dashboards
  - metrics
```

Notes:
- `monitor.mode: none` is the explicit "no monitoring at this time" label.
- For TCP checks, `monitor.target` should be `host:port` (e.g. `127.0.0.1:5432`).
