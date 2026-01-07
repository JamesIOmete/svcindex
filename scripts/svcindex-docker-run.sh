#!/usr/bin/env bash
set -euo pipefail

NAME=""
IMAGE=""
PUBLISHES=()
UI_PORT=""
HEALTH_PATH="/"
EXPECT_STATUS="200"
DESCRIPTION=""
PUBLIC_HOST=""
REMOVE_EXISTING=false
DRY_RUN=false
EXTRAS=()

usage() {
  cat <<'EOF'
Usage:
  ./scripts/svcindex-docker-run.sh --name NAME --image IMAGE[:TAG] \
    --publish HOSTPORT:CONTAINERPORT [--publish HOSTPORT:CONTAINERPORT ...] \
    --ui-port HOSTPORT [options]

Required:
  --name NAME                       Container name (used for Docker name and svcindex metadata)
  --image IMAGE[:TAG]               Image to run (tag optional)
  --publish HOSTPORT:CONTAINERPORT  Port mapping, repeatable
  --ui-port HOSTPORT                Host port users browse (must match one published)

Optional:
  --health-path PATH                HTTP path for health checks (default: /)
  --expect-status CODE              Expected HTTP status (default: 200)
  --description TEXT                Human-friendly description (default: NAME)
  --public-host HOST_OR_IP          Public host/IP used in svcindex.url (default: first non-loopback IP)
  --remove-existing                 Remove existing container before run
  --extra "ARG"                     Extra docker run argument (repeatable, e.g. "-e TZ=UTC" or "--network net")
  --dry-run                         Print docker command instead of executing
  --help                            Show this message

Examples:
  # Launch intercept with svcindex labels and monitoring
  ./scripts/svcindex-docker-run.sh \
    --name intercept \
    --image intercept:latest \
    --publish 5050:5050 --publish 5000:5000 \
    --ui-port 5050 \
    --health-path /status \
    --description "Intercept // Signal Intelligence" \
    --remove-existing

  # Dry run to inspect the docker command
  ./scripts/svcindex-docker-run.sh --name demo --image nginx:alpine \
    --publish 8080:80 --ui-port 8080 --dry-run

  # Pass extra docker args (-e, -v, --network, etc.)
  ./scripts/svcindex-docker-run.sh --name grafana --image grafana/grafana \
    --publish 3000:3000 --ui-port 3000 \
    --extra "-e GF_SECURITY_ADMIN_PASSWORD=change_me" \
    --extra "-v /srv/grafana:/var/lib/grafana"
EOF
}

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      NAME="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --publish)
      PUBLISHES+=("${2:-}")
      shift 2
      ;;
    --ui-port)
      UI_PORT="${2:-}"
      shift 2
      ;;
    --health-path)
      HEALTH_PATH="${2:-}"
      shift 2
      ;;
    --expect-status)
      EXPECT_STATUS="${2:-}"
      shift 2
      ;;
    --description)
      DESCRIPTION="${2:-}"
      shift 2
      ;;
    --public-host)
      PUBLIC_HOST="${2:-}"
      shift 2
      ;;
    --remove-existing)
      REMOVE_EXISTING=true
      shift 1
      ;;
    --extra)
      EXTRAS+=("${2:-}")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift 1
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Missing required --name" >&2
  usage
  exit 1
fi
if [[ -z "$IMAGE" ]]; then
  echo "Missing required --image" >&2
  usage
  exit 1
fi
if [[ ${#PUBLISHES[@]} -eq 0 ]]; then
  echo "At least one --publish mapping is required" >&2
  usage
  exit 1
fi
if [[ -z "$UI_PORT" ]]; then
  echo "Missing required --ui-port" >&2
  usage
  exit 1
fi

if [[ -z "$DESCRIPTION" ]]; then
  DESCRIPTION="$NAME"
fi

if [[ -z "$PUBLIC_HOST" ]]; then
  AUTO_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$AUTO_HOST" ]]; then
    PUBLIC_HOST="$AUTO_HOST"
  else
    PUBLIC_HOST="127.0.0.1"
  fi
fi

if [[ -z "$HEALTH_PATH" ]]; then
  HEALTH_PATH="/"
else
  HEALTH_PATH="/${HEALTH_PATH#/}"
fi

URL="http://${PUBLIC_HOST}:${UI_PORT}/"
MON_TARGET="http://127.0.0.1:${UI_PORT}${HEALTH_PATH}"

if [[ "$REMOVE_EXISTING" == true ]]; then
  if [[ "$DRY_RUN" == true ]]; then
    printf 'dry-run: docker rm -f %q\n' "$NAME"
  else
    docker rm -f "$NAME" >/dev/null 2>&1 || true
  fi
fi

docker_args=(
  "docker"
  "run"
  "-d"
  "--name" "$NAME"
  "--restart" "unless-stopped"
)

for pub in "${PUBLISHES[@]}"; do
  docker_args+=("-p" "$pub")
done

for extra in "${EXTRAS[@]}"; do
  if [[ -n "$extra" ]]; then
    read -r -a extra_parts <<< "$extra"
    for part in "${extra_parts[@]}"; do
      docker_args+=("$part")
    done
  fi
done

docker_args+=(
  --label "svcindex.enable=true"
  --label "svcindex.type=docker"
  --label "svcindex.description=${DESCRIPTION}"
  --label "svcindex.url=${URL}"
  --label "svcindex.monitor.mode=http"
  --label "svcindex.monitor.target=${MON_TARGET}"
  --label "svcindex.monitor.expect_status=${EXPECT_STATUS}"
  "$IMAGE"
)

if [[ "$DRY_RUN" == true ]]; then
  printf 'dry-run: '
  printf '%q ' "${docker_args[@]}"
  printf '\n'
else
  "${docker_args[@]}"
fi

echo
if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] Ready to start container '$NAME'"
else
  echo "Container '$NAME' started"
fi
echo "  URL:        ${URL}"
echo "  Monitor:    ${MON_TARGET}"
echo "  Expecting:  HTTP ${EXPECT_STATUS}"
