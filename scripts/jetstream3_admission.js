#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const DEFAULT_TIMEOUT_MS = 180_000;
const DEFAULT_WORKLOAD = "raytrace";

function usage() {
  return `Usage: node scripts/jetstream3_admission.js [options]

Required:
  --jetstream DIR            pinned JetStream checkout
  --jetstream-commit SHA     expected upstream commit
  --engine FILE              native release js_engine executable

Options:
  --engine-commit SHA        js_engine revision recorded in the report
  --engine-tree-state STATE  clean, dirty, or unknown (default: unknown)
  --workload NAME            selected JetStream workload (default: raytrace)
  --output FILE              JSON report (default: jetstream3-admission.json)
  --timeout-ms N             timeout for each probe (default: 180000)
  --help                     show this help
`;
}

function parseArgs(argv) {
  const options = {
    engineCommit: process.env.GITHUB_SHA || "unknown",
    engineTreeState: "unknown",
    output: "jetstream3-admission.json",
    timeoutMs: DEFAULT_TIMEOUT_MS,
    workload: DEFAULT_WORKLOAD,
  };
  const valueOptions = new Set([
    "--engine",
    "--engine-commit",
    "--engine-tree-state",
    "--jetstream",
    "--jetstream-commit",
    "--output",
    "--timeout-ms",
    "--workload",
  ]);
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (!valueOptions.has(arg)) throw new Error(`unknown option: ${arg}`);
    if (i + 1 >= argv.length) throw new Error(`${arg} requires a value`);
    const value = argv[(i += 1)];
    switch (arg) {
      case "--engine":
        options.engine = value;
        break;
      case "--engine-commit":
        options.engineCommit = value;
        break;
      case "--engine-tree-state":
        options.engineTreeState = value;
        break;
      case "--jetstream":
        options.jetstream = value;
        break;
      case "--jetstream-commit":
        options.jetstreamCommit = value;
        break;
      case "--output":
        options.output = value;
        break;
      case "--timeout-ms":
        options.timeoutMs = Number(value);
        break;
      case "--workload":
        options.workload = value;
        break;
      default:
        throw new Error(`unhandled option: ${arg}`);
    }
  }
  if (options.help) return options;
  for (const required of ["engine", "jetstream", "jetstreamCommit"]) {
    if (!options[required]) throw new Error(`missing required option: ${required}`);
  }
  if (!/^[0-9a-f]{40}$/.test(options.jetstreamCommit)) {
    throw new Error("--jetstream-commit must be a full 40-character commit SHA");
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive integer");
  }
  if (!new Set(["clean", "dirty", "unknown"]).has(options.engineTreeState)) {
    throw new Error("--engine-tree-state must be clean, dirty, or unknown");
  }
  options.engine = path.resolve(options.engine);
  options.jetstream = path.resolve(options.jetstream);
  options.output = path.resolve(options.output);
  return options;
}

function processFailure(probe) {
  if (probe.error) return `process launch failed: ${probe.error}`;
  if (probe.signal) return `process terminated by ${probe.signal}`;
  if (probe.status !== 0) return `process exited with status ${probe.status}`;
  return null;
}

function parseResult(stdout) {
  for (const line of stdout.split(/\r?\n/).reverse()) {
    const candidate = line.trim();
    if (!candidate.startsWith("{")) continue;
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && parsed["JetStream3.0"]) {
        return { error: null, value: parsed };
      }
    } catch (_error) {
      // A non-result diagnostic may begin with `{`; continue looking upward.
    }
  }
  return { error: "structured JetStream result was not found", value: null };
}

function validateWorkloadResult(result, workload) {
  const tests = result?.["JetStream3.0"]?.tests;
  const workloadNames =
    tests && typeof tests === "object" && !Array.isArray(tests)
      ? Object.keys(tests)
      : [];
  if (workloadNames.length !== 1 || workloadNames[0] !== workload) {
    return `structured result does not contain only '${workload}'`;
  }
  const workloadResult = tests[workload];
  if (!workloadResult || typeof workloadResult !== "object") {
    return `structured result does not contain '${workload}'`;
  }
  const scores = workloadResult.metrics?.Score?.current;
  if (
    !Array.isArray(scores) ||
    scores.length !== 1 ||
    !Number.isFinite(scores[0]) ||
    scores[0] <= 0
  ) {
    return `'${workload}' does not contain one positive finite score`;
  }
  return null;
}

function stage(name, errors) {
  return {
    name,
    status: errors.length === 0 ? "pass" : "fail",
    evidence_errors: errors,
  };
}

