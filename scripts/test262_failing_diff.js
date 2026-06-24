// Diff two Test262 runner artifacts by per-mode regression / fix transitions.
//
// Usage: node scripts/test262_failing_diff.js <baseline.json> <candidate.json>
//
// Emits the per-mode (normalized path, mode) entries whose outcome the
// candidate worsened (REGRESSIONS: baseline `pass` -> candidate non-pass) or
// improved (FIXED: baseline non-pass -> candidate `pass`). A "non-pass" is any
// of fail / timeout / error (docs/decisions/tooling-migration-contracts.md
// "Status semantics"): a previously passing test that now times out or hits a
// runner error is a regression, and a baseline failure that becomes
// skip/timeout/error is NOT a fix because it did not newly pass.
//
// LOST COVERAGE (baseline executed -> candidate `skip`) is reported separately:
// over-broad skip metadata stops executing a test that previously ran, whatever
// its outcome. A `pass -> skip` lowers Passed/Discovered; a `fail/timeout/error
// -> skip` HIDES a known failure so the failing-set diff looks clean when the
// failure was only masked, not fixed. Both are surfaced here (the `from` status
// shows which) and, like regressions, force a non-zero exit so newly-skipped
// tests cannot pass silently.
//
// Each artifact conforms to scripts/test262_result_contract.schema.json.
// Keys are built from the CONTRACT-STABLE key (normalized path, mode):
// `path` may be repo-relative (test262/test/language/x.js) or Test262-root-
// relative (language/x.js), so both spellings are normalized to one form
// before comparison to avoid false regressions/fixes across runs.
//
// Before trusting any diff we validate each non-pass count against the
// artifact summary (summary.failed/timeout/error === counted) — a mismatch
// means the extractor or artifact is broken, so we abort rather than report a
// false "0 regressions".

const NONPASS = new Set(["fail", "timeout", "error"]);
// Statuses where the test actually ran. Any executed -> skip is lost coverage.
const EXECUTED = new Set(["pass", "fail", "timeout", "error"]);

// Collapse repo-relative and Test262-root-relative spellings to one key.
// test262/test/language/x.js -> test/language/x.js -> language/x.js
// language/x.js (already root-relative) -> language/x.js
function normalizePath(p) {
  return p
    .replace(/^\.\//, "")
    .replace(/^test262\//, "")
    .replace(/^test\//, "");
}

// Build (normalized path \t mode) -> status, validating non-pass counts.
function loadStatuses(path) {
  const data = require(require("path").resolve(path));
  const byKey = new Map();
  const counts = { pass: 0, fail: 0, timeout: 0, error: 0, skip: 0 };
  for (const r of data.results) {
    const key = `${normalizePath(r.path)}\t${r.mode}`;
    // The (normalized path, mode) key must be unique. A duplicate would
    // overwrite the earlier row in byKey, dropping it from the diff — and a
    // duplicate paired with a dropped row keeps results.length and the
    // per-status counts intact, so the count checks below would NOT catch it.
    // Reject duplicates here so byKey.size === results.length is guaranteed.
    if (byKey.has(key)) {
      const [p, mode] = key.split("\t");
      throw new Error(
        `${path}: duplicate result for (${p}, ${mode}) — the (normalized ` +
          `path, mode) key must be unique; refusing to diff`,
      );
    }
    byKey.set(key, r.status);
    if (r.status in counts) counts[r.status]++;
  }
  // Global integrity: the results row count matches summary.total. Combined
  // with the duplicate-key rejection above (which makes byKey.size ===
  // results.length), this ensures no row was silently dropped or overwritten.
  if (data.results.length !== data.summary.total) {
    throw new Error(
      `${path}: summary.total=${data.summary.total} but results has ` +
        `${data.results.length} rows — artifact/extractor disagree, refusing ` +
        `to diff`,
    );
  }
  // Per-status reconciliation. `pass` is validated too: baseline pass rows are
  // the only evidence that a candidate non-pass is a regression, so silently
  // dropped pass rows would hide real pass->fail changes.
  const summaryField = {
    pass: "passed",
    fail: "failed",
    timeout: "timeout",
    error: "error",
    skip: "skipped",
  };
  for (const status of ["pass", "fail", "timeout", "error", "skip"]) {
    const field = summaryField[status];
    if (counts[status] !== data.summary[field]) {
      throw new Error(
        `${path}: summary.${field}=${data.summary[field]} but counted ` +
          `${counts[status]} ${status} results — artifact/extractor disagree, ` +
          `refusing to diff`,
      );
    }
  }
  return byKey;
}

function report(title, rows) {
  console.log(`${title} (${rows.length}):`);
  for (const { key, from, to } of rows.sort((a, b) =>
    a.key.localeCompare(b.key),
  )) {
    const [p, mode] = key.split("\t");
    console.log(`  ${mode.padEnd(10)} ${`${from}->${to}`.padEnd(16)} ${p}`);
  }
  if (rows.length === 0) console.log("  (none)");
}

function main() {
  const [, , baselinePath, candidatePath] = process.argv;
  if (!baselinePath || !candidatePath) {
    console.error(
      "usage: node scripts/test262_failing_diff.js <baseline.json> <candidate.json>",
    );
    process.exit(2);
  }
  const baseline = loadStatuses(baselinePath);
  const candidate = loadStatuses(candidatePath);

  const regressions = [];
  const fixed = [];
  const lostCoverage = [];
  // Transitions are only classifiable when BOTH artifacts observed the key;
  // a key present in only one run (e.g. different filter scope) is left
  // unclassified rather than reported as a false regression/fix.
  for (const [key, candStatus] of candidate) {
    const baseStatus = baseline.get(key);
    if (baseStatus === undefined) continue;
    if (baseStatus === "pass" && NONPASS.has(candStatus)) {
      regressions.push({ key, from: baseStatus, to: candStatus });
    } else if (candStatus === "skip" && EXECUTED.has(baseStatus)) {
      lostCoverage.push({ key, from: baseStatus, to: candStatus });
    } else if (NONPASS.has(baseStatus) && candStatus === "pass") {
      fixed.push({ key, from: baseStatus, to: candStatus });
    }
  }

  report("REGRESSIONS (pass -> non-pass)", regressions);
  console.log();
  report("LOST COVERAGE (executed -> skip)", lostCoverage);
  console.log();
  report("FIXED (non-pass -> pass)", fixed);
  console.log();
  console.log(
    `baseline keys=${baseline.size}  candidate keys=${candidate.size}  ` +
      `regressions=${regressions.length}  lost_coverage=${lostCoverage.length}  ` +
      `fixed=${fixed.length}`,
  );

  process.exit(regressions.length + lostCoverage.length === 0 ? 0 : 1);
}

main();
