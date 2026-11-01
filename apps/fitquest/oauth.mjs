import { createHash, randomBytes, randomUUID, createHmac, createPublicKey, verify } from 'node:crypto';
const digest = value => createHash('sha256').update(value).digest('hex');
const pkce = value => createHash('sha256').update(value).digest('base64url');
const random = () => randomBytes(32).toString('base64url');
const fail = (message, status = 400) => { throw Object.assign(new Error(message), { status }); };
export function oauth(db, reply, { body, rateLimit, sessionFor, createSession, friends, fetcher = fetch, env = process.env }) {
  db.exec(`CREATE TABLE IF NOT EXISTS oauth_identities (
    provider TEXT NOT NULL, subject TEXT NOT NULL, user_id TEXT NOT NULL REFERENCES users(id),
    PRIMARY KEY(provider,subject), UNIQUE(provider,user_id));
    CREATE TABLE IF NOT EXISTS oauth_flows (
    state_hash TEXT PRIMARY KEY, provider TEXT NOT NULL, challenge TEXT NOT NULL, app_state TEXT NOT NULL,
    nonce TEXT NOT NULL, link_user TEXT, expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS oauth_grants (
    code_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL, challenge TEXT NOT NULL, app_state TEXT NOT NULL,
    created_user INTEGER NOT NULL, expires INTEGER NOT NULL);`);
  for (const [table, column, definition] of [
    ['oauth_identities', 'verified_email', 'TEXT'],
    ['oauth_flows', 'purpose', "TEXT NOT NULL DEFAULT 'signin'"],
    ['oauth_grants', 'purpose', "TEXT NOT NULL DEFAULT 'signin'"],
    ['oauth_grants', 'provider', "TEXT NOT NULL DEFAULT ''"],
  ]) {
    if (!db.prepare(`PRAGMA table_info(${table})`).all().some(row => row.name === column)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
  db.exec('CREATE INDEX IF NOT EXISTS oauth_verified_email ON oauth_identities(provider,verified_email)');
  const base = env.OAUTH_REDIRECT_BASE ?? 'https://fitquest-api.northstarlabs.tech';
  if (!/^https:\/\/[^/?#]+$/.test(base)) throw new Error('OAUTH_REDIRECT_BASE must be an HTTPS origin');
  const providers = {
    google: Boolean(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET),
    facebook: Boolean(env.FACEBOOK_APP_ID && env.FACEBOOK_APP_SECRET && /^v\d+\.\d+$/.test(env.FACEBOOK_GRAPH_VERSION ?? '')),
  };
  const callback = provider => `${base}/v2/oauth/${provider}/callback`;
  const graph = `https://graph.facebook.com/${env.FACEBOOK_GRAPH_VERSION}`;
  let googleKeys;
  let keysExpire = 0;
  async function json(url, options = {}) {
    const response = await fetcher(url, { ...options, signal: AbortSignal.timeout(15000) });
    if (!response.ok) fail(response.status === 403 ? 'Provider permission is needed for this import.' : 'Provider authentication failed. Please try again.', response.status === 403 ? 403 : 502);
    return response.json();
  }
  async function googleIdentity(code, flow) {
    const tokens = await json('https://oauth2.googleapis.com/token', { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({
        code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET,
        redirect_uri: callback('google'), grant_type: 'authorization_code',
      }).toString() });
    if (typeof tokens.id_token !== 'string' || tokens.id_token.length > 20000) fail('Invalid Google identity.', 401);
    const parts = tokens.id_token.split('.');
    if (parts.length !== 3) fail('Invalid Google identity.', 401);
    let header, claims;
    try { header = JSON.parse(Buffer.from(parts[0], 'base64url')); claims = JSON.parse(Buffer.from(parts[1], 'base64url')); }
    catch { fail('Invalid Google identity.', 401); }
    if (header.alg !== 'RS256' || typeof header.kid !== 'string') fail('Invalid Google signature.', 401);
    if (!googleKeys || Date.now() >= keysExpire || !googleKeys.some(key => key.kid === header.kid)) {
      googleKeys = (await json('https://www.googleapis.com/oauth2/v3/certs')).keys;
      keysExpire = Date.now() + 3600000;
    }
    const jwk = googleKeys?.find(key => key.kid === header.kid && key.kty === 'RSA' && (!key.use || key.use === 'sig'));
    if (!jwk || !verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), createPublicKey({ key: jwk, format: 'jwk' }), Buffer.from(parts[2], 'base64url'))) fail('Invalid Google signature.', 401);
    const now = Math.floor(Date.now() / 1000);
    if (!['accounts.google.com', 'https://accounts.google.com'].includes(claims.iss)
      || claims.aud !== env.GOOGLE_CLIENT_ID || (claims.azp && claims.azp !== env.GOOGLE_CLIENT_ID)
      || !Number.isFinite(claims.exp) || claims.exp <= now || !Number.isFinite(claims.iat) || claims.iat > now + 60
      || claims.nonce !== flow.nonce || typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255) fail('Google identity expired or mismatched.', 401);
    return { subject: claims.sub, email: claims.email_verified === true ? claims.email : null, name: claims.name, accessToken: tokens.access_token };
  }
  async function facebookIdentity(code) {
    const tokens = await json(`${graph}/oauth/access_token`, { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({
        client_id: env.FACEBOOK_APP_ID, client_secret: env.FACEBOOK_APP_SECRET,
        redirect_uri: callback('facebook'), code,
      }).toString() });
    if (typeof tokens.access_token !== 'string') fail('Invalid Facebook identity.', 401);
    const debug = await json(`${graph}/debug_token?${new URLSearchParams({ input_token: tokens.access_token })}`, {
      headers: { Authorization: `Bearer ${env.FACEBOOK_APP_ID}|${env.FACEBOOK_APP_SECRET}` },
    });
    const data = debug.data;
    const now = Math.floor(Date.now() / 1000);
    if (!data?.is_valid || String(data.app_id) !== env.FACEBOOK_APP_ID || !data.user_id
      || !Number.isFinite(data.expires_at) || data.expires_at <= now
      || (data.data_access_expires_at && data.data_access_expires_at <= now)) fail('Facebook identity expired or mismatched.', 401);
    const profile = await json(`${graph}/me?${new URLSearchParams({ fields: 'id,name,email',
      appsecret_proof: createHmac('sha256', env.FACEBOOK_APP_SECRET).update(tokens.access_token).digest('hex') })}`,
      { headers: { Authorization: `Bearer ${tokens.access_token}` } });
    if (String(profile.id) !== String(data.user_id)) fail('Invalid Facebook identity.', 401);
    // Facebook email is not used to silently link an existing password account.
    return { subject: String(profile.id), email: profile.email, name: profile.name, accessToken: tokens.access_token };
  }
  function resolveUser(provider, identity, linkUser) {
    const linked = db.prepare('SELECT user_id FROM oauth_identities WHERE provider=? AND subject=?').get(provider, identity.subject);
    if (linked) {
      if (linkUser && linkUser !== linked.user_id) fail('This provider is already linked to another FitQuest account.', 409);
      return { id: linked.user_id, created: false };
    }
    if (linkUser) {
      const existing = db.prepare('SELECT 1 FROM oauth_identities WHERE provider=? AND user_id=?').get(provider, linkUser);
      if (existing) fail('This FitQuest account already has a different identity linked for this provider.', 409);
      db.prepare('INSERT INTO oauth_identities(provider,subject,user_id) VALUES (?,?,?)').run(provider, identity.subject, linkUser);
      return { id: linkUser, created: false };
    }
    const email = typeof identity.email === 'string' && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(identity.email) && identity.email.length <= 254
      ? identity.email.toLowerCase() : `${provider}.${digest(identity.subject)}@identity.fitquest.invalid`;
    if (db.prepare('SELECT 1 FROM users WHERE email=?').get(email)) fail('Sign in to your existing FitQuest account with its password, then link this provider from Account & sync.', 409);
    const id = randomUUID();
    const username = `athlete_${randomBytes(8).toString('hex')}`;
    db.prepare('INSERT INTO users VALUES (?,?,?,?,?,?)').run(id, email, username, randomBytes(16).toString('hex'), randomBytes(64).toString('hex'), Date.now());
    db.prepare('INSERT INTO oauth_identities(provider,subject,user_id) VALUES (?,?,?)').run(provider, identity.subject, id);
    return { id, created: true };
  }
  function redirect(res, values) {
    res.writeHead(303, { Location: `fitquest-auth://callback?${new URLSearchParams(values)}`,
      'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
    res.end();
  }
  return async function route(req, res, url) {
    if (!url.pathname.startsWith('/v2/oauth/')) return false;
    if (url.pathname === '/v2/oauth/providers' && req.method === 'GET') {
      const user = sessionFor(req);
      const linked = user ? db.prepare('SELECT provider FROM oauth_identities WHERE user_id=?').all(user.id).map(row => row.provider) : [];
      reply(res, 200, { providers, linked }); return true;
    }
    if (url.pathname === '/v2/oauth/exchange' && req.method === 'POST') {
      rateLimit(req);
      const input = await body(req);
      if (!input || typeof input.code !== 'string' || input.code.length > 100 || !/^[A-Za-z0-9._~-]{43,128}$/.test(input.verifier ?? '') || typeof input.appState !== 'string') fail('Invalid sign-in response.');
      const grant = db.prepare('SELECT * FROM oauth_grants WHERE code_hash=? AND expires>?').get(digest(input.code), Date.now());
      if (!grant || grant.challenge !== pkce(input.verifier) || grant.app_state !== input.appState) fail('Sign-in expired or was already used. Please try again.', 401);
      db.exec('BEGIN IMMEDIATE');
      try {
        db.prepare('DELETE FROM oauth_grants WHERE code_hash=?').run(digest(input.code));
        const session = createSession(db.prepare('SELECT * FROM users WHERE id=?').get(grant.user_id));
        db.exec('COMMIT');
        reply(res, 200, { ...session, created: Boolean(grant.created_user), purpose: grant.purpose, provider: grant.provider });
      } catch (error) { db.exec('ROLLBACK'); throw error; }
      return true;
    }
    const match = url.pathname.match(/^\/v2\/oauth\/(google|facebook)\/(start|callback)$/);
    if (!match) { reply(res, 404, { error: 'Not found' }); return true; }
    const [, provider, action] = match;
    if (!providers[provider]) fail(`${provider === 'google' ? 'Google' : 'Facebook'} sign-in is not configured yet. Email sign-in still works.`, 503);
    if (action === 'start' && req.method === 'POST') {
      rateLimit(req);
      const input = await body(req);
      if (!input || !/^[A-Za-z0-9_-]{43}$/.test(input.challenge ?? '') || !/^[a-f0-9]{48}$/.test(input.appState ?? '')) fail('Invalid sign-in request.');
      const user = sessionFor(req);
      if (req.headers.authorization && !user) fail('Sign in again before linking a provider.', 401);
      const purpose = input.purpose ?? 'signin';
      if (!['signin', 'friends'].includes(purpose)) fail('Invalid connection purpose.');
      if (purpose === 'friends' && (!user || !friends)) fail('Sign in to FitQuest before importing friends.', 401);
      const state = random(), nonce = random();
      db.prepare('DELETE FROM oauth_flows WHERE expires<?').run(Date.now());
      db.prepare('DELETE FROM oauth_grants WHERE expires<?').run(Date.now());
      db.prepare('INSERT INTO oauth_flows(state_hash,provider,challenge,app_state,nonce,link_user,expires,purpose) VALUES (?,?,?,?,?,?,?,?)').run(digest(state), provider, input.challenge, input.appState, nonce, user?.id ?? null, Date.now() + 600000, purpose);
      const authorization = new URL(provider === 'google' ? 'https://accounts.google.com/o/oauth2/v2/auth' : `https://www.facebook.com/${env.FACEBOOK_GRAPH_VERSION}/dialog/oauth`);
      authorization.search = new URLSearchParams({
        client_id: provider === 'google' ? env.GOOGLE_CLIENT_ID : env.FACEBOOK_APP_ID,
        redirect_uri: callback(provider), response_type: 'code', state,
        scope: provider === 'google' ? purpose === 'friends' ? 'openid email https://www.googleapis.com/auth/contacts.readonly' : 'openid email' : purpose === 'friends' ? 'public_profile,email,user_friends' : 'public_profile,email',
        ...(provider === 'google' ? { nonce, prompt: purpose === 'friends' ? 'consent select_account' : 'select_account' } : purpose === 'friends' ? { auth_type: 'rerequest' } : {}),
      });
      reply(res, 200, { authorizationUrl: authorization.toString() }); return true;
    }
    if (action === 'callback' && req.method === 'GET') {
      const state = url.searchParams.get('state') ?? '';
      const flow = db.prepare('SELECT * FROM oauth_flows WHERE state_hash=? AND provider=? AND expires>?').get(digest(state), provider, Date.now());
      if (!flow) fail('Sign-in expired. Return to FitQuest and try again.', 401);
      db.prepare('DELETE FROM oauth_flows WHERE state_hash=?').run(digest(state));
      if (url.searchParams.has('error')) { redirect(res, { state: flow.app_state, error: 'cancelled' }); return true; }
      try {
        const code = url.searchParams.get('code');
        if (!code || code.length > 10000) fail('Missing provider response.');
        const identity = provider === 'google' ? await googleIdentity(code, flow) : await facebookIdentity(code);
        const imported = flow.purpose === 'friends' ? await friends.collect(provider, identity.accessToken, json, graph,
          provider === 'facebook' ? createHmac('sha256', env.FACEBOOK_APP_SECRET).update(identity.accessToken).digest('hex') : '') : null;
        db.exec('BEGIN IMMEDIATE');
        try {
          const user = resolveUser(provider, identity, flow.link_user);
          if (provider === 'google') {
            db.prepare("UPDATE oauth_identities SET verified_email=? WHERE provider='google' AND subject=?").run(typeof identity.email === 'string' ? identity.email.trim().toLowerCase() : null, identity.subject);
          }
          if (imported) friends.saveMatches(user.id, provider, imported);
          const grant = random();
          db.prepare('INSERT INTO oauth_grants(code_hash,user_id,challenge,app_state,created_user,expires,purpose,provider) VALUES (?,?,?,?,?,?,?,?)').run(digest(grant), user.id, flow.challenge, flow.app_state, user.created ? 1 : 0, Date.now() + 120000, flow.purpose, provider);
          db.exec('COMMIT');
          redirect(res, { code: grant, state: flow.app_state });
        } catch (error) { db.exec('ROLLBACK'); throw error; }
      } catch (error) {
        redirect(res, { state: flow.app_state, error: error.status === 409 ? 'link_required' : error.status === 403 ? 'permission_required' : 'provider_failed' });
      }
      return true;
    }
    reply(res, 405, { error: 'Method not allowed' }); return true;
  };
}
