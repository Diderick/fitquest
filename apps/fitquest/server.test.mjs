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
  } finally {
    if (child && child.exitCode === null) await stop();
    rmSync(dir, { recursive: true, force: true });
  }
});
