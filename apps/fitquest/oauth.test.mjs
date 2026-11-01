import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { generateKeyPairSync, sign, randomBytes, createHash } from 'node:crypto';
import { oauth } from './oauth.mjs';
import { socialFriends } from './social_friends.mjs';

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const jwk = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', use: 'sig' };
function fixture(configured = true) {
  const db = new DatabaseSync(':memory:');
  db.exec('CREATE TABLE users (id TEXT PRIMARY KEY,email TEXT UNIQUE,username TEXT UNIQUE,salt TEXT,password_hash TEXT,created INTEGER)');
  db.exec('CREATE TABLE user_state (user_id TEXT,key TEXT,value TEXT,version INTEGER)');
  db.prepare('INSERT INTO users VALUES (?,?,?,?,?,?)').run('existing', 'owner@example.test', 'ExistingUser', 'salt', 'hash', 0);
  const env = configured ? { GOOGLE_CLIENT_ID: 'test-client', GOOGLE_CLIENT_SECRET: 'test-secret', FACEBOOK_APP_ID: 'test-app', FACEBOOK_APP_SECRET: 'test-secret', FACEBOOK_GRAPH_VERSION: 'v99.0' } : {};
  const identity = { nonce: '', subject: 'google-person', email: 'new@example.test', audience: 'test-client', facebookApp: 'test-app' };
  const token = () => {
    const now = Math.floor(Date.now() / 1000);
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', kid: 'test-key' })).toString('base64url');
    const body = Buffer.from(JSON.stringify({ iss: 'https://accounts.google.com', aud: identity.audience,
      sub: identity.subject, email: identity.email, email_verified: true, name: 'Private Real Name', nonce: identity.nonce, iat: now, exp: now + 300 })).toString('base64url');
    return `${header}.${body}.${(identity.badSignature ? Buffer.alloc(256) : sign('RSA-SHA256', Buffer.from(`${header}.${body}`), privateKey)).toString('base64url')}`;
  };
  const fetcher = async address => {
    const url = String(address);
    let value;
    if (url.endsWith('/token')) value = { id_token: token(), access_token: 'temporary-google-token' };
    else if (url.endsWith('/certs')) value = { keys: [jwk] };
    else if (url.endsWith('/oauth/access_token')) value = { access_token: 'test-provider-access-token' };
    else if (url.includes('/debug_token?')) value = { data: { is_valid: true, app_id: identity.facebookApp, user_id: 'fb-person', expires_at: Date.now() / 1000 + 300 } };
    else if (url.includes('/me?')) value = { id: 'fb-person', name: 'Private Facebook Name' };
    else if (url.includes('people.googleapis.com/')) value = { connections: [] };
    else if (url.includes('/me/permissions?')) value = { data: identity.permissionDenied ? [] : [{ permission: 'user_friends', status: 'granted' }] };
    else if (url.includes('/me/friends?')) value = { data: [] };
    else throw new Error('Unexpected provider request');
    return { ok: true, json: async () => value };
  };
  const reply = (res, status, body) => { res.status = status; res.body = body; };
  const friends = socialFriends(db, reply);
  const route = oauth(db, reply, { env, fetcher, friends, body: async req => req.body,
    rateLimit: () => {}, sessionFor: req => req.headers.authorization === 'Bearer existing'
      ? db.prepare('SELECT * FROM users WHERE id=?').get('existing') : undefined,
    createSession: user => ({ token: 'private-fitquest-session', user: { id: user.id, username: user.username } }),
  });
  async function request(path, { body, authorization } = {}) {
    const req = { method: body ? 'POST' : 'GET', headers: { ...(authorization ? { authorization } : {}) }, body };
    const res = { writeHead(status, headers) { this.status = status; this.headers = headers; }, end() {} };
    try { await route(req, res, new URL(path, 'https://example.test')); }
    catch (error) { reply(res, error.status ?? 500, { error: error.message }); }
    return res;
  }
  async function start(provider = 'google', authorization, purpose = 'signin') {
    const verifier = randomBytes(48).toString('hex'), appState = randomBytes(24).toString('hex');
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    const response = await request(`/v2/oauth/${provider}/start`, { body: { challenge, appState, purpose }, authorization });
    assert.equal(response.status, 200);
    const url = new URL(response.body.authorizationUrl);
    identity.nonce = url.searchParams.get('nonce');
    return { verifier, appState, state: url.searchParams.get('state'), provider, url };
  }
  async function callback(flow) {
    const response = await request(`/v2/oauth/${flow.provider}/callback?state=${flow.state}&code=provider-code`);
    return { response, link: response.headers?.Location ? new URL(response.headers.Location) : null };
  }
  const exchange = (flow, link, overrides = {}) => request('/v2/oauth/exchange', { body: {
    code: link.searchParams.get('code'), verifier: flow.verifier, appState: flow.appState, ...overrides,
  } });
  return { db, identity, request, start, callback, exchange };
}

