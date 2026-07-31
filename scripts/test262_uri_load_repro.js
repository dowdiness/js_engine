#!/usr/bin/env node

"use strict";

// Runner-level evidence harness for #695.  It intentionally invokes the
// authoritative native Test262 runner unchanged; this file only records the
// isolated-vs-four-worker comparison and the timeout control.

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const TICKET = 695;
const LOAD_WORKERS = 4;
const ISOLATED_WORKERS = 1;
const MODES = ["strict", "non-strict"];
const URI_CASES = [
  "built-ins/encodeURI/S15.1.3.3_A2.3_T1.js",
  "built-ins/encodeURIComponent/S15.1.3.4_A2.3_T1.js",
];

function repositoryRoot() {
  return path.resolve(__dirname, "..");
}

function reviewPath(root, file) {
  const relative = path.relative(root, file);
  return relative === "" ? "." : relative;
}

function defaultEngine(root) {
  return `node ${path.join(root, "_build/js/release/build/cmd/main/main.js")}`;
}

function usage() {
  return `Usage: node scripts/test262_uri_load_repro.js [options]

Options:
  --runner PATH       authoritative native test262 runner executable
  --engine COMMAND    runner --engine command (default: JS release bundle)
  --profile NAME      engine target/profile label (default: js-release)
  --test262 DIR       Test262 checkout (default: ./test262)
  --control FILE      known-hang control test
  --iterations N      repeats per mode/condition (default: 3)
  --timeout N         runner timeout in seconds (default: 5)
  --output FILE       reviewable JSON result (default: issue-695-uri-load.json)
  --help              show this help

The load condition uses the existing runner --threads 4 setting.  The
isolated condition uses --threads 1 with the identical four URI tasks.
No runner timeout, worker count, or CI policy is changed by this harness.
`;
}

function parsePositiveInt(raw, label) {
  if (!/^\d+$/.test(raw)) throw new Error(`${label} must be a positive integer`);
  const value = Number(raw);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`${label} must be a positive integer`);
  }
  return value;
}

function parseArgs(argv) {
  const root = repositoryRoot();
  const options = {
    runner: path.join(
      root,
      "_build/native/debug/build/cmd/test262_runner/test262_runner.exe",
    ),
    engine: defaultEngine(root),
    profile: "js-release",
    test262: path.join(root, "test262"),
    control: path.join(root, "scripts/test262_uri_load/known_hang.js"),
    iterations: 3,
    timeout: 5,
    output: path.join(root, "issue-695-uri-load.json"),
    repoRoot: root,
  };
  const valueOptions = new Set([
    "--runner",
    "--engine",
    "--profile",
    "--test262",
    "--control",
    "--iterations",
    "--timeout",
    "--output",
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (!valueOptions.has(arg)) throw new Error(`unknown option: ${arg}`);
    if (index + 1 >= argv.length) throw new Error(`${arg} requires a value`);
    const value = argv[++index];
    switch (arg) {
      case "--runner":
        options.runner = path.resolve(value);
        break;
      case "--engine":
        options.engine = value;
        break;
      case "--profile":
        options.profile = value;
        break;
      case "--test262":
        options.test262 = path.resolve(value);
        break;
      case "--control":
        options.control = path.resolve(value);
        break;
      case "--iterations":
        options.iterations = parsePositiveInt(value, "--iterations");
        break;
      case "--timeout":
        options.timeout = parsePositiveInt(value, "--timeout");
        break;
      case "--output":
        options.output = path.resolve(value);
        break;
      default:
        throw new Error(`unhandled option: ${arg}`);
    }
  }
  return options;
}

function requireFile(file, description) {
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) {
    throw new Error(`${description} not found: ${file}`);
  }
}

function validateInputs(options) {
  requireFile(options.runner, "runner executable");
  if (!fs.existsSync(options.test262) || !fs.statSync(options.test262).isDirectory()) {
    throw new Error(`test262 directory not found: ${options.test262}`);
  }
  for (const relative of URI_CASES) {
    requireFile(path.join(options.test262, "test", relative), `URI case ${relative}`);
  }
  requireFile(options.control, "known-hang control");
}

function safeName(value) {
  return value.replace(/[^A-Za-z0-9_.-]+/g, "_");
}

