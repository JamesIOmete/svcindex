from __future__ import annotations

import socket
import time
from typing import Tuple, Optional

import requests

from .util import Service, now_ts

def check_service(svc: Service) -> None:
    mode = (svc.monitor.mode or "none").lower()
    if mode == "none":
        svc.status = "unmonitored"
        svc.detail = "No monitoring configured"
        svc.latency_ms = None
        svc.last_checked = now_ts()
        return

    if mode == "http":
        if not svc.monitor.target:
            svc.status = "failing"
            svc.detail = "HTTP monitor missing target"
            svc.latency_ms = None
            svc.last_checked = now_ts()
            return
        _check_http(svc)
        return

    if mode == "tcp":
        if not svc.monitor.target:
            svc.status = "failing"
            svc.detail = "TCP monitor missing target"
            svc.latency_ms = None
            svc.last_checked = now_ts()
            return
        _check_tcp(svc)
        return

    svc.status = "unknown"
    svc.detail = f"Unknown monitor mode: {mode}"
    svc.latency_ms = None
    svc.last_checked = now_ts()

def _check_http(svc: Service) -> None:
    t0 = time.time()
    try:
        r = requests.get(svc.monitor.target, timeout=svc.monitor.timeout_s)
        dt = int((time.time() - t0) * 1000)
        svc.latency_ms = dt
        if 200 <= r.status_code < 400:
            svc.status = "passing"
            svc.detail = f"HTTP {r.status_code}"
        else:
            svc.status = "failing"
            svc.detail = f"HTTP {r.status_code}"
    except Exception as e:
        dt = int((time.time() - t0) * 1000)
        svc.latency_ms = dt
        svc.status = "failing"
        svc.detail = f"HTTP error: {type(e).__name__}"
    finally:
        svc.last_checked = now_ts()

def _check_tcp(svc: Service) -> None:
    target = svc.monitor.target
    assert target
    if ":" not in target:
        svc.status = "failing"
        svc.detail = "TCP target must be host:port"
        svc.latency_ms = None
        svc.last_checked = now_ts()
        return
    host, port_s = target.rsplit(":", 1)
    try:
        port = int(port_s)
    except ValueError:
        svc.status = "failing"
        svc.detail = "TCP port invalid"
        svc.latency_ms = None
        svc.last_checked = now_ts()
        return

    t0 = time.time()
    try:
        with socket.create_connection((host, port), timeout=svc.monitor.timeout_s):
            dt = int((time.time() - t0) * 1000)
            svc.latency_ms = dt
            svc.status = "passing"
            svc.detail = "TCP connect ok"
    except Exception as e:
        dt = int((time.time() - t0) * 1000)
        svc.latency_ms = dt
        svc.status = "failing"
        svc.detail = f"TCP error: {type(e).__name__}"
    finally:
        svc.last_checked = now_ts()
