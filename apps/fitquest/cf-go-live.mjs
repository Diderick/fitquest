import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { resolve } from 'node:path';

const args = process.argv.slice(2);

function readArg(name, fallback = undefined) {
  const index = args.indexOf(name);
  if (index === -1) return fallback;
  return args[index + 1];
}

function hasFlag(name) {
  return args.includes(name);
}

const domain = readArg('--domain');
const hyperdriveId = readArg('--hyperdrive-id');
const workerName = readArg('--name');
const secretsFile = readArg('--secrets-file', '.env.cloudflare');
const skipSecrets = hasFlag('--skip-secrets');
const dryRun = hasFlag('--dry-run');

if (!domain || !hyperdriveId) {
  console.error('Usage: node cf-go-live.mjs --domain <api.example.com> --hyperdrive-id <id> [--name <worker-name>] [--secrets-file .env.cloudflare] [--skip-secrets] [--dry-run]');
  process.exit(1);
}

if (!skipSecrets) {
  const secretsPath = resolve(process.cwd(), secretsFile);
  if (!existsSync(secretsPath)) {
    console.error(`Secrets file not found: ${secretsPath}`);
    console.error('Create it from .env.cloudflare.example or run with --skip-secrets if already uploaded.');
    process.exit(1);
  }
}

const tasks = [
  {
    label: 'Configuring wrangler.jsonc',
    command: 'node',
    commandArgs: ['cf-setup.mjs', '--domain', domain, '--hyperdrive-id', hyperdriveId, ...(workerName ? ['--name', workerName] : [])],
  },
  ...(!skipSecrets
    ? [{
        label: 'Uploading Wrangler secrets',
        command: 'node',
        commandArgs: ['cf-secrets.mjs', '--file', secretsFile],
      }]
    : []),
  {
    label: 'Running Cloudflare checks',
    command: 'node',
    commandArgs: ['cf-check.mjs'],
  },
  {
    label: 'Deploying Worker',
    command: 'npx',
    commandArgs: ['wrangler', 'deploy'],
  },
];

function runTask(task) {
  return new Promise((resolvePromise, rejectPromise) => {
    console.log(`\n▶ ${task.label}`);
    console.log(`$ ${task.command} ${task.commandArgs.join(' ')}`);
    const child = spawn(task.command, task.commandArgs, {
      stdio: 'inherit',
      shell: process.platform === 'win32',
    });
    child.on('exit', code => {
      if (code === 0) resolvePromise();
      else rejectPromise(new Error(`${task.label} failed (exit ${code})`));
    });
    child.on('error', rejectPromise);
  });
}

if (dryRun) {
  console.log('Dry run only. Planned go-live sequence:');
  for (const task of tasks) console.log(`- ${task.command} ${task.commandArgs.join(' ')}`);
  process.exit(0);
}

for (const task of tasks) {
  await runTask(task);
}

console.log('\n✅ Cloudflare go-live flow completed.');
