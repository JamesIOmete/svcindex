#!/usr/bin/env bash
set -euo pipefail

ROLE=""
CONSUL_SERVER=""
PORT="8080"
ENABLE_DOCKER="auto"
CONSUL_SYNC="true"
ADVERTISE=""

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/install-svcindex.sh --role host|hub --consul-server <ip_or_http_addr> [options]

Options:
  --role host|hub              Install svcindex-agent or svcindex-hub
  --consul-server <addr>       Consul server IP (e.g., 192.168.1.10) or full http URL (e.g., http://192.168.1.10:8500)
  --port <port>                Listen port (default: 8080)
  --docker auto|true|false     Enable Docker label discovery (default: auto)
  --consul-sync true|false     Agent: register services to local Consul agent (default: true)
  --advertise <ip>             Agent: address to advertise into Consul registrations (optional)

Notes:
  - This installs svcindex into /opt/svcindex with a Python venv and a systemd unit.
  - Requires python3 + python3-venv.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="${2:-}"; shift 2;;
    --consul-server) CONSUL_SERVER="${2:-}"; shift 2;;
    --port) PORT="${2:-}"; shift 2;;
    --docker) ENABLE_DOCKER="${2:-}"; shift 2;;
    --consul-sync) CONSUL_SYNC="${2:-}"; shift 2;;
    --advertise) ADVERTISE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$ROLE" ]]; then echo "Missing --role"; usage; exit 1; fi
if [[ -z "$CONSUL_SERVER" ]]; then echo "Missing --consul-server"; usage; exit 1; fi

if [[ "$CONSUL_SERVER" =~ ^http ]]; then
  CONSUL_HTTP_ADDR="$CONSUL_SERVER"
else
  CONSUL_HTTP_ADDR="http://${CONSUL_SERVER}:8500"
fi

echo "[*] Installing dependencies..."
apt-get update -y
apt-get install -y python3 python3-venv python3-pip curl

echo "[*] Creating svcindex user (if needed)..."
if ! id svcindex >/dev/null 2>&1; then
  useradd --system --home /opt/svcindex --shell /usr/sbin/nologin svcindex
fi

echo "[*] Installing code to /opt/svcindex..."
mkdir -p /opt/svcindex
rsync -a --delete ./ /opt/svcindex/
chown -R svcindex:svcindex /opt/svcindex

echo "[*] Creating venv..."
runuser -u svcindex -- /usr/bin/python3 -m venv /opt/svcindex/.venv
runuser -u svcindex -- /opt/svcindex/.venv/bin/pip install --upgrade pip setuptools wheel
runuser -u svcindex -- /opt/svcindex/.venv/bin/pip install -e /opt/svcindex

echo "[*] Creating config dirs..."
mkdir -p /etc/svcindex/services.d
chown -R svcindex:svcindex /etc/svcindex

echo "[*] Installing systemd unit..."
if [[ "$ROLE" == "host" ]]; then
  UNIT="svcindex-agent"
  cat >/etc/systemd/system/${UNIT}.service <<EOF
[Unit]
Description=svcindex agent (local service index)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=svcindex
Group=svcindex
Environment=CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR}
WorkingDirectory=/opt/svcindex
ExecStart=/opt/svcindex/.venv/bin/svcindex --mode agent --listen 0.0.0.0 --port ${PORT} --services-dir /etc/svcindex/services.d \
  $( [[ "$ENABLE_DOCKER" == "true" ]] && echo "--docker" ) \
  $( [[ "$ENABLE_DOCKER" == "auto" && -S /var/run/docker.sock ]] && echo "--docker" ) \
  $( [[ "$CONSUL_SYNC" == "true" ]] && echo "--consul-sync" ) \
  $( [[ -n "$ADVERTISE" ]] && echo "--advertise ${ADVERTISE}" )
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
elif [[ "$ROLE" == "hub" ]]; then
  UNIT="svcindex-hub"
  cat >/etc/systemd/system/${UNIT}.service <<EOF
[Unit]
Description=svcindex hub (global service index)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=svcindex
Group=svcindex
Environment=CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR}
WorkingDirectory=/opt/svcindex
ExecStart=/opt/svcindex/.venv/bin/svcindex --mode hub --listen 0.0.0.0 --port ${PORT} --consul-server ${CONSUL_HTTP_ADDR}
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
else
  echo "Invalid --role: $ROLE"
  exit 1
fi

systemctl daemon-reload
systemctl enable --now ${UNIT}.service

echo "[*] Done."
echo "    - Role: $ROLE"
echo "    - URL:  http://<this-host>:${PORT}/"
echo "    - Service defs: /etc/svcindex/services.d"
