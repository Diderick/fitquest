// Run inside the API container. Creates and removes only uniquely named fixtures.
import assert from 'node:assert/strict';
import { randomUUID, randomBytes } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
const base = process.env.FITQUEST_SMOKE_URL ?? 'https://fitquest-api.northstarlabs.tech';
const created = [];
function cleanup(users) {
  const db = new DatabaseSync(process.env.FITQUEST_DB ?? '/data/fitquest.sqlite');
  db.exec('BEGIN IMMEDIATE');
  try {
    for (const user of users) {
      const row = db.prepare('SELECT username,email FROM users WHERE id=?').get(user.id);
      assert.ok(row.username.startsWith('smoke_') && row.email.endsWith('@example.invalid'));
      for (const table of ['sessions', 'user_state', 'sync_receipts']) db.prepare(`DELETE FROM ${table} WHERE user_id=?`).run(user.id);
      db.prepare('DELETE FROM follows WHERE follower=? OR following=?').run(user.id, user.id);
      db.prepare('DELETE FROM users WHERE id=?').run(user.id);
    }
    db.exec('COMMIT');
    console.log('Removed temporary smoke-test accounts');
  } catch (error) { db.exec('ROLLBACK'); throw error; }
  finally { db.close(); }
}
if (process.argv.includes('--cleanup')) {
  cleanup(JSON.parse(readFileSync(0, 'utf8')));
  process.exit(0);
}
async function request(path, token, data) {
  const response = await fetch(base + path, {
    method: data ? 'POST' : 'GET',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(data ? { body: JSON.stringify(data) } : {}), signal: AbortSignal.timeout(20000),
  });
  assert.equal(response.status, 200, `HTTP ${response.status} for ${path}`);
  return response.json();
}
try {
  for (let i = 0; i < 2; i++) {
    const id = randomUUID().replaceAll('-', '').slice(0, 16);
    const input = { email: `smoke_${id}@example.invalid`, username: `smoke_${id}`, password: randomBytes(24).toString('hex') };
    const session = await request('/v2/auth/register', null, input);
    created.push(session);
    const loggedIn = await request('/v2/auth/login', null, input);
    assert.equal(loggedIn.user.id, session.user.id);
  }
  const [alice, bob] = created;
  const operations = [
    { id: randomUUID(), key: 'bl_start', value: 95, base: 0 },
    { id: randomUUID(), key: `following/${bob.user.id}`, value: true, base: 0 },
  ];
  const sync = await request('/v2/sync', alice.token, { operations });
  assert.equal(sync.acknowledged.length, 2);
  assert.equal(sync.state.bl_start.value, 95);
  assert.equal(sync.state.bl_current, undefined);
  assert.equal(Object.keys((await request('/v2/sync', bob.token, { operations: [] })).state).length, 0);
  assert.equal((await request('/v2/social', bob.token)).followers[0].id, alice.user.id);
  const challengeId = randomUUID();
  const definition = { id: challengeId, title: 'Temporary fitness test', category: 'Military', instructions: 'Smoke test',
    startDate: '2020-01-01', endDate: '2099-12-31', visibility: 'followers',
    events: [{ id: 'pushups', name: 'Push-ups', instructions: '2 minutes', metric: 'reps', higherWins: true, target: 20 }] };
  await request('/v2/sync', bob.token, { operations: [{ id: randomUUID(), key: `challenge.${challengeId}`, value: JSON.stringify(definition), base: 0 }] });
  assert.ok((await request('/v2/challenges', alice.token)).challenges.some(c => c.id === challengeId));
  const resultId = randomUUID();
  await request('/v2/sync', alice.token, { operations: [
    { id: randomUUID(), key: `challenge_join.${challengeId}`, value: true, base: 0 },
    { id: randomUUID(), key: `challenge_result.${challengeId}.${resultId}`, base: 0,
      value: JSON.stringify({ id: resultId, challengeId, date: new Date().toISOString().slice(0, 10), division: 'As prescribed', notes: '', completed: true, scores: { pushups: 25 } }) },
  ] });
  const board = await request(`/v2/challenges/${challengeId}`, bob.token);
  assert.equal(board.results[0].userId, alice.user.id);
  assert.equal(board.results[0].scores.pushups, 25);
  console.log('Live HTTPS accounts, private sync, following, challenge creation, joining and results checks passed');
} finally {
  if (process.env.FITQUEST_SMOKE_SSH === '1') {
    const output = execFileSync('ssh', ['-o', 'BatchMode=yes', 'ssh.northstarlabs.tech',
      'cd ~/apps/fitquest && docker compose exec -T api node /tmp/fitquest-smoke.mjs --cleanup'],
      { input: JSON.stringify(created.map(s => s.user)), encoding: 'utf8' });
    console.log(output.trim());
  } else cleanup(created.map(s => s.user));
}