function writeTestsFile(directory, name, entries) {
  const file = path.join(directory, `${safeName(name)}.tests.txt`);
  fs.writeFileSync(file, `${entries.join("\n")}\n`);
  return file;
}

function elapsedMilliseconds(start) {
  return Number(process.hrtime.bigint() - start) / 1e6;
}

function roundMilliseconds(value) {
  return Math.round(value * 10) / 10;
}

function readRunnerArtifact(file) {
  if (!fs.existsSync(file)) return null;
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    return { parse_error: String(error) };
  }
}

function invokeRunner(options, temporary, descriptor, entries, threads) {
  const testsFile = writeTestsFile(temporary, descriptor.id, entries);
  const resultFile = path.join(temporary, `${safeName(descriptor.id)}.json`);
  const args = [
    "--engine",
    options.engine,
    "--test262",
    options.test262,
    "--tests-file",
    testsFile,
    "--mode",
    descriptor.mode,
    "--threads",
    String(threads),
    "--timeout",
    String(options.timeout),
    "--output",
    resultFile,
    "--summary",
  ];
  const command = [options.runner, ...args];
  const reviewCommand = command.map(value => {
    if (value === testsFile) return "<tests-file>";
    if (value === resultFile) return "<result-file>";
    if (value === options.runner) return reviewPath(options.repoRoot, value);
    if (value === options.test262) return reviewPath(options.repoRoot, value);
    return value;
  });
  const start = process.hrtime.bigint();
  // The runner owns per-test timeout semantics.  This outer bound only guards
  // a runner process that fails to return after its own results are written.
  const outerTimeoutMs = Math.max(
    60_000,
    options.timeout * 1000 * (entries.length + 2) + 60_000,
  );
  const completed = spawnSync(options.runner, args, {
    cwd: options.repoRoot,
    encoding: "utf8",
    timeout: outerTimeoutMs,
    maxBuffer: 16 * 1024 * 1024,
  });
  const artifact = readRunnerArtifact(resultFile);
  const processExit = Number.isInteger(completed.status) ? completed.status : null;
  const outerTimeout = completed.error?.code === "ETIMEDOUT";
  return {
    id: descriptor.id,
    condition: descriptor.condition,
    mode: descriptor.mode,
    iteration: descriptor.iteration ?? null,
    threads,
    tests: entries.map(entry =>
      entry === options.control ? "<control-file>" : entry,
    ),
    command: reviewCommand,
    timeout_seconds: options.timeout,
    wall_duration_ms: roundMilliseconds(elapsedMilliseconds(start)),
    process_exit: processExit,
    signal: completed.signal ?? null,
    outer_timeout: outerTimeout,
    stdout: completed.stdout ?? "",
    stderr: completed.stderr ?? "",
    summary: artifact?.summary ?? null,
    results: artifact?.results ?? [],
    artifact_error: artifact?.parse_error ?? null,
  };
}

function uriTasks() {
  // Four tasks mirror the existing runner's four-worker setting while keeping
  // isolation and load measurements apples-to-apples.
  return [URI_CASES[0], URI_CASES[1], URI_CASES[0], URI_CASES[1]];
}

function countStatus(runs, status) {
  return runs.reduce(
    (count, run) =>
      count + run.results.filter(result => result.status === status).length,
    0,
  );
}

function durationStatistics(runs) {
  const durations = runs.flatMap(run =>
    run.results
      .map(result => result.duration_ms)
      .filter(value => typeof value === "number" && Number.isFinite(value)),
  );
  if (durations.length === 0) {
    return { count: 0, min_ms: null, max_ms: null, mean_ms: null };
  }
  const total = durations.reduce((sum, value) => sum + value, 0);
  return {
    count: durations.length,
    min_ms: Math.min(...durations),
    max_ms: Math.max(...durations),
    mean_ms: roundMilliseconds(total / durations.length),
  };
}

