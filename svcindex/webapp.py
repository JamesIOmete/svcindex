from __future__ import annotations

import threading
import time
from collections import defaultdict
from typing import Callable, Dict, List, Optional

from flask import Flask, render_template, request

from .util import Service, hostname, now_ts

def create_app(
    mode: str,
    get_services: Callable[[], List[Service]],
    title: str,
    hub_consul_addr: Optional[str] = None,
) -> Flask:
    app = Flask(__name__, template_folder="templates", static_folder="static")

    @app.get("/")
    def index():
        services = get_services()
        groups: Dict[str, List[Service]] = defaultdict(list)
        for s in services:
            groups[s.type or "other"].append(s)
        # sort within group
        for k in list(groups.keys()):
            groups[k] = sorted(groups[k], key=lambda x: x.name.lower())

        return render_template(
            "index.html",
            title=title,
            mode=mode,
            host=hostname(),
            now=int(now_ts()),
            groups=sorted(groups.items(), key=lambda kv: kv[0]),
            hub_consul_addr=hub_consul_addr,
        )

    @app.get("/healthz")
    def healthz():
        return {"ok": True, "mode": mode}

    return app
