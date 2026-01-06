#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper: install Consul agent + svcindex-agent

SERVER="${1:-}"
ADVERTISE="${2:-}"

if [[ -z "$SERVER" || -z "$ADVERTISE" ]]; then
  echo "Usage: sudo ./scripts/bootstrap-host.sh <consul_server_ip> <this_host_ip>"
  exit 1
fi

./scripts/install-consul-agent.sh --server "$SERVER" --advertise "$ADVERTISE"
./scripts/install-svcindex.sh --role host --consul-server "$SERVER" --advertise "$ADVERTISE" --docker auto --consul-sync true