function assessment(runs) {
  const isolated = runs.filter(run => run.condition === "isolated");
  const load = runs.filter(run => run.condition === "load");
  const isolatedTimeouts = countStatus(isolated, "timeout");
  const loadTimeouts = countStatus(load, "timeout");
  const isolatedDurations = durationStatistics(isolated);
  const loadDurations = durationStatistics(load);
  const slowdownRatio =
    isolatedDurations.mean_ms && loadDurations.mean_ms
      ? roundMilliseconds(loadDurations.mean_ms / isolatedDurations.mean_ms)
      : null;
  let result;
  let rationale;
  if (loadTimeouts > isolatedTimeouts) {
    result = "supported";
    rationale =
      "URI timeout frequency increased under the existing four-worker setting; CPU/scheduling contention remains the leading hypothesis.";
  } else if (loadTimeouts === 0 && isolatedTimeouts === 0) {
    result = "not_reproduced";
    rationale =
      "Neither condition timed out in this sample; the reported contention hypothesis was not reproduced.";
  } else if (loadTimeouts < isolatedTimeouts) {
    result = "rejected";
    rationale =
      "Timeouts occurred no more often under four workers than in isolation; CPU/scheduling contention is not supported by this sample.";
  } else {
    result = "inconclusive";
    rationale =
      "Timeout counts were equal across conditions; repeat with the same release profile before choosing a mitigation.";
  }
  return {
    result,
    rationale,
    isolated_uri_timeouts: isolatedTimeouts,
    load_uri_timeouts: loadTimeouts,
    isolated_uri_passes: countStatus(isolated, "pass"),
    load_uri_passes: countStatus(load, "pass"),
    isolated_uri_durations_ms: isolatedDurations,
    load_uri_durations_ms: loadDurations,
    load_to_isolated_duration_ratio: slowdownRatio,
  };
}

function invocationError(run) {
  if (run.outer_timeout) return `${run.id}: outer process timeout`;
  if (run.process_exit !== 0) {
    return `${run.id}: runner exit ${run.process_exit ?? "unknown"}`;
  }
  if (run.artifact_error) return `${run.id}: ${run.artifact_error}`;
  if (!run.summary || !Array.isArray(run.results)) {
    return `${run.id}: runner did not produce a result artifact`;
  }
  return null;
}

function main() {
  let options;
  try {
    options = parseArgs(process.argv.slice(2));
    if (options.help) {
      process.stdout.write(usage());
      return;
    }
    validateInputs(options);
  } catch (error) {
    process.stderr.write(`error: ${error.message}\n\n${usage()}`);
    process.exitCode = 2;
    return;
  }

  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "issue-695-uri-load-"));
  const runs = [];
  const controls = [];
  try {
    for (const mode of MODES) {
      for (const [condition, threads] of [
        ["isolated", ISOLATED_WORKERS],
        ["load", LOAD_WORKERS],
      ]) {
        for (let iteration = 1; iteration <= options.iterations; iteration += 1) {
          runs.push(
            invokeRunner(
              options,
              temporary,
              { id: `${condition}-${mode}-${iteration}`, condition, mode, iteration },
              uriTasks(),
              threads,
            ),
          );
        }
        controls.push(
          invokeRunner(
            options,
            temporary,
            { id: `control-${condition}-${mode}`, condition, mode },
            [options.control],
            threads,
          ),
        );
      }
    }
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }

  const artifact = {
    schema_version: 1,
    ticket: TICKET,
    generated_at: new Date().toISOString(),
    git_commit: process.env.GITHUB_SHA || "unknown",
    engine: {
      command: options.engine,
      profile: options.profile,
    },
    test262_directory: reviewPath(options.repoRoot, options.test262),
    test262_revision: process.env.TEST262_COMMIT || "unknown",
    runner: {
      executable: reviewPath(options.repoRoot, options.runner),
      timeout_seconds: options.timeout,
      isolated_workers: ISOLATED_WORKERS,
      load_workers: LOAD_WORKERS,
      iterations: options.iterations,
    },
    uri_cases: URI_CASES,
    known_hang_control: reviewPath(options.repoRoot, options.control),
    runs,
    controls,
    assessment: assessment(runs),
  };
  artifact.execution_errors = [...runs, ...controls]
    .map(invocationError)
    .filter(error => error !== null);
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(artifact, null, 2)}\n`);
  process.stdout.write(
    `#695 wrote ${options.output} (${runs.length} URI runs, ${controls.length} controls)\n`,
  );
  if (artifact.execution_errors.length > 0) process.exitCode = 1;
}

main();
