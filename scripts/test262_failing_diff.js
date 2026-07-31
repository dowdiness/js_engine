#!/usr/bin/env node

// Compare two Test262 runner artifacts by per-mode regression / recovery
// transitions.  File I/O and process exit handling live in the CLI shell below;
// validate_artifact and compare_statuses are deterministic data transformations
// so the policy can be tested without GitHub Actions.

const fs = require("node:fs");
const path = require("node:path");

const NONPASS = new Set(["fail", "timeout", "error"]);
const EXECUTED = new Set(["pass", "fail", "timeout", "error"]);
const STATUSES = new Set(["pass", "fail", "skip", "timeout", "error"]);
const MODES = new Set(["strict", "non-strict"]);
const SUMMARY_FIELDS = ["total", "passed", "failed", "skipped", "timeout", "error"];

class ArtifactError extends Error {
  constructor(source, message) {
    super(`${source}: ${message}`);
    this.name = "ArtifactError";
  }
}

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireRecord(value, label) {
  if (!isRecord(value)) throw new ArtifactError(label, "expected an object");
  return value;
}

function requireString(value, label, { nonEmpty = false } = {}) {
  if (typeof value !== "string" || (nonEmpty && value.length === 0)) {
    throw new ArtifactError(label, nonEmpty ? "expected a non-empty string" : "expected a string");
  }
  return value;
}

function requireNonNegativeInteger(value, label) {
  if (!Number.isInteger(value) || value < 0) {
    throw new ArtifactError(label, "expected a non-negative integer");
  }
  return value;
}

function requireNonNegativeNumber(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new ArtifactError(label, "expected a finite non-negative number");
  }
  return value;
}