test('Google signature/nonce flow, PKCE binding, single-use grants and opaque usernames', async () => {
  const f = fixture();
  try {
    const flow = await f.start();
    const { response, link } = await f.callback(flow);
    assert.equal(response.status, 303);
    assert.equal(link.protocol, 'fitquest-auth:');
    assert.equal(link.searchParams.get('state'), flow.appState);
    assert.equal(link.href.includes('private-fitquest-session'), false);
    assert.equal((await f.exchange(flow, link, { verifier: 'wrong'.repeat(16) })).status, 401);
    assert.equal((await f.exchange(flow, link, { appState: 'wrong-state' })).status, 401);
    const session = await f.exchange(flow, link);
    assert.equal(session.status, 200);
    assert.equal(session.body.created, true);
    assert.ok(session.body.user.username.startsWith('athlete_'));
    assert.equal(session.body.user.username.includes('Private'), false);
    assert.equal((await f.exchange(flow, link)).status, 401);
    assert.equal((await f.callback(flow)).response.status, 401);
    const second = await f.start();
    const again = await f.exchange(second, (await f.callback(second)).link);
    assert.equal(again.body.user.id, session.body.user.id);
    assert.equal(again.body.created, false);
    const invalid = await f.start();
    f.identity.audience = 'another-app';
    assert.equal((await f.callback(invalid)).link.searchParams.get('error'), 'provider_failed');
    f.identity.audience = 'test-client';
    const nonce = await f.start();
    f.identity.nonce = 'wrong-nonce';
    assert.equal((await f.callback(nonce)).link.searchParams.get('error'), 'provider_failed');
    const signature = await f.start();
    f.identity.badSignature = true;
    assert.equal((await f.callback(signature)).link.searchParams.get('error'), 'provider_failed');
  } finally { f.db.close(); }
});

test('friend imports require signed-in consent and are separate from ordinary social login', async () => {
  const f = fixture();
  try {
    const ordinary = await f.start();
    assert.equal(ordinary.url.searchParams.get('scope').includes('contacts'), false);
    const invalid = await f.request('/v2/oauth/google/start', { body: { challenge: 'a'.repeat(43), appState: 'a'.repeat(48), purpose: 'friends' } });
    assert.equal(invalid.status, 401);
    const contacts = await f.start('google', 'Bearer existing', 'friends');
    assert.ok(contacts.url.searchParams.get('scope').includes('contacts.readonly'));
    const session = await f.exchange(contacts, (await f.callback(contacts)).link);
    assert.equal(session.body.user.id, 'existing');
    assert.equal(session.body.purpose, 'friends');
    assert.equal(f.db.prepare("SELECT verified_email FROM oauth_identities WHERE provider='google'").get().verified_email, 'new@example.test');
    assert.equal(f.db.prepare('SELECT count(*) AS n FROM social_imports').get().n, 1);
    const facebook = await f.start('facebook', 'Bearer existing', 'friends');
    assert.ok(facebook.url.searchParams.get('scope').includes('user_friends'));
    f.identity.permissionDenied = true;
    assert.equal((await f.callback(facebook)).link.searchParams.get('error'), 'permission_required');
    assert.equal(f.db.prepare("SELECT count(*) AS n FROM social_imports WHERE provider='facebook'").get().n, 0);
  } finally { f.db.close(); }
});

test('existing emails are never silently merged; explicit authenticated linking is supported', async () => {
  const f = fixture();
  try {
    f.identity.email = 'owner@example.test';
    const unlinked = await f.start();
    assert.equal((await f.callback(unlinked)).link.searchParams.get('error'), 'link_required');
    assert.equal(f.db.prepare('SELECT count(*) AS count FROM users').get().count, 1);
    const linkFlow = await f.start('google', 'Bearer existing');
    const session = await f.exchange(linkFlow, (await f.callback(linkFlow)).link);
    assert.equal(session.body.user.id, 'existing');
    const providers = await f.request('/v2/oauth/providers', { authorization: 'Bearer existing' });
    assert.deepEqual(providers.body.linked, ['google']);
    const ordinaryLogin = await f.start();
    assert.equal((await f.exchange(ordinaryLogin, (await f.callback(ordinaryLogin)).link)).body.user.id, 'existing');
  } finally { f.db.close(); }
});

test('Facebook verifies app-scoped tokens; missing credentials fail closed', async () => {
  const f = fixture();
  try {
    const invalid = await f.start('facebook');
    f.identity.facebookApp = 'wrong-app';
    assert.equal((await f.callback(invalid)).link.searchParams.get('error'), 'provider_failed');
    f.identity.facebookApp = 'test-app';
    const valid = await f.start('facebook');
    const session = await f.exchange(valid, (await f.callback(valid)).link);
    assert.equal(session.status, 200);
    assert.equal(session.body.created, true);
  } finally { f.db.close(); }
  const disabled = fixture(false);
  try {
    assert.deepEqual((await disabled.request('/v2/oauth/providers')).body.providers, { google: false, facebook: false });
    assert.equal((await disabled.request('/v2/oauth/google/start', { body: {} })).status, 503);
  } finally { disabled.db.close(); }
});
