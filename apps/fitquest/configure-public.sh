#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/apps/fitquest"
chmod 700 "$PWD"
umask 077
tunnel_id=1a142c42-819b-4d93-b1f7-0561c38eff0e
cp "$HOME/.cloudflared/$tunnel_id.json" tunnel-credentials.json
cat > cloudflare.yml <<EOF
tunnel: $tunnel_id
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: fitquest-api.northstarlabs.tech
    service: http://api:8000
  - service: http_status:404
EOF
# cloudflared runs as an unprivileged container user; the parent directory is 700.
chmod 644 tunnel-credentials.json cloudflare.yml
cloudflared tunnel route dns "$tunnel_id" fitquest-api.northstarlabs.tech
docker compose --profile public up -d
python3 - <<'PY'
import json
from pathlib import Path
token = next(line.split('=', 1)[1] for line in Path('.env').read_text().splitlines() if line.startswith('FITQUEST_API_TOKEN='))
Path('client-config.json').write_text(json.dumps({
    'FITQUEST_API_URL': 'https://fitquest-api.northstarlabs.tech',
}, indent=2) + '\n')
Path('client-config.json').chmod(0o600)
PY
