from __future__ import annotations

import glob
import os
from typing import List, Dict, Any

import yaml

from .util import Service, Monitor

def load_services_from_dir(services_dir: str) -> List[Service]:
    services: List[Service] = []
    if not services_dir or not os.path.isdir(services_dir):
        return services

    for path in sorted(glob.glob(os.path.join(services_dir, "*.yml")) + glob.glob(os.path.join(services_dir, "*.yaml"))):
        with open(path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}
        services.append(service_from_dict(data, source_path=path))
    return services

def service_from_dict(d: Dict[str, Any], source_path: str = "") -> Service:
    name = str(d.get("name", "")).strip()
    if not name:
        raise ValueError(f"Service definition missing 'name' ({source_path})")

    m = d.get("monitor") or {}
    monitor = Monitor(
        mode=str(m.get("mode", "none")).strip().lower(),
        target=(None if m.get("target") in (None, "") else str(m.get("target"))),
        interval_s=int(m.get("interval_s", 30)),
        timeout_s=int(m.get("timeout_s", 2)),
    )

    tags = d.get("tags") or []
    if isinstance(tags, str):
        tags = [tags]
    tags = [str(t).strip() for t in tags if str(t).strip()]

    return Service(
        name=name,
        type=str(d.get("type", "other")).strip().lower(),
        url=str(d.get("url", "")).strip(),
        description=str(d.get("description", "")).strip(),
        tags=tags,
        monitor=monitor,
    )
