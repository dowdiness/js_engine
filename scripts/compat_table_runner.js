#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const DEFAULT_SUITES = ["es5", "es6", "es2016plus"];
const SIGNIFICANCE_WEIGHTS = {
  large: 1,
  medium: 0.5,
  small: 0.25,
  tiny: 0.125,
};
const SUCCESS_MARKER = "[SUCCESS]";

function usage() {
  return `Usage: node scripts/compat_table_runner.js [options]

Required:
  --compat-table DIR          compat-table checkout or extracted archive
  --compat-table-commit SHA   pinned upstream revision recorded in reports
  --engine FILE               built js_engine native CLI

Options:
  --engine-arg VALUE          fixed engine argument; repeatable
  --suite NAME                suite to run; repeatable (default: es5, es6, es2016plus)
  --timeout-ms N              timeout for each subtest (default: 5000)
  --output FILE               JSON output (default: compat-table-results.json)
  --markdown FILE             Markdown output (default: compat-table-summary.md)
  --engine-commit SHA         js_engine revision recorded in reports
  --help                      show this help
`;
}

function parseArgs(argv) {
  const options = {
    suites: [],
    engineArgs: [],
    timeoutMs: 5000,
    output: "compat-table-results.json",
    markdown: "compat-table-summary.md",
    engineCommit: process.env.GITHUB_SHA || "unknown",
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    const valueOptions = new Set([
      "--compat-table",
      "--compat-table-commit",
      "--engine",
      "--engine-arg",
      "--engine-commit",
      "--suite",
      "--timeout-ms",
      "--output",
      "--markdown",
    ]);
    if (!valueOptions.has(arg)) {
      throw new Error(`unknown option: ${arg}`);
    }
    if (i + 1 >= argv.length) {
      throw new Error(`${arg} requires a value`);
    }
    const value = argv[(i += 1)];
    switch (arg) {
      case "--compat-table":
        options.compatTable = value;
        break;
      case "--compat-table-commit":
        options.compatTableCommit = value;
        break;
      case "--engine":
        options.engine = value;
        break;
      case "--engine-arg":
        options.engineArgs.push(value);
        break;
      case "--engine-commit":
        options.engineCommit = value;
        break;
      case "--suite":
        options.suites.push(value);
        break;
      case "--timeout-ms":
        options.timeoutMs = Number(value);
        break;
      case "--output":
        options.output = value;
        break;
      case "--markdown":
        options.markdown = value;
        break;
      default:
        throw new Error(`unhandled option: ${arg}`);
    }
  }
  if (options.help) return options;
  for (const required of ["compatTable", "compatTableCommit", "engine"]) {
    if (!options[required]) {
      throw new Error(`missing required option: ${required}`);
    }
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive integer");
  }
  if (options.suites.length === 0) options.suites = DEFAULT_SUITES.slice();
  for (const suite of options.suites) {
    if (!/^[a-z0-9-]+$/.test(suite)) {
      throw new Error(`invalid suite name: ${suite}`);
    }
  }
  options.compatTable = path.resolve(options.compatTable);
  options.engine = path.resolve(options.engine);
  options.output = path.resolve(options.output);
  options.markdown = path.resolve(options.markdown);
  return options;
}

function removeIndent(source) {
  const indentation = /^[\t ]+/m.exec(source);
  if (!indentation) return source;
  return source.replace(new RegExp(`^${indentation[0]}`, "gm"), "");
}

function extractTestCode(exec) {
  if (typeof exec === "function") {
    const source = exec.toString();
    const commentBody =
      /^function\s*\w*\s*\(.*?\)\s*\{\s*\/\*([\s\S]*?)\*\/\s*\}$/m.exec(
        source,
      );
    if (commentBody) {
      return `(function () { ${removeIndent(commentBody[1])} })()`;
    }
    return `(${source})()`;
  }
  if (Array.isArray(exec)) {
    return exec.map((entry) => extractTestCode(entry.script)).join("; ");
  }
  return undefined;
}

