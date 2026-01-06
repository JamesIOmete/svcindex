from __future__ import annotations

import json
import subprocess
from typing import List, Dict, Any, Optional

from .util import Service, Monitor

LABEL_PREFIX = "svcindex."

def _run(cmd: List[str]) -> str:
    return subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8", errors="replace")

def docker_available() -> bool:
    try:
        _run(["docker", "version"])
        return True
    except Exception:
        return False

def discover_from_labels() -> List[Service]:
    """Opt-in discovery: only containers with label svcindex.enable=true are included."""
    if not docker_available():
        return []

    try:
        ids = _run(["docker", "ps", "-q"]).strip().splitlines()
    except Exception:
        return []
    services: List[Service] = []
    for cid in ids:
        try:
            raw = _run(["docker", "inspect", cid])
            info = json.loads(raw)[0]
            labels = (info.get("Config") or {}).get("Labels") or {}
            if str(labels.get("svcindex.enable", "false")).strip().lower() not in ("1", "true", "yes", "y", "on"):
                continue

            name = labels.get("svcindex.name") or (info.get("Name") or "").lstrip("/") or cid[:12]
            url = labels.get("svcindex.url") or ""
            desc = labels.get("svcindex.description") or ""

            mon_mode = (labels.get("svcindex.monitor.mode") or "none").strip().lower()
            mon_target = labels.get("svcindex.monitor.target")

            svc = Service(
                name=str(name),
                type=(labels.get("svcindex.type") or "docker").strip().lower(),
                url=str(url),
                description=str(desc),
                tags=_split_tags(labels.get("svcindex.tags")),
                monitor=Monitor(mode=mon_mode, target=mon_target),
            )
            services.append(svc)
        except Exception:
            continue

    return services

def _split_tags(v: Optional[str]) -> List[str]:
    if not v:
        return []
    parts = [p.strip() for p in v.split(",")]
    return [p for p in parts if p]
