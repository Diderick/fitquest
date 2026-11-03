import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

const args = process.argv.slice(2);

function readArg(name) {
  const index = args.indexOf(name);
  if (index === -1) return undefined;
  return args[index + 1];
}

const domain = readArg('--domain');
const hyperdriveId = readArg('--hyperdrive-id');
const workerName = readArg('--name');

if (!domain || !hyperdriveId) {
  console.error('Usage: node cf-setup.mjs --domain <api.example.com> --hyperdrive-id <id> [--name <worker-name>]');
  process.exit(1);
}

if (!/^[a-z0-9.-]+$/i.test(domain) || !domain.includes('.')) {
  console.error(`Invalid domain: ${domain}`);
  process.exit(1);
}

if (hyperdriveId === 'REPLACE_WITH_HYPERDRIVE_ID') {
  console.error('Provide a real Hyperdrive ID, not the placeholder value.');
  process.exit(1);
}

const wranglerPath = resolve(process.cwd(), 'wrangler.jsonc');
if (!existsSync(wranglerPath)) {
  console.error(`Missing file: ${wranglerPath}`);
  process.exit(1);
}

function parseJsonc(raw) {
  const noBom = raw.replace(/^\uFEFF/, '');
  const withoutBlockComments = noBom.replace(/\/\*[\s\S]*?\*\//g, '');
  const withoutLineComments = withoutBlockComments.replace(/^\s*\/\/.*$/gm, '');
  const withoutTrailingCommas = withoutLineComments.replace(/,\s*([}\]])/g, '$1');
  return JSON.parse(withoutTrailingCommas);
}

const raw = readFileSync(wranglerPath, 'utf8');
const config = parseJsonc(raw);

config.name = workerName || config.name || 'fitquest-api';
config.main = config.main || 'worker.mjs';
config.compatibility_flags = Array.isArray(config.compatibility_flags) ? config.compatibility_flags : [];
if (!config.compatibility_flags.includes('nodejs_compat')) config.compatibility_flags.push('nodejs_compat');

config.vars = config.vars ?? {};
config.vars.OAUTH_REDIRECT_BASE = `https://${domain}`;

config.hyperdrive = Array.isArray(config.hyperdrive) ? config.hyperdrive : [];
const existingHyperdrive = config.hyperdrive.find(entry => entry?.binding === 'FITQUEST_HYPERDRIVE');
if (existingHyperdrive) {
  existingHyperdrive.id = hyperdriveId;
} else {
  config.hyperdrive.push({ binding: 'FITQUEST_HYPERDRIVE', id: hyperdriveId });
}

config.routes = [{ pattern: `${domain}/*`, custom_domain: true }];

writeFileSync(wranglerPath, `${JSON.stringify(config, null, 2)}\n`, 'utf8');

console.log('✅ Updated wrangler.jsonc');
console.log(`   Worker name: ${config.name}`);
console.log(`   Domain route: ${domain}`);
console.log(`   OAUTH_REDIRECT_BASE: ${config.vars.OAUTH_REDIRECT_BASE}`);
console.log('   Hyperdrive binding: FITQUEST_HYPERDRIVE');
console.log('\nNext:');
console.log('  1) npm run cf:secrets');
console.log('  2) npm run cf:check');
console.log('  3) npm run cf:deploy');
