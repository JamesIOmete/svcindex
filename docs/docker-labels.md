# Docker labels (opt-in discovery)

svcindex only lists Docker containers if they explicitly opt-in via labels.

Example (docker compose):

```yaml
services:
  grafana:
    image: grafana/grafana
    labels:
      - "svcindex.enable=true"
      - "svcindex.name=grafana"
      - "svcindex.type=docker"
      - "svcindex.url=http://grafana.lan/"
      - "svcindex.description=Dashboards"
      - "svcindex.monitor.mode=http"
      - "svcindex.monitor.target=http://grafana:3000/api/health"
```

Supported labels:
- svcindex.enable=true|false
- svcindex.name
- svcindex.type (docker)
- svcindex.url
- svcindex.description
- svcindex.monitor.mode (http|tcp|none)
- svcindex.monitor.target (URL for http; host:port for tcp)
