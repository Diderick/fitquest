#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/apps/fitquest"
umask 077
if [ ! -f .env ]; then
  python3 -c 'import secrets; print("FITQUEST_API_TOKEN=" + secrets.token_urlsafe(48)); print("POSTGRES_PASSWORD=" + secrets.token_urlsafe(32))' > .env
fi
chmod 600 .env
mkdir -p backups
if [ -n "$(docker compose ps --status running -q db)" ]; then
  stamp=$(date +%s)
  docker compose exec -T db pg_dump -U fitquest fitquest > "backups/before-update-${stamp}.sql"
  chmod 600 "backups/before-update-${stamp}.sql"
  echo "Created PostgreSQL backup before update"
fi
docker compose up -d --build db api
