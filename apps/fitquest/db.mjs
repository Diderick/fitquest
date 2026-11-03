import pg from 'pg';

const { Pool } = pg;

function normalizeSql(sql) {
  let text = sql.replace(/\bBEGIN\s+IMMEDIATE\b/gi, 'BEGIN');
  text = text.replace(/\s+COLLATE\s+NOCASE/gi, '');
  text = text.replace(/INSERT\s+OR\s+IGNORE\s+INTO\s+([^\s(]+)\s+VALUES\s*\(([^)]*)\)/gi, 'INSERT INTO $1 VALUES ($2) ON CONFLICT DO NOTHING');
  let index = 0;
  text = text.replace(/\?/g, () => `$${++index}`);
  return text;
}

function createInterface(query) {
  return {
    prepare(sql) {
      const text = normalizeSql(sql);
      return {
        async get(...params) {
          const result = await query(text, params);
          return result.rows[0];
        },
        async all(...params) {
          const result = await query(text, params);
          return result.rows;
        },
        async run(...params) {
          const result = await query(text, params);
          return { changes: result.rowCount ?? 0 };
        },
      };
    },
    async exec(sql) {
      await query(normalizeSql(sql), []);
    },
  };
}

async function createSqliteInterface(path) {
  const [{ DatabaseSync }, { mkdirSync }, { dirname }] = await Promise.all([
    import('node:sqlite'),
    import('node:fs'),
    import('node:path'),
  ]);
  mkdirSync(dirname(path), { recursive: true });
  const sqlite = new DatabaseSync(path);
  const api = {
    dialect: 'sqlite',
    prepare(sql) {
      const statement = sqlite.prepare(sql);
      return {
        async get(...params) { return statement.get(...params); },
        async all(...params) { return statement.all(...params); },
        async run(...params) { return statement.run(...params); },
      };
    },
    async exec(sql) {
      sqlite.exec(sql);
    },
    async transaction(work) {
      sqlite.exec('BEGIN IMMEDIATE');
      try {
        const result = await work(api);
        sqlite.exec('COMMIT');
        return result;
      } catch (error) {
        sqlite.exec('ROLLBACK');
        throw error;
      }
    },
    async close() {
      sqlite.close();
    },
  };
  return api;
}

async function createPostgresInterface(url) {
  const pool = new Pool({ connectionString: url });
  const api = {
    dialect: 'postgres',
    ...createInterface((text, params) => pool.query(text, params)),
    async transaction(work) {
      const client = await pool.connect();
      const tx = createInterface((text, params) => client.query(text, params));
      try {
        await client.query('BEGIN');
        const result = await work(tx);
        await client.query('COMMIT');
        return result;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
      } finally {
        client.release();
      }
    },
    async close() {
      await pool.end();
    },
  };
  await pool.query('SELECT 1');
  return api;
}

export async function openDatabase({ connectionString, sqlitePath } = {}) {
  const postgresUrl = connectionString?.trim() || process.env.FITQUEST_DATABASE_URL?.trim();
  if (postgresUrl) return createPostgresInterface(postgresUrl);
  const dbPath = sqlitePath ?? process.env.FITQUEST_DB ?? './data/fitquest.sqlite';
  return createSqliteInterface(dbPath);
}
