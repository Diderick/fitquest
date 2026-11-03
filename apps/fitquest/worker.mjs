import { createApiHandler } from './app_handler.mjs';
import { openDatabase } from './db.mjs';

let handlerPromise;

function syncWorkerEnv(env) {
  if (typeof process === 'undefined' || !process.env) return;
  for (const key of [
    'FITQUEST_API_TOKEN',
    'FITQUEST_DATABASE_URL',
    'OAUTH_REDIRECT_BASE',
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'FACEBOOK_APP_ID',
    'FACEBOOK_APP_SECRET',
    'FACEBOOK_GRAPH_VERSION',
  ]) {
    if (typeof env[key] === 'string') process.env[key] = env[key];
  }
}

async function getHandler(env) {
  if (!handlerPromise) {
    syncWorkerEnv(env);
    const databaseUrl = env.FITQUEST_DATABASE_URL ?? env.FITQUEST_HYPERDRIVE?.connectionString;
    const token = env.FITQUEST_API_TOKEN;
    const db = await openDatabase({ connectionString: databaseUrl });
    handlerPromise = createApiHandler({ db, token });
  }
  return handlerPromise;
}

function createNodeLikeRequest(request) {
  const url = new URL(request.url);
  const headers = Object.fromEntries(Array.from(request.headers.entries(), ([key, value]) => [key.toLowerCase(), value]));
  let bufferedBody;
  const readBody = async () => {
    if (bufferedBody == null) bufferedBody = Buffer.from(await request.arrayBuffer());
    return bufferedBody;
  };
  return {
    method: request.method,
    url: `${url.pathname}${url.search}`,
    headers,
    socket: { remoteAddress: headers['cf-connecting-ip'] ?? headers['x-forwarded-for'] ?? '0.0.0.0' },
    async *[Symbol.asyncIterator]() {
      const body = await readBody();
      if (body.length > 0) yield body;
    },
  };
}

function createNodeLikeResponse() {
  const state = {
    status: 200,
    headers: {},
    headersSent: false,
    body: [],
    ended: false,
  };

  return {
    get headersSent() {
      return state.headersSent;
    },
    writeHead(status, headers = {}) {
      state.status = status;
      state.headers = { ...state.headers, ...headers };
      state.headersSent = true;
      return this;
    },
    end(payload = '') {
      if (!state.headersSent) this.writeHead(state.status, state.headers);
      const chunk = Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload));
      state.body.push(chunk);
      state.ended = true;
      return this;
    },
    toResponse() {
      const body = state.body.length === 0 ? null : Buffer.concat(state.body);
      return new Response(body, { status: state.status, headers: state.headers });
    },
    ensureEnded() {
      if (!state.ended) this.end('');
    },
  };
}

export default {
  async fetch(request, env) {
    const handler = await getHandler(env);
    const req = createNodeLikeRequest(request);
    const res = createNodeLikeResponse();
    await handler(req, res);
    res.ensureEnded();
    return res.toResponse();
  },
};