function makeScript(testCode, createIterableHelper) {
  let script = "";
  if (/\blacksGlobal\b/.test(testCode)) {
    script += 'this.lacksGlobal = typeof global === "undefined";\n';
  }
  if (/\bglobal\b/.test(testCode)) {
    script += 'if (typeof global === "undefined") { global = this; }\n';
  }
  if (/\blacksGlobalThis\b/.test(testCode)) {
    script += 'this.lacksGlobalThis = typeof globalThis === "undefined";\n';
  }
  if (/\bglobalThis\b/.test(testCode)) {
    script +=
      'if (typeof globalThis === "undefined") { globalThis = this; }\n';
  }
  if (/\b__script_executed\b/.test(testCode)) {
    script +=
      "var __script_executed = {};\n" +
      "global.__script_executed = __script_executed;\n";
  }
  if (/\b__createIterableObject\b/.test(testCode)) {
    script += `${createIterableHelper}\n`;
  }
  script += `var testCode = ${JSON.stringify(testCode)};\n`;

  if (/\basyncTestPassed\b/.test(testCode)) {
    script += [
      `function asyncTestPassed() { console.log("${SUCCESS_MARKER}"); }`,
      "var jobQueue = [];",
      "function setTimeout(cb, time, cbarg) {",
      "  var runTime = Date.now() + time;",
      "  if (!jobQueue[runTime]) { jobQueue[runTime] = []; }",
      "  jobQueue[runTime].push(function () { cb(cbarg); });",
      "}",
      "try {",
      "  eval(testCode);",
      "  function flushQueue() {",
      "    var curTime = Date.now();",
      "    var empty = true;",
      "    for (var runTime in jobQueue) {",
      "      empty = false;",
      "      if (curTime >= runTime) {",
      "        var jobs = jobQueue[runTime];",
      "        delete jobQueue[runTime];",
      "        jobs.forEach(function (job) { job(); });",
      "      }",
      "    }",
      "    if (!empty) { Promise.resolve().then(flushQueue); }",
      "  }",
      "  Promise.resolve().then(flushQueue);",
      "} catch (e) {}",
    ].join("\n");
  } else if (/\bglobal\.test\b/.test(testCode)) {
    script += [
      "global.test = function (expression) {",
      `  if (expression) { console.log("${SUCCESS_MARKER}"); }`,
      "};",
      "try { eval(testCode); } catch (e) {}",
    ].join("\n");
  } else {
    script += [
      "try {",
      `  if (eval(testCode)) { console.log("${SUCCESS_MARKER}"); }`,
      "} catch (e) {}",
    ].join("\n");
  }
  return script;
}

function blankBucket() {
  return {
    features: 0,
    subtests: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    timeout: 0,
    weighted_earned: 0,
    weighted_possible: 0,
    weighted_percent: 0,
    passed_percent: 0,
  };
}

function round(value, places = 6) {
  const scale = 10 ** places;
  return Math.round((value + Number.EPSILON) * scale) / scale;
}

function finalizeBucket(bucket) {
  const executed = bucket.passed + bucket.failed + bucket.timeout;
  bucket.weighted_earned = round(bucket.weighted_earned);
  bucket.weighted_possible = round(bucket.weighted_possible);
  bucket.weighted_percent = bucket.weighted_possible
    ? round((100 * bucket.weighted_earned) / bucket.weighted_possible)
    : 0;
  bucket.passed_percent = executed
    ? round((100 * bucket.passed) / executed)
    : 0;
  return bucket;
}

function addFeature(bucket, feature, results) {
  const weight = SIGNIFICANCE_WEIGHTS[feature.significance] || 1;
  const passed = results.filter((result) => result.status === "pass").length;
  bucket.features += 1;
  bucket.subtests += results.length;
  bucket.passed += passed;
  bucket.failed += results.filter((result) => result.status === "fail").length;
  bucket.skipped += results.filter((result) => result.status === "skip").length;
  bucket.timeout += results.filter(
    (result) => result.status === "timeout",
  ).length;
  bucket.weighted_possible += weight;
  bucket.weighted_earned += weight * (results.length ? passed / results.length : 0);
}

function mergeBucket(target, source) {
  for (const key of [
    "features",
    "subtests",
    "passed",
    "failed",
    "skipped",
    "timeout",
    "weighted_earned",
    "weighted_possible",
  ]) {
    target[key] += source[key];
  }
}

function outputDetails(run) {
  const stdout = run.stdout ? String(run.stdout) : "";
  const stderr = run.stderr ? String(run.stderr) : "";
  return `${stdout}${stderr}`.trim().slice(0, 2000);
}

