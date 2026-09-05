const fs = require('node:fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
function median(xs) {
  const sorted = xs.toSorted((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}
console.log('| Target | Case | Before µs | After µs | Median paired delta | Paired range |');
console.log('|---|---|---:|---:|---:|---:|');
for (const target of [...new Set(report.runs.map(run => run.target))]) {
  const runs = report.runs.filter(run => run.target === target);
  for (const {name} of runs[0].rows) {
    const pairs = [...new Set(runs.map(run => run.pair))];
    const before = [], after = [], deltas = [];
    for (const pair of pairs) {
      const a = runs.find(run => run.pair === pair && run.side === 'before');
      const b = runs.find(run => run.pair === pair && run.side === 'after');
      if (!a || !b) continue;
      const old = a.rows.find(row => row.name === name).us;
      const next = b.rows.find(row => row.name === name).us;
      before.push(old); after.push(next); deltas.push(100 * (next / old - 1));
    }
    if (deltas.length) console.log(`| ${target} | ${name} | ${median(before).toFixed(2)} | ${median(after).toFixed(2)} | ${median(deltas).toFixed(1)}% | ${Math.min(...deltas).toFixed(1)}…${Math.max(...deltas).toFixed(1)}% |`);
  }
}
