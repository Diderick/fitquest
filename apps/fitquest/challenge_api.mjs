const fail = (message, status = 400) => { throw Object.assign(new Error(message), { status }); };
const identifier = value => typeof value === 'string' && /^[\w-]{1,64}$/.test(value);
const text = (value, max, required = false) => typeof value === 'string' && value.length <= max && (!required || value.trim().length > 0);
const day = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
const number = (value, metric) => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1000000
  && (metric !== 'seconds' || value > 0) && (!['seconds', 'reps', 'rounds'].includes(metric) || Number.isInteger(value));
const unpack = row => {
  if (!row) return null;
  const value = JSON.parse(row.value);
  return typeof value === 'string' ? JSON.parse(value) : value;
};
export function challengeApi(db, reply) {
  function find(id) {
    const row = db.prepare("SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id WHERE s.key=? AND s.value<>'null' LIMIT 1").get(`challenge.${id}`);
    const challenge = unpack(row);
    return challenge ? { ...challenge, ownerId: row.user_id, ownerName: row.username } : null;
  }
  function accessible(challenge, userId) {
    return challenge && (challenge.ownerId === userId || (challenge.visibility === 'followers'
      && db.prepare('SELECT 1 FROM follows WHERE follower=? AND following=?').get(userId, challenge.ownerId)));
  }
  function validate(key, value, userId) {
    if (!key.startsWith('challenge')) return;
    const parts = key.split('.');
    if (!identifier(parts[1])) fail('Invalid challenge ID.');
    if (parts[0] === 'challenge_join') {
      if (typeof value !== 'boolean') fail('Invalid participation choice.');
      if (value && !accessible(find(parts[1]), userId)) fail('Follow the creator before joining this shared challenge.', 403);
      return;
    }
    if (parts[0] === 'challenge_result' && value === null) return;
    if (typeof value !== 'string' || value.length > 40000) fail('Invalid challenge data.');
    let input;
    try { input = JSON.parse(value); } catch { fail('Invalid challenge JSON.'); }
    if (!input || typeof input !== 'object' || Array.isArray(input)) fail('Invalid challenge data.');
    if (parts[0] === 'challenge') {
      if (input.id !== parts[1] || !text(input.title, 80, true) || !['Custom', 'Military', 'CrossFit'].includes(input.category)
          || !text(input.instructions, 3000) || !day(input.startDate) || !day(input.endDate) || input.endDate < input.startDate
          || !['private', 'followers'].includes(input.visibility) || !Array.isArray(input.events) || input.events.length < 1 || input.events.length > 20
          || new Set(input.events.map(e => e?.id)).size !== input.events.length
          || input.events.some(e => !e || !identifier(e.id) || !text(e.name, 100, true) || !text(e.instructions, 1000)
            || !['reps', 'seconds', 'metres', 'kilograms', 'rounds'].includes(e.metric) || typeof e.higherWins !== 'boolean'
            || (e.target != null && !number(e.target, e.metric)))) fail('Invalid challenge rules or scoring.');
      const existing = find(input.id);
      if (existing && existing.ownerId !== userId) fail('This challenge ID is already in use.', 409);
      const own = db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(userId, key);
      if (own && JSON.stringify(unpack(own)) !== JSON.stringify(input)) fail('Create a new challenge to change saved scoring rules.');
      return;
    }
    if (parts[0] !== 'challenge_result' || !identifier(parts[2]) || input.id !== parts[2] || input.challengeId !== parts[1]) fail('Invalid result ID.');
    const challenge = find(parts[1]);
    if (!accessible(challenge, userId)) fail('This challenge is private or unavailable. Your offline result is still saved on your device.', 403);
    if (challenge.ownerId !== userId) {
      const joined = unpack(db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(userId, `challenge_join.${challenge.id}`));
      if (joined !== true) fail('Join this challenge before submitting a result.', 403);
    }
    const scores = input.scores;
    if (!day(input.date) || input.date < challenge.startDate || input.date > challenge.endDate
        || !['As prescribed', 'Scaled'].includes(input.division) || !text(input.notes, 2000)
        || typeof input.completed !== 'boolean' || !scores || typeof scores !== 'object' || Array.isArray(scores)
        || (input.completed && Object.keys(scores).length < 1) || (!input.completed && !input.notes.trim())
        || Object.entries(scores).some(([eventId, score]) => {
          const event = challenge.events.find(e => e.id === eventId);
          return !event || !number(score, event.metric);
        })) fail('Invalid test result. Check dates, units and exercise scores.');
  }
  function route(req, res, url, session) {
    if (req.method !== 'GET' || !url.pathname.startsWith('/v2/challenges')) return false;
    if (url.pathname === '/v2/challenges') {
      const rows = db.prepare(`SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id
        WHERE s.key LIKE 'challenge.%' AND s.value<>'null'
        AND (s.user_id=? OR s.user_id IN (SELECT following FROM follows WHERE follower=?))
        ORDER BY s.rowid DESC LIMIT 200`).all(session.id, session.id);
      const challenges = rows.map(row => ({ ...unpack(row), ownerId: row.user_id, ownerName: row.username }))
        .filter(challenge => accessible(challenge, session.id));
      reply(res, 200, { challenges });
      return true;
    }
    const id = url.pathname.slice('/v2/challenges/'.length);
    if (!identifier(id)) { reply(res, 404, { error: 'Challenge not found.' }); return true; }
    const challenge = find(id);
    if (!accessible(challenge, session.id)) { reply(res, 404, { error: 'Challenge not found.' }); return true; }
    const rows = db.prepare(`SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id
      WHERE s.key LIKE ? AND s.value<>'null' ORDER BY s.rowid DESC LIMIT 2000`).all(`challenge_result.${id}.%`);
    // Exact challengeId check also prevents SQL LIKE wildcard IDs from widening a query.
    const results = rows.map(row => ({ ...unpack(row), userId: row.user_id, username: row.username }))
      .filter(result => result.challengeId === id);
    reply(res, 200, { challenge, results });
    return true;
  }
  return { validate, route };
}
