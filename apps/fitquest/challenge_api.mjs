const fail = (message, status = 400) => { throw Object.assign(new Error(message), { status }); };
const identifier = value => typeof value === 'string' && /^[\w-]{1,64}$/.test(value);
const text = (value, max, required = false) => typeof value === 'string' && value.length <= max && (!required || value.trim().length > 0);
const day = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)
  && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
const number = (value, metric) => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1000000
  && (metric !== 'seconds' || value > 0) && (!['seconds', 'reps', 'rounds'].includes(metric) || Number.isInteger(value));
const CODE = /^[A-Z0-9]{8}$/;
const joinCode = challenge => typeof challenge?.joinCode === 'string' && CODE.test(challenge.joinCode);
const unpack = row => {
  if (!row) return null;
  const value = JSON.parse(row.value);
  return typeof value === 'string' ? JSON.parse(value) : value;
};

export function challengeApi(db, reply) {
  async function find(id) {
    const row = await db.prepare("SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id WHERE s.key=? AND s.value<>'null' LIMIT 1").get(`challenge.${id}`);
    const challenge = unpack(row);
    return challenge ? { ...challenge, ownerId: row.user_id, ownerName: row.username } : null;
  }

  async function hasJoined(challenge, userId) {
    const row = await db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(userId, `challenge_join.${challenge.id}`);
    return unpack(row) === true;
  }

  // Members who joined with the creator's join code do not need to follow the creator.
  async function accessible(challenge, userId) {
    return challenge && (challenge.ownerId === userId || (challenge.visibility === 'followers'
      && await db.prepare('SELECT 1 FROM follows WHERE follower=? AND following=?').get(userId, challenge.ownerId))
      || (joinCode(challenge) && await hasJoined(challenge, userId)));
  }

  async function findByCode(code) {
    const rows = await db.prepare("SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id WHERE s.key LIKE 'challenge.%' AND s.value LIKE ? LIMIT 20").all(`%${code}%`);
    for (const row of rows) {
      const challenge = unpack(row);
      if (challenge && challenge.joinCode === code) return { ...challenge, ownerId: row.user_id, ownerName: row.username };
    }
    return null;
  }

  async function validate(key, value, userId) {
    if (!key.startsWith('challenge')) return;
    const parts = key.split('.');
    if (!identifier(parts[1])) fail('Invalid challenge ID.');
    if (parts[0] === 'challenge_join') {
      if (typeof value !== 'boolean') fail('Invalid participation choice.');
      if (value) {
        const target = await find(parts[1]);
        const codeJoin = joinCode(target);
        if (!codeJoin && !(await accessible(target, userId))) fail('Follow the creator before joining this shared challenge.', 403);
      }
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
          || !['private', 'followers'].includes(input.visibility)
          || (input.joinCode != null && (typeof input.joinCode !== 'string' || !CODE.test(input.joinCode))) || !Array.isArray(input.events) || input.events.length < 1 || input.events.length > 20
          || new Set(input.events.map(e => e?.id)).size !== input.events.length
          || input.events.some(e => !e || !identifier(e.id) || !text(e.name, 100, true) || !text(e.instructions, 1000)
            || !['reps', 'seconds', 'metres', 'kilograms', 'rounds'].includes(e.metric) || typeof e.higherWins !== 'boolean'
            || (e.target != null && !number(e.target, e.metric)))) fail('Invalid challenge rules or scoring.');
      const existing = await find(input.id);
      if (existing && existing.ownerId !== userId) fail('This challenge ID is already in use.', 409);
      const own = await db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(userId, key);
      const rules = currentValue => { const { visibility, joinCode: ignored, ...protocol } = currentValue; return JSON.stringify(protocol); };
      if (own && rules(unpack(own)) !== rules(input)) fail('Create a new challenge to change saved scoring rules.');
      return;
    }
    if (parts[0] !== 'challenge_result' || !identifier(parts[2]) || input.id !== parts[2] || input.challengeId !== parts[1]) fail('Invalid result ID.');
    const challenge = await find(parts[1]);
    if (!(await accessible(challenge, userId))) fail('This challenge is private or unavailable. Your offline result is still saved on your device.', 403);
    if (challenge.ownerId !== userId) {
      const joined = unpack(await db.prepare('SELECT value FROM user_state WHERE user_id=? AND key=?').get(userId, `challenge_join.${challenge.id}`));
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

  async function route(req, res, url, session) {
    if (req.method !== 'GET' || !url.pathname.startsWith('/v2/challenges')) return false;
    if (url.pathname === '/v2/challenges') {
      const rows = await db.prepare(`SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id
        WHERE s.key LIKE 'challenge.%' AND s.value<>'null'
        AND (s.user_id=? OR s.user_id IN (SELECT following FROM follows WHERE follower=?))
        ORDER BY s.version DESC LIMIT 200`).all(session.id, session.id);
      const hydrated = await Promise.all(rows.map(async row => ({ ...unpack(row), ownerId: row.user_id, ownerName: row.username, accessible: await accessible({ ...unpack(row), ownerId: row.user_id }, session.id) })));
      const challenges = hydrated.filter(challenge => challenge.accessible).map(({ accessible: ignored, ...challenge }) => challenge);
      const joinedRows = await db.prepare("SELECT key,value FROM user_state WHERE user_id=? AND key LIKE 'challenge_join.%' LIMIT 200").all(session.id);
      for (const row of joinedRows) {
        if (unpack(row) !== true) continue;
        const id = row.key.slice('challenge_join.'.length);
        if (challenges.some(c => c.id === id)) continue;
        const challenge = await find(id);
        if (challenge && joinCode(challenge)) challenges.push(challenge);
      }
      reply(res, 200, { challenges });
      return true;
    }
    if (url.pathname.startsWith('/v2/challenges/code/')) {
      const code = url.pathname.slice('/v2/challenges/code/'.length).toUpperCase();
      const challenge = CODE.test(code) ? await findByCode(code) : null;
      if (!challenge) { reply(res, 404, { error: 'No challenge matches that code.' }); return true; }
      reply(res, 200, { challenge });
      return true;
    }
    const id = url.pathname.slice('/v2/challenges/'.length);
    if (!identifier(id)) { reply(res, 404, { error: 'Challenge not found.' }); return true; }
    const challenge = await find(id);
    if (!(await accessible(challenge, session.id))) { reply(res, 404, { error: 'Challenge not found.' }); return true; }
    const rows = await db.prepare(`SELECT s.*,u.username FROM user_state s JOIN users u ON u.id=s.user_id
      WHERE s.key LIKE ? AND s.value<>'null' ORDER BY s.version DESC LIMIT 2000`).all(`challenge_result.${id}.%`);
    const results = rows.map(row => ({ ...unpack(row), userId: row.user_id, username: row.username }))
      .filter(result => result.challengeId === id);
    reply(res, 200, { challenge, results });
    return true;
  }

  return { validate, route };
}
