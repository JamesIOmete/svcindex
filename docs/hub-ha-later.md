# Hub UI HA (later)

svcindex-hub is stateless. To make it HA later:

1) Run `svcindex-hub` on two machines (both pointing at Consul).
2) Use keepalived/VRRP to expose a single virtual IP (e.g., `services.lan`).
3) Put DNS `services.lan -> VIP`.

No app changes required.
