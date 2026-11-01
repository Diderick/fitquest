#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/apps/fitquest"
umask 077
if [ ! -f .env ]; then
  python3 -c 'import secrets; print("FITQUEST_API_TOKEN=" + secrets.token_urlsafe(48))' > .env
fi
chmod 600 .env
docker compose up -d --build api
