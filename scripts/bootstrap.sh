\
#!/usr/bin/env bash
set -euo pipefail

ROLE=""
CONSUL_SERVER=""
THIS_IP=""
HUB_PORT="auto"
AGENT_PORT="auto"
ALLOW_LOW_PORTS="false"
ENABLE_DOCKER="auto"
CONSUL_SYNC="true"

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/bootstrap.sh --role hub|host|hub+host [options]

Required:
  --role hub|host|hub+host
  --this-ip <ip>                 This machine's LAN IP (used for Consul advertise + nice URLs)

Host-only required:
  --consul-server <ip>           Consul server IP (hub's IP)

Ports:
  --hub-port auto|<port>         Hub UI port (default: auto)
  --agent-port auto|<port>       Agent UI port (default: auto)
  --allow-low-ports true|false   If true, grants cap_net_bind_service so svcindex can bind <1024 (default: false)

Discovery:
  --docker auto|true|false       Enable Docker label discovery for agent role (default: auto)
  --consul-sync true|false       Register services to local Consul agent (default: true)

Examples:
  # Install hub (Consul server + hub UI). Ports auto-selected.
  sudo ./scripts/bootstrap.sh --role hub --this-ip 192.168.1.187

  # Install host (Consul agent + local UI)
  sudo ./scripts/bootstrap.sh --role host --consul-server 192.168.1.187 --this-ip 192.168.1.50

  # Hub also runs as host (hub UI + local UI + docker discovery)
  sudo ./scripts/bootstrap.sh --role hub+host --this-ip 192.168.1.187 --docker auto
EOF
}

# ---------- helpers ----------

is_port_in_use() {
  local port="$1"
  ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E "(:${port}$)|(:${port},)" -q
}

pick_port() {
  local prefer=("$@")
  local p
  for p in "${prefer[@]}"; do
    if ! is_port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

parse_port_arg() {
  local v="$1"
  if [[ "$v" == "auto" ]]; then
    echo "auto"
    return 0
  fi
  if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 && v <= 65535 )); then
    echo "$v"
    return 0
  fi
  echo "invalid"
  return 0
}

ensure_low_port_capability() {
  local python_bin="/opt/svcindex/.venv/bin/python3"
  if [[ "$ALLOW_LOW_PORTS" != "true" ]]; then
    return 0
  fi
  if [[ ! -x "$python_bin" ]]; then
    echo "[!] python3 venv binary not found at $python_bin (capability not set)"
    return 0
  fi
  echo "[*] Enabling cap_net_bind_service on $python_bin"
  apt-get update -y
  apt-get install -y libcap2-bin
  setcap 'cap_net_bind_service=+ep' "$python_bin" || true
}

# ---------- arg parsing ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2;;
    --consul-server) CONSUL_SERVER="${2:-}"; shift 2;;
    --this-ip) THIS_IP="${2:-}"; shift 2;;
    --hub-port) HUB_PORT="${2:-}"; shift 2;;
    --agent-port) AGENT_PORT="${2:-}"; shift 2;;
    --allow-low-ports) ALLOW_LOW_PORTS="${2:-}"; shift 2;;
    --docker) ENABLE_DOCKER="${2:-}"; shift 2;;
    --consul-sync) CONSUL_SYNC="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$ROLE" ]]; then echo "Missing --role"; usage; exit 1; fi
if [[ -z "$THIS_IP" ]]; then echo "Missing --this-ip"; usage; exit 1; fi

case "$ROLE" in
  hub|host|hub+host) ;;
  *) echo "Invalid --role: $ROLE"; usage; exit 1;;
esac

if [[ "$ROLE" == "host" ]] && [[ -z "$CONSUL_SERVER" ]]; then
  echo "Missing --consul-server for role=host"
  usage
  exit 1
fi

# Validate port args
HUB_PORT="$(parse_port_arg "$HUB_PORT")"
AGENT_PORT="$(parse_port_arg "$AGENT_PORT")"
if [[ "$HUB_PORT" == "invalid" || "$AGENT_PORT" == "invalid" ]]; then
  echo "Invalid port arg. Use auto or a number 1..65535"
  exit 1
fi

# Default preference lists (avoid common ports by default; user can override)
HUB_PREF=(8099 8090 18080 10080 8888 12000)
AGENT_PREF=(8098 8091 18081 10081 8889 12001)

# Auto-select ports if requested and role includes those services
if [[ "$ROLE" == "hub" || "$ROLE" == "hub+host" ]]; then
  if [[ "$HUB_PORT" == "auto" ]]; then
    HUB_PORT="$(pick_port "${HUB_PREF[@]}")" || { echo "Could not find a free hub port"; exit 1; }
  fi
fi
if [[ "$ROLE" == "host" || "$ROLE" == "hub+host" ]]; then
  if [[ "$AGENT_PORT" == "auto" ]]; then
    if [[ "$ROLE" == "hub+host" ]]; then
      # ensure agent port != hub port
      local_found=""
      for p in "${AGENT_PREF[@]}"; do
        if [[ "$p" == "$HUB_PORT" ]]; then continue; fi
        if ! is_port_in_use "$p"; then local_found="$p"; break; fi
      done
      if [[ -z "$local_found" ]]; then
        echo "Could not find a free agent port"
        exit 1
      fi
      AGENT_PORT="$local_found"
    else
      AGENT_PORT="$(pick_port "${AGENT_PREF[@]}")" || { echo "Could not find a free agent port"; exit 1; }
    fi
  fi
fi

echo "[*] Role: $ROLE"
echo "[*] This IP: $THIS_IP"

# Install Consul pieces
if [[ "$ROLE" == "hub" || "$ROLE" == "hub+host" ]]; then
  echo "[*] Installing Consul server (single node)..."
  ./scripts/install-consul-server.sh --advertise "$THIS_IP"
  CONSUL_SERVER="$THIS_IP"
fi

if [[ "$ROLE" == "host" ]]; then
  echo "[*] Installing Consul agent..."
  ./scripts/install-consul-agent.sh --server "$CONSUL_SERVER" --advertise "$THIS_IP"
fi

# Install svcindex pieces
if [[ "$ROLE" == "hub" || "$ROLE" == "hub+host" ]]; then
  echo "[*] Installing svcindex hub UI on port $HUB_PORT ..."
  ./scripts/install-svcindex.sh --role hub --consul-server "$CONSUL_SERVER" --port "$HUB_PORT"
fi

if [[ "$ROLE" == "host" || "$ROLE" == "hub+host" ]]; then
  echo "[*] Installing svcindex agent UI on port $AGENT_PORT ..."
  ./scripts/install-svcindex.sh --role host --consul-server "$CONSUL_SERVER" --port "$AGENT_PORT" --docker "$ENABLE_DOCKER" --consul-sync "$CONSUL_SYNC" --advertise "$THIS_IP"
fi

# Low ports capability (optional)
ensure_low_port_capability

echo
echo "[*] Done."
if [[ "$ROLE" == "hub" || "$ROLE" == "hub+host" ]]; then
  echo "    Hub UI:   http://${THIS_IP}:${HUB_PORT}/"
fi
if [[ "$ROLE" == "host" || "$ROLE" == "hub+host" ]]; then
  echo "    Host UI:  http://${THIS_IP}:${AGENT_PORT}/"
fi
echo "    Service defs: /etc/svcindex/services.d"
