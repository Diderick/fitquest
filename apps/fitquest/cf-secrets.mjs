import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawn } from 'node:child_process';

const requiredSecrets = [
  'FITQUEST_API_TOKEN',
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',
  'FACEBOOK_APP_ID',
  'FACEBOOK_APP_SECRET',
  'FACEBOOK_GRAPH_VERSION',
];

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');

function readArg(name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  return args[index + 1];
}

function parseJsonc(raw) {
  const noBom = raw.replace(/^\uFEFF/, '');
  const withoutBlockComments = noBom.replace(/\/\*[\s\S]*?\*\//g, '');
  const withoutLineComments = withoutBlockComments.replace(/^\s*\/\/.*$/gm, '');
  const withoutTrailingCommas = withoutLineComments.replace(/,\s*([}\]])/g, '$1');
  return JSON.parse(withoutTrailingCommas);
}

function parseDotEnv(raw) {
  const output = {};
  for (const line of raw.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const equals = trimmed.indexOf('=');
    if (equals <= 0) continue;
    const key = trimmed.slice(0, equals).trim();
    let value = trimmed.slice(equals + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    output[key] = value;
  }
  return output;
}

async function putSecret(workerName, key, value) {
  return new Promise((resolvePromise, rejectPromise) => {
    const child = spawn('npx', ['wrangler', 'secret', 'put', key, '--name', workerName], {
      stdio: ['pipe', 'inherit', 'inherit'],
      shell: process.platform === 'win32',
    });
    child.stdin.write(value);
    child.stdin.end();
    child.on('exit', code => {
      if (code === 0) resolvePromise();
      else rejectPromise(new Error(`wrangler secret put failed for ${key} (exit ${code})`));
    });
    child.on('error', rejectPromise);
  });
}

const envFile = readArg('--file') ?? '.env.cloudflare';
const envPath = resolve(process.cwd(), envFile);
if (!existsSync(envPath)) {
  console.error(`Missing secrets file: ${envPath}`);
  console.error('Copy .env.cloudflare.example to .env.cloudflare and fill values first.');
  process.exit(1);
}

const wranglerPath = resolve(process.cwd(), 'wrangler.jsonc');
if (!existsSync(wranglerPath)) {
  console.error(`Missing file: ${wranglerPath}`);
  process.exit(1);
}

const wrangler = parseJsonc(readFileSync(wranglerPath, 'utf8'));
const workerName = wrangler.name;
if (!workerName) {
  console.error('wrangler.jsonc is missing worker name.');
  process.exit(1);
}

const env = parseDotEnv(readFileSync(envPath, 'utf8'));
const missing = requiredSecrets.filter(key => !env[key]);
if (missing.length) {
  console.error('Missing required secrets in env file:');
  for (const key of missing) console.error(`  - ${key}`);
  process.exit(1);
}

console.log(`Using worker: ${workerName}`);
console.log(`Secrets file: ${envFile}`);

if (dryRun) {
  console.log('Dry run only. Would upload:');
  for (const key of requiredSecrets) console.log(`  - ${key}`);
  process.exit(0);
}

for (const key of requiredSecrets) {
  console.log(`Uploading secret: ${key}`);
  await putSecret(workerName, key, env[key]);
}

console.log('✅ Wrangler secrets uploaded successfully.');