// Collapse repo-relative and Test262-root-relative spellings to one key.
// test262/test/language/x.js -> language/x.js
// language/x.js (already root-relative) -> language/x.js
function normalizePath(value, label = "path") {
  const normalized = requireString(value, label, { nonEmpty: true })
    .replace(/^\.\//, "")
    .replace(/^test262\//, "")
    .replace(/^test\//, "");
  if (normalized.length === 0) {
    throw new ArtifactError(label, "normalizes to an empty path");
  }
  return normalized;
}

function keyFor(pathname, mode) {
  return JSON.stringify([pathname, mode]);
}

function rowFromKey(key) {
  const [pathname, mode] = JSON.parse(key);
  return { path: pathname, mode };
}

function validateCategory(category, label) {
  const record = requireRecord(category, label);
  for (const field of ["total", "passed", "failed", "skipped"]) {
    requireNonNegativeInteger(record[field], `${label}.${field}`);
  }
  if (record.pass_rate !== undefined) {
    if (typeof record.pass_rate !== "number" || !Number.isFinite(record.pass_rate) || record.pass_rate < 0 || record.pass_rate > 100) {
      throw new ArtifactError(`${label}.pass_rate`, "expected a number between 0 and 100");
    }
  }
}

// Validate the stable fields needed by the comparison policy and return a
// normalized status map.  pass_rate is optional for compatibility with older
// merged main artifacts; all row/summary counts remain mandatory and exact.
function validateArtifact(data, source = "artifact") {
  const artifact = requireRecord(data, source);
  if (artifact.engine !== "moonbit-js-engine") {
    throw new ArtifactError(`${source}.engine`, "expected moonbit-js-engine");
  }
  requireString(artifact.date, `${source}.date`);

  const summary = requireRecord(artifact.summary, `${source}.summary`);
  for (const field of SUMMARY_FIELDS) {
    requireNonNegativeInteger(summary[field], `${source}.summary.${field}`);
  }
  if (summary.pass_rate !== undefined) {
    if (typeof summary.pass_rate !== "number" || !Number.isFinite(summary.pass_rate) || summary.pass_rate < 0 || summary.pass_rate > 100) {
      throw new ArtifactError(`${source}.summary.pass_rate`, "expected a number between 0 and 100");
    }
  }

  const categories = requireRecord(artifact.categories, `${source}.categories`);
  for (const [name, category] of Object.entries(categories)) {
    validateCategory(category, `${source}.categories.${name}`);
  }

  if (!Array.isArray(artifact.results)) {
    throw new ArtifactError(`${source}.results`, "expected an array");
  }
  if (artifact.results.length === 0) {
    throw new ArtifactError(`${source}.results`, "cannot be empty");
  }
  if (artifact.results.length !== summary.total) {
    throw new ArtifactError(
      source,
      `summary.total=${summary.total} but results has ${artifact.results.length} rows`,
    );
  }

  const statuses = new Map();
  const counts = { pass: 0, fail: 0, skip: 0, timeout: 0, error: 0 };
  for (const [index, result] of artifact.results.entries()) {
    const label = `${source}.results[${index}]`;
    const row = requireRecord(result, label);
    const pathname = normalizePath(row.path, `${label}.path`);
    requireString(row.reason, `${label}.reason`);
    requireNonNegativeNumber(row.duration_ms, `${label}.duration_ms`);
    if (!STATUSES.has(row.status)) {
      throw new ArtifactError(`${label}.status`, `unknown status ${JSON.stringify(row.status)}`);
    }
    if (!MODES.has(row.mode)) {
      throw new ArtifactError(`${label}.mode`, `unknown mode ${JSON.stringify(row.mode)}`);
    }
    const key = keyFor(pathname, row.mode);
    if (statuses.has(key)) {
      const display = rowFromKey(key);
      throw new ArtifactError(
        source,
        `duplicate result for (${display.path}, ${display.mode})`,
      );
    }
    statuses.set(key, row.status);
    counts[row.status] += 1;
  }

  const expected = {
    pass: summary.passed,
    fail: summary.failed,
    skip: summary.skipped,
    timeout: summary.timeout,
    error: summary.error,
  };
  for (const status of Object.keys(expected)) {
    if (counts[status] !== expected[status]) {
      throw new ArtifactError(
        source,
        `summary.${status === "pass" ? "passed" : status === "skip" ? "skipped" : status}=${expected[status]} but counted ${counts[status]} ${status} results`,
      );
    }
  }
  const countedTotal = Object.values(counts).reduce((sum, value) => sum + value, 0);
  if (countedTotal !== summary.total) {
    throw new ArtifactError(source, `status counts total ${countedTotal} but summary.total=${summary.total}`);
  }

  return { statuses, source };
}

function loadArtifact(filePath) {
  const source = path.resolve(filePath);
  let data;
  try {
    data = JSON.parse(fs.readFileSync(source, "utf8"));
  } catch (error) {
    throw new ArtifactError(source, `could not read or parse JSON (${error.message})`);
  }
  return validateArtifact(data, source);
}

// Backward-compatible helper name for callers that only need a status map.
function loadStatuses(filePath) {
  return loadArtifact(filePath).statuses;
}

function compareStatuses(baseline, candidate) {
  if (!(baseline instanceof Map) || !(candidate instanceof Map)) {
    throw new ArtifactError("comparison", "expected status maps");
  }
  const baselineKeys = [...baseline.keys()].sort();
  const candidateKeys = [...candidate.keys()].sort();
  if (baselineKeys.length !== candidateKeys.length || baselineKeys.some((key, index) => key !== candidateKeys[index])) {
    const missing = baselineKeys.filter((key) => !candidate.has(key)).map(rowFromKey);
    const extra = candidateKeys.filter((key) => !baseline.has(key)).map(rowFromKey);
    throw new ArtifactError(
      "comparison",
      `incomplete key coverage (missing=${JSON.stringify(missing)}, extra=${JSON.stringify(extra)})`,
    );
  }

  const regressions = [];
  const recoveries = [];
  const lostCoverage = [];
  for (const key of baselineKeys) {
    const from = baseline.get(key);
    const to = candidate.get(key);
    const row = rowFromKey(key);
    if (from === "pass" && NONPASS.has(to)) {
      regressions.push({ ...row, from, to });
    } else if (EXECUTED.has(from) && to === "skip") {
      lostCoverage.push({ ...row, from, to });
    } else if (NONPASS.has(from) && to === "pass") {
      recoveries.push({ ...row, from, to });
    }
  }
  return {
    regressions,
    lostCoverage,
    recoveries,
    baselineKeys: baselineKeys.length,
    candidateKeys: candidateKeys.length,
  };
}

function compareArtifacts(baseline, candidate) {
  const baselineArtifact = baseline.statuses ? baseline : validateArtifact(baseline, "baseline");
  const candidateArtifact = candidate.statuses ? candidate : validateArtifact(candidate, "candidate");
  return compareStatuses(baselineArtifact.statuses, candidateArtifact.statuses);
}

function report(title, rows, output = console) {
  output.log(`${title} (${rows.length}):`);
  for (const row of rows) {
    output.log(`  ${row.mode.padEnd(10)} ${`${row.from}->${row.to}`.padEnd(16)} ${row.path}`);
  }
  if (rows.length === 0) output.log("  (none)");
}

function main(argv = process.argv.slice(2), output = console) {
  if (argv.length !== 2) {
    output.error("usage: node scripts/test262_failing_diff.js <baseline.json> <candidate.json>");
    return 2;
  }
  let diff;
  try {
    diff = compareArtifacts(loadArtifact(argv[0]), loadArtifact(argv[1]));
  } catch (error) {
    output.error(`Test262 comparison failed closed: ${error.message}`);
    return 3;
  }

  report("REGRESSIONS (pass -> non-pass)", diff.regressions, output);
  output.log();
  report("LOST COVERAGE (executed -> skip)", diff.lostCoverage, output);
  output.log();
  report("RECOVERIES (non-pass -> pass)", diff.recoveries, output);
  output.log();
  output.log(
    `baseline keys=${diff.baselineKeys}  candidate keys=${diff.candidateKeys}  ` +
      `regressions=${diff.regressions.length}  lost_coverage=${diff.lostCoverage.length}  ` +
      `recoveries=${diff.recoveries.length}`,
  );
  return diff.regressions.length + diff.lostCoverage.length === 0 ? 0 : 1;
}

if (require.main === module) process.exitCode = main();

module.exports = {
  ArtifactError,
  compareArtifacts,
  compareStatuses,
  loadArtifact,
  loadStatuses,
  main,
  normalizePath,
  validateArtifact,
};
