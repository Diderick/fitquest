import { randomBytes, randomUUID, scrypt as scryptCallback, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';
import { challengeApi } from './challenge_api.mjs';
import { oauth } from './oauth.mjs';
import { socialFriends } from './social_friends.mjs';
import { validProfileNutrition } from './profile_nutrition.mjs';
const scrypt = promisify(scryptCallback);
const hash = value => createHash('sha256').update(value).digest('hex');
const passwordHash = (password, salt) => scrypt(password, salt, 64, { N: 32768, r: 8, p: 1, maxmem: 64 * 1024 * 1024 });

export function accounts(db, reply) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      salt TEXT NOT NULL, password_hash TEXT NOT NULL, created INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), expires INTEGER NOT NULL);
    CREATE TABLE IF NOT EXISTS user_state (
      user_id TEXT NOT NULL REFERENCES users(id), key TEXT NOT NULL, value TEXT NOT NULL,
      version INTEGER NOT NULL, PRIMARY KEY(user_id,key));
    CREATE TABLE IF NOT EXISTS sync_receipts (
      user_id TEXT NOT NULL, op_id TEXT NOT NULL, created INTEGER NOT NULL, PRIMARY KEY(user_id,op_id));
    CREATE TABLE IF NOT EXISTS follows (
      follower TEXT NOT NULL REFERENCES users(id), following TEXT NOT NULL REFERENCES users(id),
      PRIMARY KEY(follower, following));
  `);
  const attempts = new Map();
  const friends = socialFriends(db, reply);
  const challenges = challengeApi(db, reply);
  const publicUser = user => ({ id: user.id, username: user.username });
  function createSession(user) {
    const session = randomBytes(32).toString('base64url');
    db.prepare('DELETE FROM sessions WHERE expires<?').run(Date.now());
    db.prepare('INSERT INTO sessions VALUES (?,?,?)').run(hash(session), user.id, Date.now() + 90 * 86400000);
    return { token: session, user: publicUser(user) };
  }
  function sessionFor(req) {
    const bearer = req.headers.authorization?.startsWith('Bearer ') ? req.headers.authorization.slice(7) : '';
    return db.prepare('SELECT users.* FROM sessions JOIN users ON users.id=sessions.user_id WHERE token_hash=? AND expires>?').get(hash(bearer), Date.now());
  }
  async function body(req) {
    if (!req.headers['content-type']?.startsWith('application/json')) throw Object.assign(new Error('Expected JSON'), { status: 415 });
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) throw Object.assign(new Error('Request too large'), { status: 413 });
      chunks.push(chunk);
    }
    try { return JSON.parse(Buffer.concat(chunks).toString()); }
    catch { throw Object.assign(new Error('Invalid JSON'), { status: 400 }); }
  }
  function rateLimit(req) {
    const now = Date.now();
    for (const [key, entry] of attempts) if (entry.reset < now) attempts.delete(key);
    const key = req.headers['cf-connecting-ip'] ?? req.socket.remoteAddress;
    const entry = attempts.get(key) ?? { count: 0, reset: now + 60000 };
    if (++entry.count > 15) throw Object.assign(new Error('Too many attempts. Try again in a minute.'), { status: 429 });
    attempts.set(key, entry);
  }
  const selectState = db.prepare('SELECT key,value,version FROM user_state WHERE user_id=?');
  const oauthRoute = oauth(db, reply, { body, rateLimit, sessionFor, createSession, friends });
  const state = userId => Object.fromEntries(selectState.all(userId).map(row => [row.key, { value: JSON.parse(row.value), version: row.version }]));
  const allowed = key => /^(fitquest\.activities\.v1|weekly_goal|appearance_mode|active_plan|community_(posts|joined|liked)|nutrition[\w.:-]*|bl_(start|current|joined)|body_fat|profile_gender|profile_photo_v1|ads_hidden|friend_discovery|challenge\.[\w-]+|challenge_join\.[\w-]+|challenge_result\.[\w-]+\.[\w-]+|steps\.[\w.-]+|following\/[\w-]+)$/.test(key);
  function validateValue(key, value) {
    if (!allowed(key)) return false;
    const specific = validProfileNutrition(key, value);
    if (specific !== undefined) return specific;
    if (key.startsWith('following/') || key === 'friend_discovery') return typeof value === 'boolean';
    if (['bl_start', 'bl_current', 'body_fat'].includes(key)) return value === null || (typeof value === 'number' && Number.isFinite(value) && value > 0 && value <= 500);
    return value === null || typeof value === 'string' || typeof value === 'boolean'
      || (typeof value === 'number' && Number.isFinite(value))
      || (Array.isArray(value) && value.every(item => typeof item === 'string'));
  }
  return async function route(req, res) {
    const url = new URL(req.url, 'http://localhost');
    if (friends.publicRoute(req, res, url)) return true;
    if (!url.pathname.startsWith('/v2/')) return false;
    try {
      if (await oauthRoute(req, res, url)) return true;
      if (['/v2/auth/register', '/v2/auth/login'].includes(url.pathname) && req.method === 'POST') {
        rateLimit(req);
        const input = await body(req);
        const email = typeof input?.email === 'string' ? input.email.trim().toLowerCase() : '';
        const password = input?.password;
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || typeof password !== 'string' || password.length < 12 || password.length > 128) {
          return reply(res, 400, { error: 'Use a valid email and a password of 12–128 characters.' }), true;
        }
        let user;
        if (url.pathname.endsWith('/register')) {
          const username = typeof input.username === 'string' ? input.username.trim() : '';
          if (!/^[a-zA-Z0-9_]{3,30}$/.test(username)) return reply(res, 400, { error: 'Username must be 3–30 letters, numbers or underscores.' }), true;
          const salt = randomBytes(16).toString('hex');
          const encoded = (await passwordHash(password, salt)).toString('hex');
          user = { id: randomUUID(), email, username };
          try {
            db.prepare('INSERT INTO users VALUES (?,?,?,?,?,?)').run(user.id, email, username, salt, encoded, Date.now());
          } catch (error) {
            if (error.code?.includes('CONSTRAINT') || error.message.includes('UNIQUE')) return reply(res, 409, { error: 'Email or username is already registered.' }), true;
            throw error;
          }
        } else {
          user = db.prepare('SELECT * FROM users WHERE email=?').get(email);
          const candidate = await passwordHash(password, user?.salt ?? '00000000000000000000000000000000');
          if (!user || !timingSafeEqual(candidate, Buffer.from(user.password_hash, 'hex'))) return reply(res, 401, { error: 'Email or password is incorrect.' }), true;
        }
        return reply(res, 200, createSession(user)), true;
      }
      const bearer = req.headers.authorization?.startsWith('Bearer ') ? req.headers.authorization.slice(7) : '';
      const session = db.prepare('SELECT users.* FROM sessions JOIN users ON users.id=sessions.user_id WHERE token_hash=? AND expires>?').get(hash(bearer), Date.now());
      if (!session) return reply(res, 401, { error: 'Sign in again to sync. Offline data is safe on this device.' }), true;
      if (await friends.route(req, res, url, session, body)) return true;
      if (url.pathname === '/v2/auth/logout' && req.method === 'POST') {
        db.prepare('DELETE FROM sessions WHERE token_hash=?').run(hash(bearer));
        return reply(res, 200, { ok: true }), true;
      }
      if (url.pathname === '/v2/me' && req.method === 'GET') return reply(res, 200, { user: publicUser(session) }), true;
      if (url.pathname === '/v2/sync' && req.method === 'POST') {
        const input = await body(req);
        if (!input || !Array.isArray(input.operations) || input.operations.length > 200 || input.operations.some(op => !op || typeof op.id !== 'string' || op.id.length > 100 || typeof op.key !== 'string' || op.key.length > 120 || !Number.isSafeInteger(op.base) || op.base < 0 || !validateValue(op.key, op.value))) {
          return reply(res, 400, { error: 'Invalid sync operations.' }), true;
        }
        const acknowledged = [], conflicts = [];
        db.exec('BEGIN IMMEDIATE');
        try {
          db.prepare('DELETE FROM sync_receipts WHERE created<?').run(Date.now() - 180 * 86400000);
          const priority = key => key.startsWith('following/') ? 0 : key.startsWith('challenge.') ? 1 : key.startsWith('challenge_join.') ? 2 : key.startsWith('challenge_result.') ? 4 : 3;
          for (const op of [...input.operations].sort((a, b) => priority(a.key) - priority(b.key))) {
            if (db.prepare('SELECT 1 FROM sync_receipts WHERE user_id=? AND op_id=?').get(session.id, op.id)) { acknowledged.push(op.id); continue; }
            challenges.validate(op.key, op.value, session.id);
            const current = db.prepare('SELECT version,value FROM user_state WHERE user_id=? AND key=?').get(session.id, op.key);
            if ((current?.version ?? 0) !== op.base) { conflicts.push(op.key); continue; }
            const count = db.prepare('SELECT count(*) AS count FROM user_state WHERE user_id=?').get(session.id).count;
            if (!current && count >= 5000) throw Object.assign(new Error('Account storage limit reached.'), { status: 413 });
            if (op.key.startsWith('following/')) {
              const target = op.key.slice(10);
              if (target === session.id || !db.prepare('SELECT 1 FROM users WHERE id=?').get(target)) throw Object.assign(new Error('Unknown person.'), { status: 400 });
              if (op.value) db.prepare('INSERT OR IGNORE INTO follows VALUES (?,?)').run(session.id, target);
              else db.prepare('DELETE FROM follows WHERE follower=? AND following=?').run(session.id, target);
            }
            db.prepare('INSERT INTO user_state VALUES (?,?,?,?) ON CONFLICT(user_id,key) DO UPDATE SET value=excluded.value,version=excluded.version').run(session.id, op.key, JSON.stringify(op.value), op.base + 1);
            db.prepare('INSERT INTO sync_receipts VALUES (?,?,?)').run(session.id, op.id, Date.now());
            acknowledged.push(op.id);
          }
          db.exec('COMMIT');
        } catch (error) { db.exec('ROLLBACK'); throw error; }
        return reply(res, 200, { acknowledged, conflicts, state: state(session.id) }), true;
      }
      if (url.pathname === '/v2/people' && req.method === 'GET') {
        const query = (url.searchParams.get('q') ?? '').trim();
        if (!/^[\w]{2,30}$/.test(query)) return reply(res, 200, { people: [] }), true;
        const people = db.prepare('SELECT id,username FROM users WHERE username LIKE ? ESCAPE \'\\\' AND id<>? ORDER BY username LIMIT 25').all(query.replaceAll('_', '\\_') + '%', session.id);
        return reply(res, 200, { people }), true;
      }
      if (url.pathname === '/v2/social' && req.method === 'GET') {
        const following = db.prepare('SELECT u.id,u.username FROM follows f JOIN users u ON u.id=f.following WHERE f.follower=? ORDER BY u.username').all(session.id);
        const followers = db.prepare('SELECT u.id,u.username FROM follows f JOIN users u ON u.id=f.follower WHERE f.following=? ORDER BY u.username').all(session.id);
        const posts = following.flatMap(user => {
          const raw = db.prepare("SELECT value FROM user_state WHERE user_id=? AND key='community_posts'").get(user.id);
          const list = raw ? JSON.parse(raw.value) : [];
          return Array.isArray(list) ? list.slice(0, 10).filter(text => typeof text === 'string').map(text => ({ username: user.username, text })) : [];
        }).slice(0, 100);
        return reply(res, 200, { following, followers, posts }), true;
      }
      if (challenges.route(req, res, url, session)) return true;
      reply(res, 404, { error: 'Not found' });
    } catch (error) {
      if (!res.headersSent) reply(res, error.status ?? 500, { error: error.status ? error.message : 'Server error' });
      if (!error.status) console.error('Account request failed:', error.message);
    }
    return true;
  };
}
