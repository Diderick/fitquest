import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const requiredSecrets = [
  'FITQUEST_API_TOKEN',
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',
  'FACEBOOK_APP_ID',
  'FACEBOOK_APP_SECRET',
  'FACEBOOK_GRAPH_VERSION',
];

const projectDir = process.cwd();
const wranglerPath = resolve(projectDir, 'wrangler.jsonc');
const workerPath = resolve(projectDir, 'worker.mjs');

function parseJsonc(raw) {
  const noBom = raw.replace(/^\uFEFF/, '');
  const withoutBlockComments = noBom.replace(/\/\*[\s\S]*?\*\//g, '');
  const withoutLineComments = withoutBlockComments.replace(/^\s*\/\/.*$/gm, '');
  const withoutTrailingCommas = withoutLineComments.replace(/,\s*([}\]])/g, '$1');
  return JSON.parse(withoutTrailingCommas);
}

function checkHttpsUrl(value) {
  if (typeof value !== 'string') return false;
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

function domainFromUrl(value) {
  try {
    return new URL(value).hostname.toLowerCase();
  } catch {
    return null;
  }
}

const failures = [];
const warnings = [];

if (!existsSync(wranglerPath)) {
  failures.push('Missing wrangler.jsonc file.');
} else {
  let wrangler;
  try {
    const raw = readFileSync(wranglerPath, 'utf8');
    wrangler = parseJsonc(raw);
  } catch (error) {
    failures.push(`Unable to parse wrangler.jsonc: ${error.message}`);
  }

  if (wrangler) {
    if (wrangler.main !== 'worker.mjs') {
      failures.push(`wrangler.main is '${wrangler.main ?? '<missing>'}', expected 'worker.mjs'.`);
    }

    const flags = Array.isArray(wrangler.compatibility_flags) ? wrangler.compatibility_flags : [];
    if (!flags.includes('nodejs_compat')) {
      failures.push("compatibility_flags must include 'nodejs_compat'.");
    }

    const redirectBase = wrangler?.vars?.OAUTH_REDIRECT_BASE;
    if (!checkHttpsUrl(redirectBase)) {
      failures.push('vars.OAUTH_REDIRECT_BASE must be a valid https URL.');
    }

    const hyperdrives = Array.isArray(wrangler.hyperdrive) ? wrangler.hyperdrive : [];
    const hyperdrive = hyperdrives.find(entry => entry?.binding === 'FITQUEST_HYPERDRIVE');
    if (!hyperdrive) {
      failures.push("Missing hyperdrive binding with binding='FITQUEST_HYPERDRIVE'.");
    } else {
      const id = String(hyperdrive.id ?? '').trim();
      if (!id || id === 'REPLACE_WITH_HYPERDRIVE_ID') {
        failures.push('Hyperdrive id is still placeholder. Set wrangler.hyperdrive[...].id to real ID.');
      }
    }

    const routes = Array.isArray(wrangler.routes) ? wrangler.routes : [];
    if (routes.length === 0) {
      warnings.push('No routes are set in wrangler.jsonc. Attach a custom API domain route before production cutover.');
    }

    const routeHosts = routes
      .map(route => typeof route?.pattern === 'string' ? route.pattern.split('/')[0].toLowerCase() : null)
      .filter(Boolean);
    const oauthHost = domainFromUrl(redirectBase);
    if (oauthHost && routeHosts.length > 0 && !routeHosts.includes(oauthHost)) {
      warnings.push(`Route host(s) [${routeHosts.join(', ')}] do not include OAUTH_REDIRECT_BASE host '${oauthHost}'.`);
    }
  }
}

if (!existsSync(workerPath)) {
  failures.push('Missing worker.mjs entrypoint file.');
}

const secretsExamplePath = resolve(projectDir, '.env.cloudflare.example');
if (!existsSync(secretsExamplePath)) {
  warnings.push('Missing .env.cloudflare.example template file.');
}

if (failures.length === 0) {
  console.log('✅ Cloudflare pre-deploy check passed.');
} else {
  console.error('❌ Cloudflare pre-deploy check failed:');
  for (const message of failures) console.error(`  - ${message}`);
}

if (warnings.length) {
  console.log('\n⚠️ Warnings:');
  for (const message of warnings) console.log(`  - ${message}`);
}

console.log('\nℹ️ Required Wrangler secrets:');
for (const secret of requiredSecrets) console.log(`  - ${secret}`);

if (failures.length) process.exit(1);