function runSubtest(options, testCode, createIterableHelper, annexB, spawn) {
  if (!testCode) {
    return { status: "skip", duration_ms: 0, details: "missing exec" };
  }
  const source = makeScript(testCode, createIterableHelper);
  const args = options.engineArgs.concat(
    annexB ? ["--annex-b", source] : [source],
  );
  const started = process.hrtime.bigint();
  const run = spawn(options.engine, args, {
    encoding: "utf8",
    timeout: options.timeoutMs,
    maxBuffer: 1024 * 1024,
  });
  const durationMs = Number(process.hrtime.bigint() - started) / 1_000_000;
  if (
    (run.error && run.error.code === "ETIMEDOUT") ||
    run.signal === "SIGTERM" ||
    run.signal === "SIGKILL"
  ) {
    return {
      status: "timeout",
      duration_ms: round(durationMs, 3),
      details: outputDetails(run),
    };
  }
  if (run.error) {
    throw new Error(`engine execution failed: ${run.error.message}`);
  }
  const stdout = run.stdout ? String(run.stdout) : "";
  const passed = stdout
    .split(/\r?\n/)
    .some((line) => line.trim() === SUCCESS_MARKER);
  return {
    status: passed ? "pass" : "fail",
    duration_ms: round(durationMs, 3),
    details: passed ? "" : outputDetails(run),
  };
}

function loadSuite(compatTable, suiteName) {
  const suitePath = path.join(compatTable, `data-${suiteName}.js`);
  if (!fs.existsSync(suitePath)) {
    throw new Error(`compat-table suite not found: ${suitePath}`);
  }
  delete require.cache[require.resolve(suitePath)];
  const suite = require(suitePath);
  if (!suite || !Array.isArray(suite.tests) || typeof suite.name !== "string") {
    throw new Error(`invalid compat-table suite: ${suitePath}`);
  }
  return suite;
}

function runCompatTable(options, dependencies = {}) {
  const spawn = dependencies.spawn || spawnSync;
  if (!fs.statSync(options.compatTable).isDirectory()) {
    throw new Error(`not a directory: ${options.compatTable}`);
  }
  if (!fs.statSync(options.engine).isFile()) {
    throw new Error(`engine not found: ${options.engine}`);
  }
  const helperPath = path.join(
    options.compatTable,
    "test-utils",
    "testHelpers.js",
  );
  if (!fs.existsSync(helperPath)) {
    throw new Error(`compat-table helper not found: ${helperPath}`);
  }
  delete require.cache[require.resolve(helperPath)];
  const createIterableHelper = require(helperPath).createIterableHelper;
  if (typeof createIterableHelper !== "string") {
    throw new Error(`invalid createIterableHelper in ${helperPath}`);
  }

  const report = {
    schema_version: 1,
    generated_at: new Date().toISOString(),
    engine: {
      name: "moonbit-js-engine",
      commit: options.engineCommit,
      command: options.engine,
      arguments: options.engineArgs.slice(),
      annex_b_flag: "--annex-b",
    },
    compat_table: {
      repository: "https://github.com/compat-table/compat-table",
      commit: options.compatTableCommit,
    },
    scope: {
      suites: options.suites.slice(),
      headline: "standard features only; Annex B reported separately",
      excluded_by_default: ["esnext", "esintl", "non-standard"],
      timeout_ms: options.timeoutMs,
    },
    methodology: {
      purpose: "feature coverage diagnostic; not an ECMAScript conformance claim",
      weights: { ...SIGNIFICANCE_WEIGHTS },
      weighted_score:
        "each feature weight multiplied by its passing-subtest fraction",
      raw_score: "passed / executed subtests; skipped subtests excluded",
      modes:
        "standard features use the default CLI; Annex B features use --annex-b",
    },
    summary: {
      standard: blankBucket(),
      annex_b: blankBucket(),
    },
    suites: {},
    categories: {},
    results: [],
  };

  for (const suiteName of options.suites) {
    const suite = loadSuite(options.compatTable, suiteName);
    const suiteBuckets = {
      name: suite.name,
      standard: blankBucket(),
      annex_b: blankBucket(),
    };
    for (const feature of suite.tests) {
      const category = feature.category || suite.name;
      const annexB = category.toLowerCase().includes("annex b");
      const leaves = Array.isArray(feature.subtests)
        ? feature.subtests
        : [feature];
      const leafResults = leaves.map((leaf) => {
        const run = runSubtest(
          options,
          extractTestCode(leaf.exec),
          createIterableHelper,
          annexB,
          spawn,
        );
        report.results.push({
          suite: suiteName,
          category,
          feature: feature.name,
          test: leaf.name || feature.name,
          significance: feature.significance || "large",
          annex_b: annexB,
          status: run.status,
          duration_ms: run.duration_ms,
          details: run.details,
        });
        return run;
      });
      const bucketName = annexB ? "annex_b" : "standard";
      addFeature(suiteBuckets[bucketName], feature, leafResults);
      if (!report.categories[category]) {
        report.categories[category] = {
          annex_b: annexB,
          coverage: blankBucket(),
        };
      }
      addFeature(report.categories[category].coverage, feature, leafResults);
    }
    finalizeBucket(suiteBuckets.standard);
    finalizeBucket(suiteBuckets.annex_b);
    mergeBucket(report.summary.standard, suiteBuckets.standard);
    mergeBucket(report.summary.annex_b, suiteBuckets.annex_b);
    report.suites[suiteName] = suiteBuckets;
  }

  finalizeBucket(report.summary.standard);
  finalizeBucket(report.summary.annex_b);
  for (const category of Object.values(report.categories)) {
    finalizeBucket(category.coverage);
  }
  return report;
}

