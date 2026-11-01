import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { socialFriends } from './social_friends.mjs';

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.exec(`CREATE TABLE users (id TEXT PRIMARY KEY,username TEXT,email TEXT);
    CREATE TABLE user_state (user_id TEXT,key TEXT,value TEXT,version INTEGER);
    CREATE TABLE oauth_identities (provider TEXT,subject TEXT,user_id TEXT,verified_email TEXT);
    CREATE TABLE follows (follower TEXT,following TEXT);`);
  for (const id of ['owner', 'google-friend', 'facebook-friend', 'hidden', 'unverified']) {
    db.prepare('INSERT INTO users VALUES (?,?,?)').run(id, id.replaceAll('-', '_'), `${id}@example.test`);
  }
  db.exec(`INSERT INTO oauth_identities VALUES ('google','g-friend','google-friend','friend@example.test'),
    ('google','g-hidden','hidden','hidden@example.test'),('facebook','fb-friend','facebook-friend',NULL);
    INSERT INTO user_state VALUES ('google-friend','friend_discovery','true',1),
    ('facebook-friend','friend_discovery','true',1);`);
  const reply = (res, status, body) => Object.assign(res, { status, body });
  const api = socialFriends(db, reply);
  async function request(path, data) {
    const res = {};
    await api.route({ method: data ? 'POST' : 'GET' }, res, new URL(path, 'https://example.test'), { id: 'owner', username: 'owner' }, async () => data);
    return res;
  }
  return { db, api, request };
}
test('Google import is paginated, consented, opt-in and verified; contacts are never stored or auto-followed', async () => {
  const f = fixture();
  try {
    let pages = 0;
    const imported = await f.api.collect('google', 'temporary-token', async (address, options) => {
      const url = new URL(address);
      assert.equal(url.hostname, 'people.googleapis.com');
      assert.equal(url.searchParams.get('personFields'), 'emailAddresses');
      assert.equal(options.headers.Authorization, 'Bearer temporary-token');
      pages++;
      return pages === 1 ? { connections: [{ emailAddresses: [{ value: 'FRIEND@example.test' }] },
        { emailAddresses: [{ value: 'hidden@example.test' }] }, { emailAddresses: [{ value: 'unverified@example.test' }] }], nextPageToken: 'page2' }
        : { connections: [{ emailAddresses: [{ value: 'friend@example.test' }] }] };
    });
    assert.equal(pages, 2);
    f.api.saveMatches('owner', 'google', imported);
    const result = await f.request('/v2/friends/suggestions');
    assert.deepEqual(result.body.people.map(person => ({ ...person })), [{ id: 'google-friend', username: 'google_friend', provider: 'google' }]);
    assert.equal(JSON.stringify(result.body).includes('friend@example.test'), false);
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM follows').get().n, 0);
    assert.deepEqual(Object.keys(f.db.prepare('SELECT * FROM social_suggestions').get()), ['user_id', 'provider', 'target_id', 'created']);
    f.db.prepare("UPDATE user_state SET value='false' WHERE user_id='google-friend'").run();
    assert.equal((await f.request('/v2/friends/suggestions')).body.people.length, 0);
    await f.request('/v2/friends/imports/clear', { provider: 'all' });
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM social_suggestions').get().n, 0);
  } finally { f.db.close(); }
});
test('Facebook import checks friend-list consent and returns only matching discoverable app users', async () => {
  const f = fixture();
  try {
    await assert.rejects(f.api.collect('facebook', 'token', async () => ({ data: [] }), 'https://graph.facebook.com/v99.0', 'proof'), e => e.status === 403);
    const imported = await f.api.collect('facebook', 'token', async url => url.includes('/permissions?')
      ? { data: [{ permission: 'user_friends', status: 'granted' }] }
      : { data: [{ id: 'fb-friend' }, { id: 'not-a-fitquest-user' }] }, 'https://graph.facebook.com/v99.0', 'proof');
    f.api.saveMatches('owner', 'facebook', imported);
    assert.equal((await f.request('/v2/friends/suggestions')).body.people[0].id, 'facebook-friend');
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM follows').get().n, 0);
  } finally { f.db.close(); }
});
test('invitations are reusable, expose no email, and cannot reveal private challenge rules', async () => {
  const f = fixture();
  try {
    const first = await f.request('/v2/friends/invite', {});
    assert.equal(first.body.code.length, 24);
    assert.equal((await f.request('/v2/friends/invite', {})).body.code, first.body.code);
    const path = `/v2/friends/invites/${first.body.code}?challenge=test`;
    const definition = { id: 'test', title: 'Private protocol', visibility: 'private', events: [] };
    f.db.prepare('INSERT INTO user_state VALUES (?,?,?,?)').run('owner', 'challenge.test', JSON.stringify(JSON.stringify(definition)), 1);
    const privateResult = await f.request(path);
    assert.equal(privateResult.body.challenge, null);
    assert.equal(privateResult.body.person.email, undefined);
    definition.visibility = 'followers';
    f.db.prepare('UPDATE user_state SET value=? WHERE key=?').run(JSON.stringify(JSON.stringify(definition)), 'challenge.test');
    assert.equal((await f.request(path)).body.challenge.id, 'test');
    const res = { writeHead(status, headers) { this.status = status; this.headers = headers; }, end(html) { this.html = html; } };
    f.api.publicRoute({ method: 'GET' }, res, new URL(`/join/${first.body.code}?challenge=test`, 'https://example.test'));
    assert.equal(res.status, 200);
    assert.ok(res.html.includes('fitquest-auth://invite?'));
    assert.equal(res.html.includes('owner@example.test'), false);
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM follows').get().n, 0);
  } finally { f.db.close(); }
});
