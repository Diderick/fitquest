import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validProfileNutrition as valid } from './profile_nutrition.mjs';

test('gender and photo sync accept only supported values and bounded PNG thumbnails', () => {
  for (const gender of ['male', 'female', 'other', null]) assert.equal(valid('profile_gender', gender), true);
  assert.equal(valid('profile_gender', 'invalid'), false);
  const photo = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxuYAAAAASUVORK5CYII=';
  assert.equal(valid('profile_photo_v1', photo), true);
  assert.equal(valid('profile_photo_v1', 'not-an-image'), false);
  const oversized = Buffer.from(photo, 'base64'); oversized.writeUInt32BE(4000, 16);
  assert.equal(valid('profile_photo_v1', oversized.toString('base64')), false);
  assert.equal(valid('profile_photo_v1', null), true);
});
test('nutrition sync validates dates, times, portions, zero-calorie drinks and per-day goals', () => {
  const entry = { id: 'water', name: 'Water', kind: 'drink', portion: '250 ml', calories: 0, date: '2026-11-02', time: '10:15', legacy: false };
  const check = value => valid('nutrition_entry.water', JSON.stringify(value));
  assert.equal(check(entry), true);
  assert.equal(check({ ...entry, date: '2026-02-31' }), false);
  assert.equal(check({ ...entry, time: '24:00' }), false);
  assert.equal(check({ ...entry, calories: -1 }), false);
  assert.equal(check({ ...entry, id: 'someone-else' }), false);
  assert.equal(check({ ...entry, date: null, time: null }), false);
  assert.equal(check({ ...entry, date: null, time: null, legacy: true }), true);
  assert.equal(valid('nutrition_entry.water', null), true);
  assert.equal(valid('nutrition_goal.2026-11-02', 2200), true);
  assert.equal(valid('nutrition_goal.2026-02-31', 2200), false);
  assert.equal(valid('nutrition_goal.2026-11-02', 0), false);
});
