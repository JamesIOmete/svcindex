from __future__ import annotations

import argparse
import os
import threading
import time
from typing import List, Optional

from flask import Flask

from .util import Service, hostname
from .registry import load_services_from_dir
from .docker_discovery import discover_from_labels
from .checks import check_service
from .webapp import create_app
from .consul_sync import sync_services_to_local_consul
from .consul_client import get_json

def main():
    p = argparse.ArgumentParser(prog="svcindex")
    p.add_argument("--mode", choices=["agent", "hub"], required=True, help="Run as per-host agent or hub UI")
    p.add_argument("--listen", default="0.0.0.0", help="Listen address")
    p.add_argument("--port", type=int, default=8080, help="Listen port")
    p.add_argument("--services-dir", default="/etc/svcindex/services.d", help="Directory with YAML service definitions")
    p.add_argument("--poll", type=int, default=30, help="Polling interval for checks/discovery (seconds)")
    p.add_argument("--docker", action="store_true", help="Enable Docker label discovery (opt-in via labels)")

    # Consul integration
    p.add_argument("--consul-sync", action="store_true", help="Register discovered services to local Consul agent")
    p.add_argument("--advertise", default="", help="Advertise address to register into Consul (defaults to best-effort local IP)")
    p.add_argument("--consul-server", default="", help="Consul server address for hub mode, e.g. http://192.168.1.10:8500")

    args = p.parse_args()

    if args.mode == "agent":
        run_agent(args)
    else:
        run_hub(args)

def run_agent(args) -> None:
    lock = threading.Lock()
    services: List[Service] = []
    node = hostname()

    def discover() -> List[Service]:
        items = load_services_from_dir(args.services_dir)
        if args.docker:
            items.extend(discover_from_labels())
        # de-dupe by name (last wins)
        by = {}
        for s in items:
            by[s.name] = s
        return list(by.values())

    def refresh_loop():
        nonlocal services
        while True:
            items = discover()
            for s in items:
                check_service(s)
            if args.consul_sync:
                try:
                    sync_services_to_local_consul(
                        items,
                        node=node,
                        advertise_addr=(args.advertise or None),
                        consul_base=os.getenv("CONSUL_HTTP_ADDR") or None,
                    )
                except Exception:
                    pass
            with lock:
                services = items
            time.sleep(max(5, args.poll))

    t = threading.Thread(target=refresh_loop, daemon=True)
    t.start()

    def get_services():
        with lock:
            return list(services)

    title = f"svcindex · {node}"
    app = create_app(mode="agent", get_services=get_services, title=title)
    app.run(host=args.listen, port=args.port, threaded=True)

def run_hub(args) -> None:
    lock = threading.Lock()
    services: List[Service] = []

    if args.consul_server:
        os.environ["CONSUL_HTTP_ADDR"] = args.consul_server

    def refresh_loop():
        nonlocal services
        while True:
            items = discover_from_consul()
            with lock:
                services = items
            time.sleep(max(5, args.poll))

    t = threading.Thread(target=refresh_loop, daemon=True)
    t.start()

    def get_services():
        with lock:
            return list(services)

    title = "svcindex · hub"
    app = create_app(mode="hub", get_services=get_services, title=title, hub_consul_addr=os.getenv("CONSUL_HTTP_ADDR"))
    app.run(host=args.listen, port=args.port, threaded=True)

def discover_from_consul() -> List[Service]:
    """Best-effort global discovery: lists all services and their instances from Consul."""
    out: List[Service] = []
    try:
        catalog = get_json("/v1/catalog/services") or {}
    except Exception:
        return out

    for svc_name, tags in catalog.items():
        # Pull instances + checks
        try:
            entries = get_json(f"/v1/health/service/{svc_name}", params={"passing": "false"}) or []
        except Exception:
            entries = []

        for e in entries:
            service = e.get("Service") or {}
            checks = e.get("Checks") or []
            node = (e.get("Node") or {}).get("Node", "unknown")
            addr = service.get("Address") or (e.get("Node") or {}).get("Address") or ""
            port = service.get("Port") or 0

            # Determine status: passing if all checks passing (or no checks => unknown)
            if not checks:
                status = "unknown"
                detail = "No checks"
            else:
                failing = [c for c in checks if str(c.get("Status")) != "passing"]
                if failing:
                    status = "failing"
                    detail = failing[0].get("Output") or failing[0].get("CheckID") or "check failing"
                else:
                    status = "passing"
                    detail = "passing"

	    # Monitor mode inferred from tags if present
	    tag_list = list(service.get("Tags") or tags or [])
	    mon_mode = _tag_value(tag_list, "monitor") or "none"
	    svc_type = _tag_value(tag_list, "type") or "other"

	    # ✅ Option A: if not monitored, show "unmonitored" unless there is a failing check
	    if mon_mode == "none" and status != "failing":
    		status = "unmonitored"
    		if detail in ("passing", "No checks"):
        		detail = "No monitoring configured"

            url = _guess_url(service.get("Meta") or {}, addr, port, svc_name)

            s = Service(
                name=f"{svc_name} @ {node}",
                type=svc_type,
                url=url,
                description=(service.get("Meta") or {}).get("description", ""),
                tags=tag_list,
            )
            s.monitor.mode = mon_mode
            s.status = status
            s.detail = str(detail)[:120]
            out.append(s)
    return out

def _tag_value(tags: List[str], key: str) -> str:
    prefix = f"{key}="
    for t in tags:
        if isinstance(t, str) and t.startswith(prefix):
            return t[len(prefix):]
    return ""

def _guess_url(meta: dict, addr: str, port: int, name: str) -> str:
    # If the agent provided a URL in Meta, use it. Otherwise guess http://addr:port for nonzero port.
    if isinstance(meta, dict):
        u = meta.get("url")
        if u:
            return str(u)
    if addr and port:
        return f"http://{addr}:{port}"
    return ""
