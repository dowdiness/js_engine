const assert = require('node:assert/strict');
const test = require('node:test');
const { summarize, parseBenchmarkOutput } = require('./numeric_update_results.cjs');

function completeReport() {
  const runs = [];
  for (const target of ['wasm-gc', 'js', 'native']) {
    for (const pair of [0, 1]) {
      for (const side of ['before', 'after']) {
        const us = side === 'before' ? [10, 20][pair] : [8, 10][pair];
        runs.push({ target, pair, side, rows:
          ['straight-postfix', 'loop-postfix', 'loop-prefix', 'loop-add-control']
            .map(name => ({ name, us })) });
      }
    }
  }
  return { pairs: 2, runs };
}

test('paired changes are summarized independently of the ratio of medians', () => {
  const report = completeReport();
  const original = structuredClone(report);
  const rows = summarize(report);
  assert.equal(rows.length, 12);
  assert.deepEqual(rows[0], {
    target: 'wasm-gc', name: 'straight-postfix', before: 15, after: 9,
    delta: -35, min: -50, max: -20,
  });
  assert.deepEqual(report, original);
  report.runs.reverse();
  assert.deepEqual(summarize(report), rows);
});

test('historical reports require an explicit expected pair count', () => {
  const report = completeReport();
  delete report.pairs;
  assert.throws(() => summarize(report), /numeric-update report:/);
  assert.equal(summarize(report, 2).length, 12);
  assert.throws(() => summarize(completeReport(), 3), /numeric-update report:/);
});

const invalidReports = [
  ['missing side', r => { r.runs.pop(); }],
  ['missing whole pair', r => { r.runs = r.runs.filter(x => x.pair === 0); }],
  ['missing target', r => { r.runs = r.runs.filter(x => x.target !== 'native'); }],
  ['duplicate run', r => { r.runs[1] = structuredClone(r.runs[0]); }],
  ['unknown target', r => { r.runs[0].target = 'wasm'; }],
  ['unknown side', r => { r.runs[0].side = 'patched'; }],
  ['out-of-range pair', r => { r.runs[0].pair = 2; }],
  ['fractional pair', r => { r.runs[0].pair = 0.5; }],
  ['missing case', r => { r.runs[0].rows.pop(); }],
  ['duplicate case', r => { r.runs[0].rows[1].name = 'straight-postfix'; }],
  ['unknown case', r => { r.runs[0].rows[0].name = 'typo'; }],
  ['invalid pair count', r => { r.pairs = 1; }],
];
for (const [name, damage] of invalidReports) {
  test(`rejects ${name} rather than publishing a partial comparison`, () => {
    const report = completeReport();
    damage(report);
    assert.throws(() => summarize(report), /numeric-update report:/);
  });
}

test('timings must be finite positive numbers and produce finite changes', () => {
  for (const us of [0, -1, NaN, Infinity, '10', null]) {
    const report = completeReport();
    report.runs[0].rows[0].us = us;
    assert.throws(() => summarize(report), /numeric-update report:/);
  }
  const report = completeReport();
  report.runs[0].rows[0].us = Number.MIN_VALUE;
  assert.throws(() => summarize(report), /numeric-update report:/);
});

test('malformed report shapes fail with a report diagnostic', () => {
  for (const report of [null, {}, { pairs: 2, runs: null }, { pairs: 2, runs: [null] }]) {
    assert.throws(() => summarize(report), /numeric-update report:/);
  }
});

function benchmarkEvent(rows) {
  return JSON.stringify({ type: 'result', message: '@BATCH_BENCH ' + JSON.stringify({
    summaries: rows.map(row => ({ name: row.name, mean: row.us })),
  }) });
}

test('reads unrounded means from exactly one complete structured benchmark result', () => {
  const rows = completeReport().runs[0].rows;
  rows[0].us = 1.23456789;
  const event = benchmarkEvent(rows);
  assert.deepEqual(parseBenchmarkOutput('driver startup\n' + event + '\n').rows, rows);
  for (const raw of ['', event + '\n' + event, '{broken json}',
    benchmarkEvent(rows.slice(1)), benchmarkEvent([rows[0], rows[0], rows[2], rows[3]])]) {
    assert.throws(() => parseBenchmarkOutput(raw), /numeric-update report:/);
  }
});

test('CLI prints a complete table or exits with a diagnostic and no table', () => {
  const fs = require('node:fs');
  const os = require('node:os');
  const path = require('node:path');
  const { spawnSync } = require('node:child_process');
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'numeric-update-cli-'));
  try {
    const file = path.join(directory, 'report.json');
    const run = report => {
      fs.writeFileSync(file, JSON.stringify(report));
      const result = spawnSync(process.execPath,
        [path.join(__dirname, 'summarize_numeric_update_cost.cjs'), file], { encoding: 'utf8' });
      if (result.error) throw result.error;
      return result;
    };
    const valid = run(completeReport());
    assert.equal(valid.status, 0);
    assert.equal(valid.stdout.trim().split('\n').length, 14);
    assert.match(valid.stdout, /\| wasm-gc \| straight-postfix \| 15.00 \| 9.00 \| -35.0% \| -50.0…-20.0% \|/);
    const incomplete = completeReport();
    incomplete.runs = incomplete.runs.filter(row => row.pair === 0);
    const invalid = run(incomplete);
    assert.equal(invalid.status, 1);
    assert.equal(invalid.stdout, '');
    assert.match(invalid.stderr, /incomplete series/);
  } finally {
    fs.rmSync(directory, { recursive: true });
  }
});
