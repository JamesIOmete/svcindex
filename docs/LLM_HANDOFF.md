# LLM Handoff Notes

- **New helper script**: `scripts/svcindex-docker-run.sh` wraps `docker run` with the svcindex label set expected by `svcindex/docker_discovery.py`. It keeps demos consistent and avoids copy/paste label errors.
- **Usage quickstart**: Run `./scripts/svcindex-docker-run.sh --help` for arguments. Pair it with the agent's `--docker` flag so containers appear automatically in the UI.
- **Health defaults**: The script points monitoring at `http://127.0.0.1:<ui-port>/<health-path>`; override `--health-path` if the container exposes a dedicated health endpoint.
- **Dry run support**: Use `--dry-run` while iterating on extra flags (`--extra "-e KEY=VALUE"`, `--extra "-v host:container"`) to confirm the generated `docker run` command without starting the container.
