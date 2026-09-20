#!/usr/bin/env node
// THROWAWAY UI; all behavior and assertions run on the real MoonBit engine.
const {spawnSync} = require('node:child_process');
const {createInterface} = require('node:readline/promises');
const path = require('node:path');
const names = ['retained-host-object', 'strict-versus-coerce', 'host-type-error', 'host-failure', 'closed-handles', 'foreign-handles', 'reentry', 'method-turn-order', 'saved-function', 'coercion-exception'];
function run(name) {
  const args = ['run', '--target', 'native', 'cmd/value_handle_prototype'];
  if (name) args.push('--', name);
  const result = spawnSync('moon', args, {cwd: path.resolve(__dirname, '..'), encoding: 'utf8', timeout: 180000});
  if (result.error || result.status !== 0) throw new Error(result.error || result.stderr || result.stdout);
  return result.stdout.trim().split('\n').map(line => JSON.parse(line));
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length) {
    if (args.length === 1 && args[0] === '--all') {
      for (const report of run()) console.log(JSON.stringify(report));
      return;
    }
    if (args.length === 2 && args[0] === '--scenario' && names.includes(args[1])) {
      console.log(JSON.stringify(run(args[1])[0], null, 2));
      return;
    }
    throw new Error('Usage: --all | --scenario NAME | no arguments for menu');
  }
  const terminal = createInterface({input: process.stdin, output: process.stdout});
  let state = 'Each selection runs a fresh scenario; handles persist within its operations.';
  try {
    while (true) {
      console.clear();
      console.log('\x1b[1mValue Handle API — THROWAWAY\x1b[0m');
      console.log(state);
      console.log(names.map((name, i) => `[${i + 1}] ${name}`).join('\n'));
      const answer = (await terminal.question('[q] quit > ')).trim();
      if (answer === 'q') return;
      const name = names[Number(answer) - 1];
      state = name ? JSON.stringify(run(name)[0], null, 2) : 'Choose a listed scenario.';
    }
  } finally { terminal.close(); }
}
main().catch(error => {console.error(error.message); process.exitCode = 1;});
