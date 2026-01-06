#!/usr/bin/env bash
set -euo pipefail

CONSUL_VERSION="${CONSUL_VERSION:-1.17.1}"
ADVERTISE=""
DATA_DIR="/opt/consul"
CONFIG_DIR="/etc/consul.d"
BIND="0.0.0.0"

usage() {
  cat <<'EOF'
Usage:
  sudo ./scripts/install-consul-server.sh --advertise <ip> [--version <v>]

Notes:
  - This installs a single Consul server (non-HA) suitable for v0.1.
  - Later you can expand to 3 servers by updating server config + adding retry_join peers.
  - No TLS/mTLS in this pass.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --advertise) ADVERTISE="${2:-}"; shift 2;;
    --version) CONSUL_VERSION="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$ADVERTISE" ]]; then echo "Missing --advertise"; usage; exit 1; fi

apt-get update -y
apt-get install -y unzip curl

if ! id consul >/dev/null 2>&1; then
  useradd --system --home "${DATA_DIR}" --shell /usr/sbin/nologin consul
fi

mkdir -p /tmp/consul-install
cd /tmp/consul-install

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) CONSUL_ARCH="amd64" ;;
  aarch64|arm64) CONSUL_ARCH="arm64" ;;
  armv7l) CONSUL_ARCH="arm" ;;
  *) echo "Unsupported arch: $ARCH"; exit 1 ;;
esac

echo "[*] Downloading Consul ${CONSUL_VERSION}..."
curl -fsSLo consul.zip "https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_${CONSUL_ARCH}.zip"
unzip -o consul.zip
install -m 0755 consul /usr/local/bin/consul

mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"
chown -R consul:consul "${DATA_DIR}" "${CONFIG_DIR}"

cat >"${CONFIG_DIR}/consul.hcl" <<EOF
data_dir = "${DATA_DIR}"
server = true
bootstrap_expect = 1

bind_addr = "${BIND}"
advertise_addr = "${ADVERTISE}"

client_addr = "0.0.0.0"
ui_config {
  enabled = true
}

ports {
  grpc = -1
}

# NOTE: ACL/TLS not enabled in v0.1. Add later if desired.
EOF

cat >/etc/systemd/system/consul.service <<'EOF'
[Unit]
Description=Consul Server
Wants=network-online.target
After=network-online.target

[Service]
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now consul

echo "[*] Consul server installed."
echo "    UI: http://${ADVERTISE}:8500/ui/"