function assessAdmission(probes, workload) {
  const discoveryErrors = [];
  const discoveryProcessFailure = processFailure(probes.discovery);
  if (discoveryProcessFailure) discoveryErrors.push(discoveryProcessFailure);
  const discovered = probes.discovery.stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  if (discovered.length !== 1 || discovered[0] !== workload) {
    discoveryErrors.push(`selected test discovery did not return only '${workload}'`);
  }

  const executionErrors = [];
  const executionProcessFailure = processFailure(probes.execution);
  if (executionProcessFailure) executionErrors.push(executionProcessFailure);

  const parsed = parseResult(probes.execution.stdout);
  const structuredErrors = parsed.error ? [parsed.error] : [];
  const validationErrors = [];
  if (parsed.value) {
    const validationFailure = validateWorkloadResult(parsed.value, workload);
    if (validationFailure) validationErrors.push(validationFailure);
  } else {
    validationErrors.push("workload completion and validation were not observed");
  }

  const stages = [
    stage("test_discovery", discoveryErrors),
    stage("workload_execution", executionErrors),
    stage("workload_result_validation", validationErrors),
    stage("structured_result", structuredErrors),
  ];
  const evidenceErrors = stages.flatMap((entry) =>
    entry.evidence_errors.map((message) => `${entry.name}: ${message}`),
  );
  return {
    result: evidenceErrors.length === 0 ? "admitted" : "not_admitted",
    stages,
    evidence_errors: evidenceErrors,
  };
}

function runProbe(name, engine, args, options, dependencies) {
  const spawn = dependencies.spawn || spawnSync;
  const now = dependencies.now || Date.now;
  const started = now();
  const result = spawn(engine, args, {
    cwd: options.jetstream,
    encoding: "utf8",
    timeout: options.timeoutMs,
  });
  const ended = now();
  return {
    name,
    command: [engine, ...args],
    duration_ms: Math.max(0, ended - started),
    error: result.error ? result.error.message : null,
    signal: result.signal || null,
    status: result.status,
    stderr: result.stderr || "",
    stdout: result.stdout || "",
  };
}

function readRevision(root) {
  const result = spawnSync("git", ["-C", root, "rev-parse", "HEAD"], {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(`cannot read JetStream revision: ${result.stderr.trim()}`);
  }
  return result.stdout.trim();
}

function readTreeState(root) {
  const result = spawnSync(
    "git",
    ["-C", root, "status", "--porcelain", "--untracked-files=all"],
    { encoding: "utf8" },
  );
  if (result.status !== 0) {
    throw new Error(`cannot inspect JetStream checkout: ${result.stderr.trim()}`);
  }
  return result.stdout.trim() === "" ? "clean" : "dirty";
}

function readMoonBitVersion() {
  const result = spawnSync("moon", ["version"], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error("cannot read MoonBit version");
  }
  return `${result.stdout}${result.stderr}`.trim().split(/\r?\n/)[0];
}

function main(argv, dependencies = {}) {
  const options = parseArgs(argv);
  const stdout = dependencies.stdout || process.stdout;
  if (options.help) {
    stdout.write(usage());
    return "help";
  }
  if (!fs.statSync(options.jetstream).isDirectory()) {
    throw new Error("--jetstream must name a directory");
  }
  if (!fs.statSync(options.engine).isFile()) {
    throw new Error("--engine must name a file");
  }
  if (!fs.statSync(path.join(options.jetstream, "cli.js")).isFile()) {
    throw new Error("JetStream checkout is missing cli.js");
  }
  const actualRevision = (dependencies.readRevision || readRevision)(
    options.jetstream,
  );
  if (actualRevision !== options.jetstreamCommit) {
    throw new Error(
      `JetStream revision mismatch: expected ${options.jetstreamCommit}, got ${actualRevision}`,
    );
  }
  const treeState = (dependencies.readTreeState || readTreeState)(
    options.jetstream,
  );
  if (treeState !== "clean") {
    throw new Error("JetStream checkout has local modifications");
  }

  const cli = path.join(options.jetstream, "cli.js");
  const moonbitVersion = (
    dependencies.readMoonBitVersion || readMoonBitVersion
  )();
  const common = [cli, "--", "--no-prefetch"];
  const discovery = runProbe(
    "test_discovery",
    options.engine,
    [...common, "--dump-test-list", `--test=${options.workload}`],
    options,
    dependencies,
  );
  const execution = runProbe(
    "workload_execution",
    options.engine,
    [
      cli,
      "--",
      `--test=${options.workload}`,
      "--iteration-count=2",
      "--worst-case-count=1",
      "--no-prefetch",
      "--dump-json-results",
    ],
    options,
    dependencies,
  );
  const probes = { discovery, execution };
  const assessment = assessAdmission(probes, options.workload);
  const now = dependencies.now || Date.now;
  const report = {
    schema_version: 1,
    generated_at: new Date(now()).toISOString(),
    jetstream: {
      commit: options.jetstreamCommit,
      path: options.jetstream,
    },
    engine: {
      commit: options.engineCommit,
      tree_state: options.engineTreeState,
      path: options.engine,
      target: "native",
      profile: "release",
    },
    environment: {
      moonbit_version: moonbitVersion,
      node_version: process.version,
      platform: os.platform(),
      architecture: os.arch(),
      os_release: os.release(),
    },
    scope: {
      workload: options.workload,
      iteration_count: 2,
      worst_case_count: 1,
      prefetch: false,
      timeout_ms: options.timeoutMs,
      timings_are_diagnostic_only: true,
    },
    assessment,
    probes: [discovery, execution],
  };
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  stdout.write(
    `${JSON.stringify({ output: options.output, result: assessment.result })}\n`,
  );
  return assessment.result;
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`JetStream 3 admission error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  assessAdmission,
  main,
  parseArgs,
  validateWorkloadResult,
};
