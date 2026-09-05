// Compare saved compiler benchmark artifacts without build time or text rounding.
// Usage: node scripts/compare_numeric_update_artifacts.cjs ARTIFACT_DIR OUTPUT [PAIRS]
// ARTIFACT_DIR contains merged.{wasm,js,exe} and patched.{wasm,js,exe}.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [directory, output, count = '4'] = process.argv.slice(2);
if (!directory || !output || !Number.isInteger(+count) || +count < 2) throw Error('expected ARTIFACT_DIR OUTPUT [PAIRS >= 2]');
const filter = JSON.stringify({package: 'dowdiness/js_engine/compiler', file_and_index: [['numeric_update_cost_benchmark_wbtest.mbt', [{start: 0, end: 1}]]]});
const report = { createdAt: new Date().toISOString(), before: 'merged', after: 'patched', artifacts: {}, runs: [] };
for (const [target, extension] of [['wasm-gc', 'wasm'], ['js', 'js'], ['native', 'exe']]) {
  for (const side of ['merged', 'patched']) {
    const file = path.join(directory, `${side}.${extension}`);
    report.artifacts[`${target}/${side}`] = {file, sha256: crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')};
  }
  for (let pair = 0; pair < +count; pair++) {
    for (const side of pair % 2 === 0 ? ['merged', 'patched'] : ['patched', 'merged']) {
      const file = report.artifacts[`${target}/${side}`].file;
      const [command, args] = target === 'js' ? ['node', [file, filter]] : target === 'wasm-gc' ? ['moonrun', [file, '--test-args', filter]] : [file, ['numeric_update_cost_benchmark_wbtest.mbt:0-1']];
      const r = spawnSync(command, args, {encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
      if (r.error || r.status !== 0) throw Error(`${target}/${side}: ${r.error || r.stdout + r.stderr}`);
      const raw = r.stdout + r.stderr;
      const events = raw.split('\n').filter(line => line.startsWith('{')).map(line => JSON.parse(line));
      const event = events.find(event => event.type === 'result' && event.message?.startsWith('@BATCH_BENCH '));
      if (!event) throw Error(`missing benchmark result: ${raw}`);
      const summaries = JSON.parse(event.message.slice('@BATCH_BENCH '.length)).summaries;
      if (summaries.length !== 4) throw Error('expected four benchmark cases');
      const rows = summaries.map(row => ({name: row.name, us: row.mean}));
      report.runs.push({target, pair, side: side === 'merged' ? 'before' : 'after', rows, summaries, raw});
      fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
      console.log(JSON.stringify({target, pair, side, rows}));
    }
  }
}
