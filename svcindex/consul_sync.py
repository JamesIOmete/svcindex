from __future__ import annotations

import socket
from typing import Dict, List, Optional, Tuple

from .util import Service
from .consul_client import get_json, register_service, deregister_service, consul_addr

def _local_ip_guess() -> str:
    # Best-effort: doesn't need to be perfect; user can override with --advertise
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def sync_services_to_local_consul(
    services: List[Service],
    node: str,
    advertise_addr: Optional[str] = None,
    consul_base: Optional[str] = None,
) -> Tuple[int, int]:
    """Registers svcindex-known services to the local Consul agent.

    Returns: (registered_count, deregistered_count)
    """
    base = (consul_base or consul_addr()).rstrip("/")
    # If no local agent reachable, just skip gracefully.
    try:
        _ = get_json("/v1/agent/self", base=base)
    except Exception:
        return (0, 0)

    addr = advertise_addr or _local_ip_guess()
    wanted_ids: Dict[str, Dict] = {}
    for svc in services:
        # service_id should be stable per node+service
        service_id = f"{node}::{svc.name}"
        # tags include type and monitor mode for grouping
        tags = list(svc.tags or [])
        tags.append(f"type={svc.type}")
        tags.append(f"monitor={svc.monitor.mode}")
        tags.append(f"node={node}")

        # Attempt to parse url for address/port for "Service" fields; fall back to 0
        port = _guess_port(svc.url) or 0
        checks = _build_checks(svc, service_id)

        wanted_ids[service_id] = dict(
            service_id=service_id, name=svc.name, address=addr, port=port, tags=tags, checks=checks
        )

    # Current services
    try:
        current = get_json("/v1/agent/services", base=base) or {}
    except Exception:
        current = {}

    # Register/update wanted
    reg = 0
    for sid, info in wanted_ids.items():
        register_service(
            service_id=sid,
            name=info["name"],
            address=info["address"],
            port=info["port"],
            tags=info["tags"],
            checks=info["checks"],
        )
        reg += 1

    # Deregister stale ones with our node prefix
    dereg = 0
    for sid in list(current.keys()):
        if sid.startswith(f"{node}::") and sid not in wanted_ids:
            try:
                deregister_service(sid)
                dereg += 1
            except Exception:
                pass

    return (reg, dereg)

def _guess_port(url: str) -> Optional[int]:
    if not url:
        return None
    # very small parser
    if url.startswith("http://") or url.startswith("https://"):
        try:
            # split scheme://host:port/...
            rest = url.split("://", 1)[1]
            hostport = rest.split("/", 1)[0]
            if ":" in hostport:
                return int(hostport.rsplit(":", 1)[1])
            return 443 if url.startswith("https://") else 80
        except Exception:
            return None
    return None

def _build_checks(svc: Service, service_id: str) -> List[Dict]:
    mode = (svc.monitor.mode or "none").lower()
    if mode == "none":
        return []
    interval = f"{int(svc.monitor.interval_s)}s"
    timeout = f"{int(svc.monitor.timeout_s)}s"
    if mode == "http":
        if not svc.monitor.target:
            return []
        return [{
            "Name": f"svcindex http {service_id}",
            "HTTP": svc.monitor.target,
            "Interval": interval,
            "Timeout": timeout,
        }]
    if mode == "tcp":
        if not svc.monitor.target:
            return []
        return [{
            "Name": f"svcindex tcp {service_id}",
            "TCP": svc.monitor.target,
            "Interval": interval,
            "Timeout": timeout,
        }]
    return []
