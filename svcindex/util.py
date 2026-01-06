from __future__ import annotations

import os
import socket
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

def hostname() -> str:
    try:
        return socket.gethostname()
    except Exception:
        return "unknown-host"

def env_bool(name: str, default: bool=False) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "y", "on")

@dataclass
class Monitor:
    mode: str = "none"   # http | tcp | none
    target: Optional[str] = None
    interval_s: int = 30
    timeout_s: int = 2

@dataclass
class Service:
    name: str
    type: str = "other"  # docker | systemd | native | other
    url: str = ""
    description: str = ""
    tags: List[str] = field(default_factory=list)
    monitor: Monitor = field(default_factory=Monitor)
    # runtime
    status: str = "unknown"      # passing | failing | unmonitored | unknown
    last_checked: float = 0.0
    latency_ms: Optional[int] = None
    detail: str = ""

def now_ts() -> float:
    return time.time()
