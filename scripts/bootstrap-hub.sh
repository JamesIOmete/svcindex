#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper: install Consul server + svcindex-hub

ADVERTISE="${1:-}"
if [[ -z "$ADVERTISE" ]]; then
  echo "Usage: sudo ./scripts/bootstrap-hub.sh <this_hub_ip>"
  exit 1
fi

./scripts/install-consul-server.sh --advertise "$ADVERTISE"
./scripts/install-svcindex.sh --role hub --consul-server "$ADVERTISE"
