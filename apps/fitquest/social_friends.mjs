import { randomBytes } from 'node:crypto';
const fail = (message, status = 400) => { throw Object.assign(new Error(message), { status }); };
export function socialFriends(db, reply) {
  db.exec(`CREATE TABLE IF NOT EXISTS social_suggestions (
    user_id TEXT NOT NULL, provider TEXT NOT NULL, target_id TEXT NOT NULL, created INTEGER NOT NULL,
    PRIMARY KEY(user_id,provider,target_id));
    CREATE TABLE IF NOT EXISTS social_imports (
    user_id TEXT NOT NULL, provider TEXT NOT NULL, checked INTEGER NOT NULL, limited INTEGER NOT NULL,
    PRIMARY KEY(user_id,provider));
    CREATE TABLE IF NOT EXISTS friend_invites (
    code TEXT PRIMARY KEY, user_id TEXT NOT NULL UNIQUE);`);
  function discoverable(userId) {
    return db.prepare("SELECT 1 FROM user_state WHERE user_id=? AND key='friend_discovery' AND value='true'").get(userId);
  }
  async function collect(provider, accessToken, json, graph, appSecretProof) {
    if (typeof accessToken !== 'string') fail('Contact permission is needed.', 403);
    const subjects = new Set();
    let pageToken;
    let limited = false;
    if (provider === 'facebook') {
      const permissions = await json(`${graph}/me/permissions?${new URLSearchParams({ appsecret_proof: appSecretProof })}`, { headers: { Authorization: `Bearer ${accessToken}` } });
      if (!permissions.data?.some(p => p.permission === 'user_friends' && p.status === 'granted')) fail('Allow friend-list permission to import eligible Facebook friends.', 403);
    }
    // Read at most ten pages, without following provider-supplied arbitrary URLs.
    for (let page = 0; page < 10; page++) {
      const url = provider === 'google'
        ? `https://people.googleapis.com/v1/people/me/connections?${new URLSearchParams({ personFields: 'emailAddresses', pageSize: '1000', ...(pageToken ? { pageToken } : {}) })}`
        : `${graph}/me/friends?${new URLSearchParams({ fields: 'id', limit: '500', appsecret_proof: appSecretProof, ...(pageToken ? { after: pageToken } : {}) })}`;
      const data = await json(url, { headers: { Authorization: `Bearer ${accessToken}` } });
      if (provider === 'google') {
        for (const person of data.connections ?? []) {
          for (const email of person.emailAddresses ?? []) {
            if (typeof email.value === 'string' && email.value.length <= 254) subjects.add(email.value.trim().toLowerCase());
          }
        }
        pageToken = data.nextPageToken;
      } else {
        for (const friend of data.data ?? []) if (typeof friend.id === 'string' && friend.id.length <= 255) subjects.add(friend.id);
        pageToken = data.paging?.next ? data.paging?.cursors?.after : null;
      }
      if (subjects.size >= 10000) { limited = true; break; }
      if (!pageToken) break;
      if (page === 9) limited = true;
    }
    return { subjects, limited };
  }
  function saveMatches(userId, provider, imported) {
    // Google matches only verified Google emails; unverified password emails cannot impersonate a contact.
    const match = provider === 'google'
      ? db.prepare("SELECT user_id FROM oauth_identities WHERE provider='google' AND verified_email=?")
      : db.prepare("SELECT user_id FROM oauth_identities WHERE provider='facebook' AND subject=?");
    const targets = new Set();
    for (const subject of imported.subjects) {
      for (const row of match.all(subject)) if (row.user_id !== userId && discoverable(row.user_id)) targets.add(row.user_id);
    }
    db.prepare('DELETE FROM social_suggestions WHERE user_id=? AND provider=?').run(userId, provider);
    const insert = db.prepare('INSERT INTO social_suggestions VALUES (?,?,?,?)');
    for (const target of targets) insert.run(userId, provider, target, Date.now());
    db.prepare('INSERT INTO social_imports VALUES (?,?,?,?) ON CONFLICT(user_id,provider) DO UPDATE SET checked=excluded.checked,limited=excluded.limited').run(userId, provider, Date.now(), imported.limited ? 1 : 0);
  }
  function invite(code, challengeId) {
    if (!/^[A-Za-z0-9_-]{24}$/.test(code)) return null;
    const person = db.prepare('SELECT u.id,u.username FROM friend_invites i JOIN users u ON u.id=i.user_id WHERE i.code=?').get(code);
    if (!person) return null;
    let challenge = null;
    if (challengeId && /^[\w-]{1,64}$/.test(challengeId)) {
      const row = db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(person.id, `challenge.${challengeId}`);
      if (row) {
        const raw = JSON.parse(row.value);
        const value = typeof raw === 'string' ? JSON.parse(raw) : null;
        if (value?.visibility === 'followers') challenge = { ...value, ownerId: person.id, ownerName: person.username };
      }
    }
    return { person, challenge };
  }
  function publicRoute(req, res, url) {
    if (req.method !== 'GET' || !url.pathname.startsWith('/join/')) return false;
    const code = url.pathname.slice('/join/'.length);
    const info = invite(code, url.searchParams.get('challenge'));
    if (!info) { reply(res, 404, { error: 'Invitation not found.' }); return true; }
    const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
    const deepLink = `fitquest-auth://invite?${new URLSearchParams({ code, ...(info.challenge ? { challenge: info.challenge.id } : {}) })}`;
    const title = info.challenge ? `Join ${info.challenge.title}` : `Follow @${info.person.username}`;
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store',
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'", 'Referrer-Policy': 'no-referrer' });
    res.end(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escape(title)} · FitQuest</title></head><body style="margin:0;background:#0b1424;color:#f5f8fc;font:18px system-ui;padding:32px;max-width:640px"><p style="color:#20bbae">FITQUEST</p><h1>${escape(title)}</h1><p>@${escape(info.person.username)} invited you. Open FitQuest, sign in or create an account, then choose Follow${info.challenge ? ' &amp; join' : ''}.</p><p><a style="display:inline-block;padding:16px;background:#20bbae;color:#0b1424;border-radius:12px;text-decoration:none" href="${escape(deepLink)}">Open in FitQuest</a></p><p>If the app is not installed, install the FitQuest APK shared by your friend, then return to this link. You can also paste this invitation into Friends &amp; following.</p><p>Invitation code: <strong>${escape(code)}</strong></p><p>No one is followed or joined automatically.</p></body></html>`);
    return true;
  }
  async function route(req, res, url, session, body) {
    if (url.pathname === '/v2/friends/suggestions' && req.method === 'GET') {
      const people = db.prepare(`SELECT u.id,u.username,s.provider FROM social_suggestions s JOIN users u ON u.id=s.target_id
        JOIN user_state p ON p.user_id=u.id AND p.key='friend_discovery' AND p.value='true'
        WHERE s.user_id=? ORDER BY u.username LIMIT 500`).all(session.id);
      const imports = db.prepare('SELECT provider,checked,limited FROM social_imports WHERE user_id=?').all(session.id);
      reply(res, 200, { people, imports }); return true;
    }
    if (url.pathname === '/v2/friends/imports/clear' && req.method === 'POST') {
      const input = await body(req);
      if (!['google', 'facebook', 'all'].includes(input?.provider)) fail('Choose an import source.');
      if (input.provider === 'all') {
        db.prepare('DELETE FROM social_suggestions WHERE user_id=?').run(session.id);
        db.prepare('DELETE FROM social_imports WHERE user_id=?').run(session.id);
      } else {
        db.prepare('DELETE FROM social_suggestions WHERE user_id=? AND provider=?').run(session.id, input.provider);
        db.prepare('DELETE FROM social_imports WHERE user_id=? AND provider=?').run(session.id, input.provider);
      }
      reply(res, 200, { ok: true }); return true;
    }
    if (url.pathname === '/v2/friends/invite' && req.method === 'POST') {
      let row = db.prepare('SELECT code FROM friend_invites WHERE user_id=?').get(session.id);
      if (!row) {
        row = { code: randomBytes(18).toString('base64url') };
        db.prepare('INSERT INTO friend_invites VALUES (?,?)').run(row.code, session.id);
      }
      reply(res, 200, { code: row.code, username: session.username }); return true;
    }
    if (url.pathname.startsWith('/v2/friends/invites/') && req.method === 'GET') {
      const result = invite(url.pathname.slice('/v2/friends/invites/'.length), url.searchParams.get('challenge'));
      reply(res, result ? 200 : 404, result ?? { error: 'Invitation not found.' }); return true;
    }
    return false;
  }
  return { collect, saveMatches, route, publicRoute };
}
