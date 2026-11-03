import http from 'node:http';
import { openDatabase } from './db.mjs';
import { createApiHandler } from './app_handler.mjs';

const token = process.env.FITQUEST_API_TOKEN;
const db = await openDatabase();
const handle = await createApiHandler({ db, token });

const server = http.createServer(async (req, res) => {
  await handle(req, res);
});

server.requestTimeout = 30000;
server.headersTimeout = 10000;
server.listen(Number(process.env.PORT ?? 8000), process.env.HOST ?? '127.0.0.1', () => console.log('FitQuest API listening'));

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(async () => {
    await db.close();
    process.exit(0);
  }));
}
