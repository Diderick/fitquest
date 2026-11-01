# Friend discovery and invitations

Open **Community → Friends → Find friends & following** or **Account & sync →
Find friends & following**. Users can review imported suggestions, follow selected
people, or invite others with a shareable link. Nothing follows, joins, creates
accounts for contacts, or sends messages automatically.

## Provider setup

The Google/Meta credentials in [social login setup](SOCIAL_SETUP.md) are still
required. Imports ask for extra permission separately from ordinary sign-in.

- **Google:** enable People API in the OAuth project and configure read-only
  `https://www.googleapis.com/auth/contacts.readonly` consent. Matching uses verified
  linked Google emails and target users' discovery opt-in. An unverified email on
  a password account cannot impersonate a Google contact. Existing Google links
  refresh their verified address on the next successful connection.
- **Facebook:** configure `user_friends` permission and required app access/review.
  The app checks that permission, then matches eligible app-scoped friends returned
  by `/me/friends`. These must also use FitQuest, link Facebook, and allow discovery.
  This does not import an unrestricted Facebook friend list.
- Other contacts can use invite links; the app does not scrape social websites or
  claim to retrieve a public WhatsApp friend list.

**Let social friends discover me** defaults off. Google discovery allows people
who have the user's verified Google email in contacts to find their public
FitQuest username. Facebook discovery applies to eligible app-scoped friends.
This setting does not disable public username search or shared invitation links.

Only matched FitQuest IDs, source and import time are stored in suggestion tables.
Unmatched contact emails, names, address books and provider access/refresh tokens
are not stored. Own verified Google email addresses are stored on identity rows.
Server reads re-check current discovery settings; already viewed information can
remain in an offline cache. Clear imported suggestions removes matches, not
existing follows. Offline clearing hides the local cache and retries server
clearing on the next refresh of this screen.

Imports read up to ten provider pages; the UI indicates a partial import. The
suggestion response is limited to 500 rows. Declining permission or a failed import
does not clear previous matches or follow anyone.

## Invitations, following and joining

Use **Invite via WhatsApp, Facebook or another app**, **Copy my invitation link**,
or **Open an invitation link or code**. Creating the first invitation requires a
connection; cached links can be shared offline. The reusable HTTPS link includes
no session credential.

The public `/join/{code}` page displays the public username and, if shared, a
challenge title. **Open in FitQuest** opens the app. If not installed, recipients
are told to install the APK shared by their friend and return to the link. No
nonexistent store URL is advertised. A raw code opens a profile; paste the full
link to preserve a challenge invitation.

Pending invites survive restart while sign-in/registration is in progress. The
recipient explicitly chooses **Follow friend** or **Follow & join challenge**.
The latter saves both choices atomically and opens the test. Mutual follows are
friends. Cached invitations and known people can be followed/joined offline;
first lookup and initial registration need a connection.

Challenge owners can toggle **Share with my followers** and use **Invite friends
to this challenge**. Sharing can change, but exercise protocols and scoring stay
fixed. Invite lookup never exposes private challenge rules or results. Cached
invitations are last-known information; a later server join can be refused if the
creator revoked sharing.

## API and checks

- `GET /v2/friends/suggestions`
- `POST /v2/friends/imports/clear` with `{provider: "google" | "facebook" | "all"}`
- `POST /v2/friends/invite`
- `GET /v2/friends/invites/{code}?challenge={id}`

OAuth start accepts `purpose: "friends"` only for an authenticated FitQuest user.
Normal sign-in keeps minimal scopes. Provider tokens are used only inside the
callback; returned grants include purpose/provider, never the contact list.

```sh
node --test apps/fitquest/server.test.mjs apps/fitquest/oauth.test.mjs apps/fitquest/social_friends.test.mjs
flutter test
flutter analyze
```

Tests cover consent, opt-in/verified matching, no automatic follows, scoped caches,
private challenge access, persistent invite parsing, and offline follow-and-join.
Real provider consent/import and phone-to-phone links still need configured apps
and physical-device checks.

References: [Google People API](https://developers.google.com/people/api/rest/v1/people.connections/list),
[Meta friends endpoint](https://developers.facebook.com/docs/graph-api/reference/user/friends/).