function percent(value) {
  return `${Number(value).toFixed(1)}%`;
}

function ratio(bucket) {
  const executed = bucket.passed + bucket.failed + bucket.timeout;
  return `${bucket.passed} / ${executed}`;
}

function renderTable(report, bucketName) {
  const lines = [
    "| Suite | Weighted coverage | Passed / Executed | Skipped | Timeout |",
    "|---|---:|---:|---:|---:|",
  ];
  for (const suite of Object.values(report.suites)) {
    const bucket = suite[bucketName];
    if (bucket.features === 0) continue;
    lines.push(
      `| ${suite.name} | ${percent(bucket.weighted_percent)} | ${ratio(bucket)} | ${bucket.skipped} | ${bucket.timeout} |`,
    );
  }
  const total = report.summary[bucketName];
  lines.push(
    `| **Total** | **${percent(total.weighted_percent)}** | **${ratio(total)}** | **${total.skipped}** | **${total.timeout}** |`,
  );
  return lines.join("\n");
}

function renderMarkdown(report) {
  const lines = [
    "# compat-table feature coverage",
    "",
    "> This is a feature-coverage diagnostic, not an ECMAScript conformance claim.",
    "> Test262 remains the authoritative conformance and regression suite.",
    "",
    `- js_engine commit: \`${report.engine.commit}\``,
    `- compat-table commit: \`${report.compat_table.commit}\``,
    `- generated: ${report.generated_at}`,
    `- per-subtest timeout: ${report.scope.timeout_ms} ms`,
    "",
    "## Standard feature coverage",
    "",
    renderTable(report, "standard"),
    "",
    "## Annex B feature coverage",
    "",
    "Annex B tests are executed separately with `--annex-b` and are excluded from the standard headline.",
    "",
    renderTable(report, "annex_b"),
    "",
    "## Category detail",
    "",
    "| Category | Mode | Weighted coverage | Passed / Executed | Skipped | Timeout |",
    "|---|---|---:|---:|---:|---:|",
  ];
  for (const [name, category] of Object.entries(report.categories)) {
    const bucket = category.coverage;
    lines.push(
      `| ${name} | ${category.annex_b ? "Annex B" : "standard"} | ${percent(bucket.weighted_percent)} | ${ratio(bucket)} | ${bucket.skipped} | ${bucket.timeout} |`,
    );
  }
  lines.push(
    "",
    "## Methodology",
    "",
    "compat-table weights top-level features as large = 1, medium = 0.5, small = 0.25, and tiny = 0.125. A feature with subtests earns its weight in proportion to the subtests that pass. The raw count is also reported so the weighted headline is never presented without its denominator.",
    "",
    "ESNext proposals, Intl, and non-standard extensions are outside the default run. Expected feature failures do not make the runner exit non-zero; only invalid inputs or runner/infrastructure failures do.",
    "",
  );
  return lines.join("\n");
}

function main(argv, dependencies = {}) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(usage());
    return;
  }
  const report = runCompatTable(options, dependencies);
  const markdown = renderMarkdown(report);
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.mkdirSync(path.dirname(options.markdown), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  fs.writeFileSync(options.markdown, markdown);
  const stdout = dependencies.stdout || process.stdout;
  stdout.write(markdown);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`compat-table runner error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  addFeature,
  blankBucket,
  extractTestCode,
  finalizeBucket,
  main,
  makeScript,
  parseArgs,
  renderMarkdown,
  runCompatTable,
};
