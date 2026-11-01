# Google / Facebook sign-in and activity sharing

Activity sharing is available without provider credentials. Google and Facebook
sign-in are implemented but disabled until real registrations are configured.
No provider secret or shared API credential is compiled into the mobile app.

## Activate sign-in

Add the following values to **the server's** `/home/northstar/apps/fitquest/.env`,
preserving `FITQUEST_API_TOKEN` and other existing values. Keep this file mode 600.
Do not put secrets in Git, Flutter defines or chat messages.

```dotenv
GOOGLE_CLIENT_ID=your-web-oauth-client-id
GOOGLE_CLIENT_SECRET=your-web-oauth-client-secret
FACEBOOK_APP_ID=your-meta-app-id
FACEBOOK_APP_SECRET=your-meta-app-secret
FACEBOOK_GRAPH_VERSION=the-supported-version-from-your-meta-dashboard
```

The Facebook version must use a value of the form `vNUMBER.NUMBER` (not the
placeholder above). Each provider can be enabled independently. Then run:

```sh
cd ~/apps/fitquest
docker compose up -d api
curl https://fitquest-api.northstarlabs.tech/v2/oauth/providers
```

Reopen Account & sync to refresh availability. The app does not need another
build just to activate credentials. OAuth client secrets remain on the server.

### Google

Create a Google Cloud OAuth consent configuration and an OAuth client of type
**Web application**, because FitQuest uses a confidential server-side browser
flow. Configure the app's verified domains/branding and add this exact authorized
redirect URI:

```text
https://fitquest-api.northstarlabs.tech/v2/oauth/google/callback
```

Use the client ID and secret from this web client. Do not substitute an Android
client ID. In testing mode, add the accounts that should be allowed to test.
The server requests OpenID and email, validates Google's signed ID token,
audience, issuer, expiry and nonce, and establishes a FitQuest session.

[Google OpenID Connect setup](https://developers.google.com/identity/openid-connect/openid-connect)

### Facebook

Create a Meta app with Facebook Login and configure web login for the API's HTTPS
origin. Add this exact Valid OAuth Redirect URI:

```text
https://fitquest-api.northstarlabs.tech/v2/oauth/facebook/callback
```

Set the app ID, app secret and supported Graph API version from your dashboard.
Configure the provider's required app-domain, privacy/data-deletion settings and
test users before switching to live mode. The server requests public profile and
email, validates the token against the configured app using `debug_token`, then
reads the matching app-scoped user ID with an app-secret proof. It also supports
Facebook accounts that do not return an email address.

[Meta manual login flow](https://developers.facebook.com/docs/facebook-login/guides/advanced/manual-flow/)

## Account behavior and linking

First social sign-in creates a private FitQuest account and a random public
`athlete_...` username. Provider names/photos are not automatically published.
Only a newly created account imports guest data. Subsequent sign-ins restore the
account's existing local workspace and sync. Existing sessions work offline;
starting a new provider sign-in needs a connection.

Matching email addresses never silently merge accounts. An existing password
user must first sign in normally, then choose **Link Google** or **Link Facebook**
in Account & sync. A provider identity already linked to another FitQuest account
cannot be reassigned through this flow. Sign-out ends the FitQuest session; it
does not sign the user out of their browser's Google or Facebook account.

The browser returns via `fitquest-auth://callback`. Android intent handling and
iOS URL/scene handling are included. The mobile app stores a temporary PKCE
verifier/state in OS secure storage. Provider codes/tokens stay on the backend;
the app receives a two-minute, single-use code bound to that verifier. It exchanges
the code for a session over HTTPS. Sessions never appear in callback URLs.
Social sign-in is gated to Android/iOS; desktop/web builds retain email login.

Routes: `GET /v2/oauth/providers`, `POST /v2/oauth/{provider}/start`,
`GET /v2/oauth/{provider}/callback`, `POST /v2/oauth/exchange`.

## Share an activity

Use the share icon on an activity or open its details and choose **Share activity**.
The preview can export a 1080×1350 PNG card, share a text summary, copy a caption,
or post the summary to the FitQuest community feed. Rendering and local feed
drafts work offline. FitQuest feed posts use the existing durable outbox.

Route sketches and notes default off. Only the selected activity's date, sport,
duration and optional distance are included by default. No account email, profile
weight, nutrition or raw route-coordinate list is exported. An explicitly enabled
route sketch can still disclose places visited, so users see that before sharing.

Image sharing sends an image without prefilled text for wider compatibility;
copy the summary separately for a caption. WhatsApp/Facebook/other destinations
are supplied by the installed apps and OS share sheet. Destination caption and
feed behavior varies; the app does not claim a post was published merely because
the share sheet opened or closed. It never posts automatically to an external
account. The FitQuest-feed button posts a text summary, not the private GPS trace.

[Share plugin behavior and destination limitations](https://pub.dev/packages/share_plus)

## Validation and remaining real-device checks

```sh
node --test apps/fitquest/oauth.test.mjs apps/fitquest/server.test.mjs
flutter test
flutter analyze
```

Automated tests verify signed identities, nonce/audience rejection, Facebook app
validation, explicit linking, single-use/PKCE/state checks, offline cache behavior
and PNG generation/privacy defaults. They use test provider responses, not a fake
production login switch. The deployed capability endpoint reports disabled
providers until credentials are supplied. Real Google/Meta consent, browser
return, iOS builds and installed-app sharing require provider credentials and
physical-device testing; the Windows build cannot exercise iPhone behavior.
