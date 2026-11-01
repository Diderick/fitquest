# FitQuest activity backend

Single-user activity storage for the Flutter app. This token grants access to one
shared activity collection; it is not a multi-user account system. Goals,
nutrition, plans, and community features still use local storage. Existing local
activities are not automatically uploaded. Configured builds start with the server
collection, and report connection errors rather than falling back to local data.

## Server

Deployed at `/home/northstar/apps/fitquest` on `ssh.northstarlabs.tech`.
Public endpoint: `https://fitquest-api.northstarlabs.tech`.

Generate a random token of at least 32 characters in `.env`, using the format in
`.env.example`. Never commit the real token. Run:

```sh
docker compose up -d --build api
curl http://127.0.0.1:8011/health
```

The public deployment uses a dedicated Cloudflare tunnel, with its generated
`cloudflare.yml` and `tunnel-credentials.json` kept only on the server:

```sh
docker compose --profile public up -d
docker compose ps
docker compose logs --tail=50 api tunnel
```

Data lives in the `fitquest_fitquest-data` Docker volume. Preserve this volume
when updating. Back up SQLite with its online backup API or stop the API before
copying the database; WAL files can contain uncheckpointed writes. Do not use
`docker compose down -v` unless intentionally deleting activity data.

## Connect Flutter

Copy `.env`'s token into a local, ignored `apps/fitquest/client-config.json`:

```json
{
  "FITQUEST_API_URL": "https://fitquest-api.northstarlabs.tech",
  "FITQUEST_API_TOKEN": "your-server-token"
}
```

```sh
flutter run --dart-define-from-file=apps/fitquest/client-config.json
flutter build apk --release --dart-define-from-file=apps/fitquest/client-config.json
```

An API token included in a mobile build can be extracted. Use this deployment for
a trusted single-user build; add per-user login and server-side ownership before
distributing a public app. Builds without these defines retain local storage.

On Windows, use `powershell -File apps/fitquest/build-connected.ps1` to build the
connected APK without echoing encoded credentials. Its build log stays under the
ignored `build/` directory and should remain private. To rotate credentials, run
`bash ~/apps/fitquest/rotate-token.sh` on the server, copy the updated private
`client-config.json` to this folder, and rebuild any connected clients.

## API

`GET /health` is public. Other endpoints require `Authorization: Bearer TOKEN`.
`GET /v1/activities` returns `{"revision":0,"workouts":[]}`. `PUT /v1/activities`
accepts the same shape and returns the new revision. A stale revision returns 409
without modifying data. Restart the client to reload before trying again. Requests
are limited to 2 MiB; workouts and GPS coordinates are validated.

## Verification

Node 22 or newer is required (SQLite is built in).

```sh
node --test apps/fitquest/server.test.mjs
flutter test
flutter analyze
```

To verify the deployed API through the actual Flutter repository (reads and saves
the current collection with revision protection):

```sh
flutter test test/remote_activity_repository_test.dart --dart-define-from-file=apps/fitquest/client-config.json --dart-define=FITQUEST_RUN_LIVE_TEST=true
```
