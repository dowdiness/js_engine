// Run identical fixtures serially, alternating before/after order across pairs.
// Usage: node scripts/measure_numeric_update_cost.cjs BEFORE AFTER OUTPUT [PAIRS]
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const [before, after, output, count = '4'] = process.argv.slice(2);
if (!before || !after || !output || !Number.isInteger(+count) || +count < 2) {
  throw Error('expected BEFORE AFTER OUTPUT [PAIRS >= 2]');
}
const fixture = 'compiler/numeric_update_cost_benchmark_wbtest.mbt';
const files = [before, after].map(root => fs.readFileSync(path.join(root, fixture)));
if (!files[0].equals(files[1])) throw Error('benchmark fixtures differ');
function command(cmd, args, cwd) {
  const r = spawnSync(cmd, args, { cwd, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (r.error || r.status !== 0) throw Error(`${cmd}: ${r.error || r.stdout + r.stderr}`);
  return r.stdout + r.stderr;
}
const report = {
  createdAt: new Date().toISOString(),
  toolchain: command('moon', ['version', '--all']),
  node: process.version,
  cpu: os.cpus()[0].model,
  platform: `${os.platform()} ${os.release()}`,
  before: command('git', ['rev-parse', 'HEAD'], before).trim(),
  after: command('git', ['rev-parse', 'HEAD'], after).trim(),
  fixtureSha256: crypto.createHash('sha256').update(files[0]).digest('hex'),
  runs: [],
};
for (const target of ['wasm-gc', 'js', 'native']) {
  for (let pair = 0; pair < +count; pair++) {
    for (const side of pair % 2 === 0 ? ['before', 'after'] : ['after', 'before']) {
      const cwd = side === 'before' ? before : after;
      const raw = command('moon', ['bench', fixture, '--target', target, '--release'], cwd);
      const rows = [];
      for (const line of raw.split('\n')) {
        const m = line.match(/^(straight-postfix|loop-postfix|loop-prefix|loop-add-control)\s+([\d.]+)\s+(ns|µs|ms|s)\s+±/);
        if (m) rows.push({ name: m[1], us: +m[2] * ({ns: 0.001, 'µs': 1, ms: 1000, s: 1000000}[m[3]]) });
      }
      if (rows.length !== 4) throw Error(`expected four benchmark rows: ${raw}`);
      report.runs.push({ target, pair, side, rows, raw });
      fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify({ target, pair, side, rows }));
    }
  }
}
