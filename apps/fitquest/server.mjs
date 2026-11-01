import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { accounts } from './accounts.mjs';

const token = process.env.FITQUEST_API_TOKEN;
if (!token || token.length < 32) throw new Error('FITQUEST_API_TOKEN must contain at least 32 characters');
const dbPath = process.env.FITQUEST_DB ?? './data/fitquest.sqlite';
mkdirSync(dirname(dbPath), { recursive: true });
const db = new DatabaseSync(dbPath);
db.exec('PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS activities (id INTEGER PRIMARY KEY CHECK (id = 1), revision INTEGER NOT NULL, payload TEXT NOT NULL)');
db.prepare("INSERT OR IGNORE INTO activities VALUES (1, 0, '[]')").run();
const read = db.prepare('SELECT revision, payload FROM activities WHERE id = 1');
const write = db.prepare('UPDATE activities SET revision = revision + 1, payload = ? WHERE id = 1 AND revision = ?');
const sports = new Set(['Swimming', 'Cycling', 'Running', 'Walking', 'Hiking', 'Strength', 'Rowing', 'Yoga', 'HIIT', 'Tennis']);
const validNumber = (n, min, max) => typeof n === 'number' && Number.isFinite(n) && n >= min && n <= max;
function validWorkout(w) {
  return w && sports.has(w.activity) && Number.isInteger(w.minutes) && w.minutes > 0 && w.minutes <= 10080
    && typeof w.date === 'string' && w.date.length <= 40 && Number.isFinite(Date.parse(w.date))
    && (w.distanceKm == null || validNumber(w.distanceKm, 0, 100000))
    && typeof w.notes === 'string' && w.notes.length <= 10000
    && Array.isArray(w.route) && w.route.length <= 50000
    && w.route.every(p => Array.isArray(p) && p.length === 2 && validNumber(p[0], -90, 90) && validNumber(p[1], -180, 180));
}
function reply(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers });
  res.end(JSON.stringify(body));
}
const accountRoute = accounts(db, reply);
const server = http.createServer(async (req, res) => {
  if (req.url === '/health' && req.method === 'GET') return reply(res, 200, { status: 'ok' });
  if (await accountRoute(req, res)) return;
  const supplied = Buffer.from(req.headers.authorization ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) {
    return reply(res, 401, { error: 'Unauthorized' });
  }
  if (req.url !== '/v1/activities') return reply(res, 404, { error: 'Not found' });
  try {
    if (req.method === 'GET') {
      const row = read.get();
      return reply(res, 200, { revision: row.revision, workouts: JSON.parse(row.payload) });
    }
    if (req.method !== 'PUT') return reply(res, 405, { error: 'Method not allowed' }, { Allow: 'GET, PUT' });
    if (!req.headers['content-type']?.startsWith('application/json')) return reply(res, 415, { error: 'Expected application/json' });
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 2 * 1024 * 1024) {
        reply(res, 413, { error: 'Request exceeds 2 MiB' });
        return;
      }
      chunks.push(chunk);
    }
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch { return reply(res, 400, { error: 'Invalid JSON' }); }
    if (!body || !Number.isSafeInteger(body.revision) || body.revision < 0 || !Array.isArray(body.workouts)
        || body.workouts.length > 10000 || !body.workouts.every(validWorkout)) {
      return reply(res, 400, { error: 'Invalid activity data' });
    }
    const result = write.run(JSON.stringify(body.workouts), body.revision);
    if (result.changes === 0) return reply(res, 409, { error: 'Activities changed on another device. Reload before saving.' });
    return reply(res, 200, { revision: body.revision + 1 });
  } catch (error) {
    console.error('Request failed:', error.message);
    if (!res.headersSent) reply(res, 500, { error: 'Server error' });
  }
});
server.requestTimeout = 30000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT ?? 8000), process.env.HOST ?? '127.0.0.1', () => console.log('FitQuest API listening'));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(() => { db.close(); process.exit(0); }));
