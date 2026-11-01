#!/usr/bin/env bash
set -euo pipefail
cd "$HOME/apps/fitquest"
umask 077
if [ ! -f .env ]; then
  python3 -c 'import secrets; print("FITQUEST_API_TOKEN=" + secrets.token_urlsafe(48))' > .env
fi
chmod 600 .env
if [ -n "$(docker compose ps --status running -q api)" ]; then
  docker compose exec -T api node --input-type=module <<'JS'
import { DatabaseSync, backup } from 'node:sqlite';
const db = new DatabaseSync(process.env.FITQUEST_DB);
await backup(db, `/data/before-update-${Date.now()}.sqlite`);
db.close();
console.log('Created SQLite backup before update');
JS
fi
docker compose up -d --build api
