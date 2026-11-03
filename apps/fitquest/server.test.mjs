import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';

test('authentication, validation, conflict detection and persistence', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fitquest-'));
  const token = 'test-token-'.repeat(6);
  const port = 18000 + Math.floor(Math.random() * 10000);
  const base = `http://127.0.0.1:${port}`;
  const headers = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  let child;
  async function start() {
    child = spawn(process.execPath, ['server.mjs'], {
      cwd: new URL('.', import.meta.url),
      env: { ...process.env, PORT: String(port), HOST: '127.0.0.1', FITQUEST_API_TOKEN: token, FITQUEST_DB: join(dir, 'test.sqlite') },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await Promise.race([
      once(child.stdout, 'data'),
      once(child, 'exit').then(([code]) => { throw new Error(`Server exited: ${code}`); }),
      new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('Startup timed out')), 10000); timer.unref(); }),
    ]);
  }
  async function stop() {
    const done = once(child, 'exit');
    child.kill();
    await done;
  }
  const get = () => fetch(`${base}/v1/activities`, { headers });
  const put = (body) => fetch(`${base}/v1/activities`, { method: 'PUT', headers, body: JSON.stringify(body) });
  try {
    await start();
    assert.equal((await fetch(`${base}/health`)).status, 200);
    assert.equal((await fetch(`${base}/v1/activities`)).status, 401);
    assert.deepEqual(await (await get()).json(), { revision: 0, workouts: [] });
    assert.equal((await put({ revision: 0, workouts: [{ activity: 'invalid' }] })).status, 400);
    const workouts = [{ activity: 'Running', minutes: 30, date: '2026-11-01T10:00:00Z', distanceKm: 5, notes: 'Test', route: [[-26, 28]] }];
    assert.equal((await put({ revision: 0, workouts })).status, 200);
    assert.equal((await put({ revision: 0, workouts: [] })).status, 409);
    assert.equal((await put({ revision: 1, workouts: [{ ...workouts[0], route: [[91, 0]] }] })).status, 400);
    await stop();
    await start();
    assert.deepEqual(await (await get()).json(), { revision: 1, workouts });
    assert.equal((await put({ revision: 1, workouts: [] })).status, 200);
    assert.deepEqual(await (await get()).json(), { revision: 2, workouts: [] });
    const api = (path, token, data) => fetch(`${base}${path}`, {
      method: data ? 'POST' : 'GET',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}),
    });
    const register = (email, username) => api('/v2/auth/register', null, { email, username, password: 'a long test password 123' });
    const alice = await (await register('alice@example.test', 'Alice_test')).json();
    const bob = await (await register('bob@example.test', 'Bob_test')).json();
    assert.ok(alice.token && bob.token);
    assert.equal((await register('alice@example.test', 'OtherUser')).status, 409);
    assert.equal((await api('/v2/auth/login', null, { email: 'alice@example.test', password: 'wrong password 123' })).status, 401);
    assert.equal((await api('/v2/auth/login', null, { email: 'alice@example.test', password: 'a long test password 123' })).status, 200);
    assert.equal((await api('/v2/sync', null, { operations: [] })).status, 401);
    const op = { id: 'first-operation', key: 'bl_start', value: 95.5, base: 0 };
    const sync = (token, operations) => api('/v2/sync', token, { operations });
    const saved = await (await sync(alice.token, [op])).json();
    assert.deepEqual(saved.acknowledged, [op.id]);
    assert.equal(saved.state.bl_start.value, 95.5);
    assert.equal(saved.state.bl_current, undefined);
    assert.equal((await sync(alice.token, [{ id: 'appearance', key: 'appearance_mode', value: 'dark', base: 0 }])).status, 200);
    const duplicate = await (await sync(alice.token, [op])).json();
    assert.equal(duplicate.state.bl_start.version, 1);
    const conflict = await (await sync(alice.token, [{ ...op, id: 'conflict', value: 80 }])).json();
    assert.deepEqual(conflict.conflicts, ['bl_start']);
    assert.equal(conflict.state.bl_start.value, 95.5);
    const privateState = await (await sync(bob.token, [])).json();
    assert.deepEqual(privateState.state, {});
    const search = await (await api('/v2/people?q=Alice_', bob.token)).json();
    assert.equal(search.people[0].id, alice.user.id);
    assert.equal(search.people[0].email, undefined);
    await sync(bob.token, [{ id: 'follow', key: `following/${alice.user.id}`, value: true, base: 0 }]);
    await sync(alice.token, [{ id: 'post', key: 'community_posts', value: ['An offline post'], base: 0 }]);
    const social = await (await api('/v2/social', bob.token)).json();
    assert.equal(social.following[0].id, alice.user.id);
    assert.equal(social.posts[0].text, 'An offline post');
    assert.equal(social.bl_start, undefined);
    await sync(bob.token, [{ id: 'unfollow', key: `following/${alice.user.id}`, value: false, base: 1 }]);
    assert.equal((await (await api('/v2/social', bob.token)).json()).following.length, 0);
    const definition = { id: 'military-test', title: 'Custom unit fitness test', category: 'Military', instructions: 'Personal practice protocol.',
      startDate: '2026-11-01', endDate: '2026-12-01', visibility: 'followers',
      events: [{ id: 'pushups', name: 'Push-ups', metric: 'reps', higherWins: true, target: 40, instructions: '2 minutes' },
        { id: 'run', name: 'Run', metric: 'seconds', higherWins: false, target: 900, instructions: '2.4 km' }] };
    const challengeOp = { id: 'create-challenge', key: 'challenge.military-test', value: JSON.stringify(definition), base: 0 };
    assert.equal((await sync(alice.token, [challengeOp])).status, 200);
    assert.equal((await (await api('/v2/challenges', bob.token)).json()).challenges.length, 0);
    assert.equal((await api('/v2/challenges/military-test', bob.token)).status, 404);
    const result = { id: 'attempt1', challengeId: definition.id, date: '2026-11-02', division: 'As prescribed', notes: '', completed: true, scores: { pushups: 45, run: 875 } };
    const resultOp = { id: 'record-challenge-result', key: 'challenge_result.military-test.attempt1', value: JSON.stringify(result), base: 0 };
    assert.equal((await sync(bob.token, [resultOp])).status, 403);
    // Dependency ordering must work even if an offline result precedes follow/join in the batch.
    assert.equal((await sync(bob.token, [resultOp,
      { id: 'join-challenge', key: 'challenge_join.military-test', value: true, base: 0 },
      { id: 'refollow', key: `following/${alice.user.id}`, value: true, base: 2 },
    ])).status, 200);
    assert.equal((await (await api('/v2/challenges', bob.token)).json()).challenges[0].id, definition.id);
    const board = await (await api('/v2/challenges/military-test', alice.token)).json();
    assert.equal(board.results[0].userId, bob.user.id);
    assert.equal(board.results[0].scores.run, 875);
    assert.equal((await sync(bob.token, [{ ...resultOp, id: 'bad-result', key: 'challenge_result.military-test.bad', value: JSON.stringify({ ...result, id: 'bad', scores: { pushups: -1 } }) }])).status, 400);
    assert.equal((await sync(bob.token, [{ ...resultOp, id: 'bad-date', key: 'challenge_result.military-test.date', value: JSON.stringify({ ...result, id: 'date', date: '2026-12-02' }) }])).status, 400);
    assert.equal((await sync(bob.token, [{ ...challengeOp, id: 'steal' }])).status, 409);
    const privateChallenge = { ...definition, id: 'private-test', visibility: 'private' };
    assert.equal((await sync(alice.token, [{ ...challengeOp, id: 'private', key: 'challenge.private-test', value: JSON.stringify(privateChallenge) }])).status, 200);
    assert.equal((await api('/v2/challenges/private-test', bob.token)).status, 404);
    assert.equal((await sync(alice.token, [{ id: 'share-private', key: 'challenge.private-test', value: JSON.stringify({ ...privateChallenge, visibility: 'followers' }), base: 1 }])).status, 200);
    assert.equal((await api('/v2/challenges/private-test', bob.token)).status, 200);
    assert.equal((await sync(alice.token, [{ id: 'change-protocol', key: 'challenge.private-test', value: JSON.stringify({ ...privateChallenge, title: 'Changed protocol', visibility: 'followers' }), base: 2 }])).status, 400);
    assert.equal((await sync(alice.token, [{ id: 'hide-private', key: 'challenge.private-test', value: JSON.stringify(privateChallenge), base: 2 }])).status, 200);
    assert.equal((await api('/v2/challenges/private-test', bob.token)).status, 404);
    assert.equal((await sync(bob.token, [{ id: 'delete-attempt', key: resultOp.key, value: null, base: 1 }])).status, 200);
    assert.equal((await (await api('/v2/challenges/military-test', alice.token)).json()).results.length, 0);
    const coded = { ...definition, id: 'coded-test', visibility: 'private', joinCode: 'ABCD2345' };
    assert.equal((await sync(alice.token, [{ id: 'coded', key: 'challenge.coded-test', value: JSON.stringify(coded), base: 0 }])).status, 200);
    assert.equal((await api('/v2/challenges/coded-test', bob.token)).status, 404);
    assert.equal((await api('/v2/challenges/code/ZZZZ9999', bob.token)).status, 404);
    assert.equal((await (await api('/v2/challenges/code/abcd2345', bob.token)).json()).challenge.id, 'coded-test');
    assert.equal((await sync(bob.token, [{ id: 'join-coded', key: 'challenge_join.coded-test', value: true, base: 0 }])).status, 200);
    const codedResult = { ...result, id: 'coded1', challengeId: 'coded-test' };
    assert.equal((await sync(bob.token, [{ id: 'coded-result', key: 'challenge_result.coded-test.coded1', value: JSON.stringify(codedResult), base: 0 }])).status, 200);
    const codedBoard = await (await api('/v2/challenges/coded-test', alice.token)).json();
    assert.equal(codedBoard.results[0].userId, bob.user.id);
    assert.ok((await (await api('/v2/challenges', bob.token)).json()).challenges.some(c => c.id === 'coded-test'));
    await stop(); await start();
    assert.equal((await (await sync(alice.token, [])).json()).state.bl_start.value, 95.5);
    await api('/v2/auth/logout', alice.token, {});
    assert.equal((await api('/v2/me', alice.token)).status, 401);
  } finally {
    if (child && child.exitCode === null) await stop();
    rmSync(dir, { recursive: true, force: true });
  }
});
