# FitQuest accounts and offline sync

The Flutter app saves changes locally first. Activities, GPS routes, goals, plans,
nutrition, weigh-ins, community posts, follow choices, ad preferences and daily
phone step records sync to a signed-in user's private account. Guest mode works
without a server. Creating an account imports the current guest workspace;
signing into an existing account uses its own separate cache. Passwords are never
saved on the phone. Session tokens use OS secure storage.

Registration and first sign-in require a connection. An existing session remains
usable offline. Sync retries every 30 seconds while the app is open, on resume,
and after local changes. No background network-sync execution is promised when
the OS suspends the Flutter app. Failed uploads stay in a durable outbox across
restarts. Repeated operations are deduplicated by ID on the server. Concurrent
edits on two devices are preserved until the user chooses a version in Account &
sync. Nutrition and activity collections are treated as a single conflicting
item; resolve them before editing on both devices again.

## Server

Deployed at `/home/northstar/apps/fitquest` on `ssh.northstarlabs.tech`.
Public endpoint: `https://fitquest-api.northstarlabs.tech`.

Generate a random token of at least 32 characters in `.env`, using the format in
`.env.example`. This token is only for the legacy v1 endpoint, not account login.
Never commit the real token. Initial setup or updates use:

```sh
bash ~/apps/fitquest/deploy.sh
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
when updating. `deploy.sh` makes an online database backup before replacing an
existing API container. Keep backups off the server as well. Back up SQLite with its online backup API or stop the API before
copying the database; WAL files can contain uncheckpointed writes. Do not use
`docker compose down -v` unless intentionally deleting activity data.

## Connect Flutter

The default API hostname is compiled into the app. To override it, use the local,
ignored `apps/fitquest/client-config.json`. No shared credential belongs in a build:

```json
{
  "FITQUEST_API_URL": "https://fitquest-api.northstarlabs.tech"
}
```

```sh
flutter run --dart-define-from-file=apps/fitquest/client-config.json
flutter build apk --release --dart-define-from-file=apps/fitquest/client-config.json
```

On Windows, use `powershell -File apps/fitquest/build-connected.ps1` to build the
connected APK. Its build log stays under the ignored `build/` directory.

## Accounts and friends

Google/Facebook browser sign-in and explicit account linking are prepared; see
[social sign-in setup](SOCIAL_SETUP.md) to configure provider registrations.
Without credentials, these buttons stay disabled and email login still works.
The same guide covers activity image/text sharing to installed apps.

SQLite contains users, hashed sessions, per-user state, sync receipts and follow
relationships. Passwords use a random salt and scrypt (N=32768, r=8, p=1). Sessions
expire after 90 days; expired sessions require sign-in to resume sync, while
local logging continues. Authentication endpoints are rate-limited. Email
verification, password recovery, account deletion and store purchase verification
are not implemented yet; these need completion before public store release.

People are discoverable by public username, never email. Following is one-way;
mutual follows appear as friends. Community posts are shared with followers.
Weight, routes and nutrition are not included in social responses. Cached people
and follow choices work offline; finding new people needs a connection.

Provider imports can match discoverable friends through explicit consent. Emails
are used internally for verified Google matching, never returned in suggestions.
Invitation links support explicit follow-and-join for challenges. See
[friend discovery](FRIENDS_SETUP.md).

Local data is separated by account but uses unencrypted SharedPreferences. Secure
storage protects session tokens. Plan a local-data encryption migration and a
privacy policy before distributing sensitive health-data features publicly.

## Custom fitness challenges

Open **Quests → My fitness challenges** (Challenges tab) or **Community → Create
a fitness challenge**. Choose Custom, Military-style test, CrossFit-style AMRAP
or CrossFit-style for time. Set a name, dates, exercise protocols, equipment,
scaling and optional pass thresholds. Every exercise uses reps, seconds, metres,
kilograms or rounds with an explicit higher/lower scoring direction. Templates
are personal training examples, not official military scoring standards.

Challenges default to private. Select **My followers** to let people who follow
the creator discover, join and view participant usernames/results. Followers
discover challenges after refreshing their challenge list. No weights or routes
are automatically included. Scoring rules are fixed once saved; create another
challenge to change a protocol without mixing incompatible results. Creators can
change sharing between private and followers and invite friends to join.

Log any tested exercise, leaving untested ones blank. Time accepts `mm:ss` or
whole seconds. Prescribed and scaled attempts are ranked separately, one best
completed result per participant per exercise, with ties sharing a rank. There is
no invented overall score adding different units. Unfinished attempts need notes
and appear in history but are excluded from rankings. Attempts can be deleted;
offline deletion syncs later. Rankings are self-reported and show cached results
offline (refresh to update); the server returns the latest 2,000 attempts.

Definitions, joins and attempts use the durable account outbox. A guest can
create and record private challenges without a connection; registration imports
them. Following and joining are processed before result uploads in each sync
batch. The server validates ownership, visibility, membership, dates, exercise
IDs and numeric units. Invalid uploads stay local and are reported by sync.

API routes: `GET /v2/challenges` lists personal and followed creators' shared
challenges; `GET /v2/challenges/{id}` returns an accessible definition and results.
Definitions and results remain isolated through the existing per-user state keys.

## Phone steps and sponsor placements

See [profile and daily nutrition](PROFILE_NUTRITION.md) for profile photo/gender,
food/drink timestamps, daily exercise-credit arithmetic and legacy-log handling.

Android uses TYPE_STEP_COUNTER and an optional health foreground service with an
ongoing notification. Counting begins from the first enabled sensor reading,
continues offline, and handles counter resets and phone reboots without adding a
previous boot's counter. Reopen FitQuest after a reboot or force-stop. Android
cannot reconstruct missing daily history while its listener is stopped. Daily
totals use the phone's local calendar day. Motion permission is required and
notification permission is requested. Devices without a sensor show unavailable.

iOS uses CMPedometer to query the phone's steps since local midnight and requests
Motion & Fitness access. It requires a physical iPhone and a macOS build to
validate; the Windows Android build cannot verify the iOS integration. Neither
platform adds workout distance estimates to sensor steps.

Only Home and Community have labeled sponsor preview cards. They can be hidden
for free in Profile or Account & sync. There is no ad SDK, live advertising,
tracking, billing or fabricated purchase entitlement. Supply AdMob app/ad-unit IDs
and store product IDs to implement live ads, consent and a verified remove-ads
purchase. No ads appear in GPS recording, weigh-in or login forms.

## API

`GET /health` is public. `POST /v2/auth/register` and `/v2/auth/login` accept an
email/password, plus username for registration. Other v2 routes require the
returned session token as `Authorization: Bearer TOKEN`:

- `GET /v2/me`, `POST /v2/auth/logout`
- `POST /v2/sync`: `{operations: [{id,key,value,base}]}`; returns acknowledgments,
  conflicting keys and private state with per-key versions.
- `GET /v2/people?q=prefix`, `GET /v2/social`

The old `/v1/activities` API and its original database row remain available for
previous single-user builds. That shared collection is never automatically
assigned to a new account. New builds do not include the old shared token.

## Verification

Node 22 or newer is required (SQLite is built in).

```sh
node --test apps/fitquest/server.test.mjs apps/fitquest/oauth.test.mjs
flutter test
flutter analyze
```

To smoke-test the deployed public API from Windows, with unique temporary
accounts removed afterward, upload `smoke.mjs` to the server and container first:

```sh
scp apps/fitquest/smoke.mjs ssh.northstarlabs.tech:apps/fitquest/
ssh ssh.northstarlabs.tech 'cd ~/apps/fitquest && docker compose cp smoke.mjs api:/tmp/fitquest-smoke.mjs'
```

Then in PowerShell run `$env:FITQUEST_SMOKE_SSH='1'` followed by
`node apps/fitquest/smoke.mjs`. The test prints no credentials and cleans up only
the accounts it creates. Android sensor permissions, background operation,
midnight rollover and reboots still need real-phone QA.
