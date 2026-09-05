const fs = require('node:fs');
const { summarize } = require('./numeric_update_results.cjs');

try {
  const [file, pairs] = process.argv.slice(2);
  if (!file || process.argv.length > 4) throw Error('usage: node scripts/summarize_numeric_update_cost.cjs REPORT [EXPECTED_PAIRS]');
  const report = JSON.parse(fs.readFileSync(file, 'utf8'));
  // Validate the entire report before printing even the table header.
  const rows = summarize(report, pairs === undefined ? undefined : Number(pairs));
  console.log('| Target | Case | Before µs | After µs | Median paired delta | Paired range |');
  console.log('|---|---|---:|---:|---:|---:|');
  for (const row of rows) {
    console.log(`| ${row.target} | ${row.name} | ${row.before.toFixed(2)} | ${row.after.toFixed(2)} | ${row.delta.toFixed(1)}% | ${row.min.toFixed(1)}…${row.max.toFixed(1)}% |`);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
