#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/apps/fitquest"
umask 077
python3 - <<'PY'
import json
import secrets
from pathlib import Path
token = secrets.token_urlsafe(48)
config = Path('.env')
lines = config.read_text().splitlines() if config.exists() else []
lines = [line for line in lines if not line.startswith('FITQUEST_API_TOKEN=')]
lines.append('FITQUEST_API_TOKEN=' + token)
config.write_text('\n'.join(lines) + '\n')
Path('.env').chmod(0o600)
Path('client-config.json').write_text(json.dumps({
    'FITQUEST_API_URL': 'https://fitquest-api.northstarlabs.tech',
}, indent=2) + '\n')
Path('client-config.json').chmod(0o600)
PY
docker compose up -d api
