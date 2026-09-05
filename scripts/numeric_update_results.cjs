// Deterministic result handling for the numeric-update fixture; no I/O here.
const TARGETS = Object.freeze(['wasm-gc', 'js', 'native']);
const CASES = Object.freeze(['straight-postfix', 'loop-postfix', 'loop-prefix', 'loop-add-control']);

function requireValid(condition, message) {
  if (!condition) throw Error(`numeric-update report: ${message}`);
}

function validateRows(rows, context) {
  requireValid(Array.isArray(rows) && rows.length === CASES.length,
    `${context}: expected all four cases`);
  const seen = new Set();
  for (const row of rows) {
    requireValid(row && CASES.includes(row.name) && !seen.has(row.name),
      `${context}: unknown or duplicate case`);
    requireValid(Number.isFinite(row.us) && row.us > 0,
      `${context}/${row.name}: timing must be a finite positive number`);
    seen.add(row.name);
  }
}

function validateReport(report, expectedPairs) {
  requireValid(report && Array.isArray(report.runs), 'expected a runs array');
  requireValid(Number.isSafeInteger(expectedPairs) && expectedPairs >= 2,
    'expected pair count must be an integer >= 2; supply it explicitly for historical reports');
  requireValid(report.pairs === undefined || report.pairs === expectedPairs,
    'recorded and requested pair counts disagree');
  requireValid(report.runs.length === TARGETS.length * 2 * expectedPairs,
    'incomplete series: expected both sides of every pair on all three targets');
  const seen = new Set();
  for (const run of report.runs) {
    requireValid(run && TARGETS.includes(run.target), 'unknown target');
    requireValid(['before', 'after'].includes(run.side), 'unknown side');
    requireValid(Number.isSafeInteger(run.pair) && run.pair >= 0 && run.pair < expectedPairs,
      'pair index outside the expected range');
    const key = `${run.target}/${run.pair}/${run.side}`;
    requireValid(!seen.has(key), `duplicate run: ${key}`);
    seen.add(key);
    validateRows(run.rows, key);
  }
}

function median(values) {
  const sorted = values.toSorted((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : sorted[middle - 1] / 2 + sorted[middle] / 2;
}

function summarize(report, expectedPairs = report?.pairs) {
  validateReport(report, expectedPairs);
  return TARGETS.flatMap(target => CASES.map(name => {
    const before = [], after = [], deltas = [];
    for (let pair = 0; pair < expectedPairs; pair++) {
      const read = side => report.runs.find(run =>
        run.target === target && run.pair === pair && run.side === side
      ).rows.find(row => row.name === name).us;
      const old = read('before'), next = read('after');
      before.push(old);
      after.push(next);
      const delta = 100 * ((next - old) / old);
      requireValid(Number.isFinite(delta), `${target}/${name}: percentage change overflow`);
      deltas.push(delta);
    }
    return { target, name, before: median(before), after: median(after),
      delta: median(deltas), min: Math.min(...deltas), max: Math.max(...deltas) };
  }));
}

function parseBenchmarkOutput(raw) {
  let events;
  try {
    events = raw.split('\n').map(line => line.trim())
      .filter(line => line.startsWith('{')).map(line => JSON.parse(line));
  } catch {
    throw Error('numeric-update report: malformed driver JSON');
  }
  const results = events.filter(event => event.type === 'result' &&
    typeof event.message === 'string' && event.message.startsWith('@BATCH_BENCH '));
  requireValid(results.length === 1, 'expected exactly one benchmark result');
  let batch;
  try {
    batch = JSON.parse(results[0].message.slice('@BATCH_BENCH '.length));
  } catch {
    throw Error('numeric-update report: malformed benchmark JSON');
  }
  requireValid(batch && Array.isArray(batch.summaries), 'expected benchmark summaries');
  const rows = batch.summaries.map(row => ({ name: row?.name, us: row?.mean }));
  validateRows(rows, 'benchmark output');
  return { rows, summaries: batch.summaries };
}

module.exports = { summarize, parseBenchmarkOutput };
