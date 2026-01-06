from __future__ import annotations

import os
from typing import Any, Dict, List, Optional

import requests

def consul_addr(default: str = "http://127.0.0.1:8500") -> str:
    return os.getenv("CONSUL_HTTP_ADDR", default).rstrip("/")

def consul_token() -> Optional[str]:
    return os.getenv("CONSUL_HTTP_TOKEN")

def _headers() -> Dict[str, str]:
    h: Dict[str, str] = {}
    tok = consul_token()
    if tok:
        h["X-Consul-Token"] = tok
    return h

def get_json(path: str, params: Optional[Dict[str, Any]] = None, base: Optional[str] = None) -> Any:
    base_url = (base or consul_addr()).rstrip("/")
    url = f"{base_url}{path}"
    r = requests.get(url, params=params, headers=_headers(), timeout=3)
    r.raise_for_status()
    return r.json()

def put_json(path: str, payload: Any, base: Optional[str] = None) -> Any:
    base_url = (base or consul_addr()).rstrip("/")
    url = f"{base_url}{path}"
    r = requests.put(url, json=payload, headers=_headers(), timeout=3)
    r.raise_for_status()
    if r.text.strip():
        try:
            return r.json()
        except Exception:
            return r.text
    return None

def register_service(service_id: str, name: str, address: str, port: int, tags: List[str], checks: List[Dict[str, Any]]) -> None:
    payload = {
        "ID": service_id,
        "Name": name,
        "Address": address,
        "Port": port,
        "Tags": tags,
    }
    if checks:
        payload["Checks"] = checks
    put_json("/v1/agent/service/register", payload)

def deregister_service(service_id: str) -> None:
    put_json(f"/v1/agent/service/deregister/{service_id}", payload={})
