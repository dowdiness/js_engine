#!/usr/bin/env node

"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { main: runJsEngine } = require("./jetstream3_admission.js");
const { main: runJavaScriptCore } = require(
  "./jetstream3_javascriptcore_probe.js"
);
const { main: runSpiderMonkey } = require(
  "./jetstream3_spidermonkey_probe.js"
);
const {
  validateCommonSpec,
} = require("./jetstream3_reference_probe_core.js");
const { main: runV8 } = require("./jetstream3_v8_probe.js");

const EXPERIMENT = "jetstream3-cross-engine-feasibility";
const MEASUREMENT_PROFILE = "upstream-default";
const DEFAULT_TIMEOUT_MS = 900_000;
const EXPECTED_MEMBERS = ["js_engine", "v8", "javascriptcore", "spidermonkey"];
const SPEC_FILES = {
  javascriptcore: "jetstream3_javascriptcore_probe.json",
  spidermonkey: "jetstream3_spidermonkey_probe.json",
  v8: "jetstream3_v8_probe.json",
};
const DEFAULT_RUNNERS = {
  javascriptcore: runJavaScriptCore,
  jsEngine: runJsEngine,
  spidermonkey: runSpiderMonkey,
  v8: runV8,
};

function usage() {
  return `Usage: node scripts/jetstream3_reference_experiment.js [options]

Required:
  --jetstream DIR       pinned JetStream checkout
  --engine FILE         native release js_engine executable
  --jsvu-root DIR       directory containing pinned jsvu engine payloads
  --output-dir DIR      experiment evidence directory

Options:
  --engine-commit SHA   js_engine revision recorded in evidence
  --engine-tree-state STATE
                        clean, dirty, or unknown (default: unknown)
  --timeout-ms N        timeout for each probe (default: 900000)
  --help                show this help
`;
}

function parseArgs(argv, environment) {
  const options = {
    engineCommit: environment.GITHUB_SHA || "unknown",
    engineTreeState: "unknown",
    timeoutMs: DEFAULT_TIMEOUT_MS,
  };
  const valueOptions = new Set([
    "--engine",
    "--engine-commit",
    "--engine-tree-state",
    "--jetstream",
    "--jsvu-root",
    "--output-dir",
    "--timeout-ms",
  ]);
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help") {
      options.help = true;
      continue;
    }
    if (!valueOptions.has(arg)) throw new Error(`unknown option: ${arg}`);
    if (index + 1 >= argv.length) throw new Error(`${arg} requires a value`);
    const value = argv[(index += 1)];
    if (arg === "--engine") options.engine = value;
    if (arg === "--engine-commit") options.engineCommit = value;
    if (arg === "--engine-tree-state") options.engineTreeState = value;
    if (arg === "--jetstream") options.jetstream = value;
    if (arg === "--jsvu-root") options.jsvuRoot = value;
    if (arg === "--output-dir") options.outputDir = value;
    if (arg === "--timeout-ms") options.timeoutMs = Number(value);
  }
  if (options.help) return options;
  for (const required of ["engine", "jetstream", "jsvuRoot", "outputDir"]) {
    if (!options[required]) throw new Error(`missing required option: ${required}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs <= 0) {
    throw new Error("--timeout-ms must be a positive integer");
  }
  if (!new Set(["clean", "dirty", "unknown"]).has(options.engineTreeState)) {
    throw new Error("--engine-tree-state must be clean, dirty, or unknown");
  }
  for (const field of ["engine", "jetstream", "jsvuRoot", "outputDir"]) {
    options[field] = path.resolve(options[field]);
  }
  return options;
}

function readSpecifications() {
  return Object.entries(SPEC_FILES).map(([member, filename]) => {
    const absolute = path.join(__dirname, filename);
    const bytes = fs.readFileSync(absolute);
    return {
      member,
      filename,
      sha256: crypto.createHash("sha256").update(bytes).digest("hex"),
      spec: JSON.parse(bytes.toString("utf8")),
    };
  });
}

function validateSpecifications(specifications) {
  const expected = Object.keys(SPEC_FILES).sort();
  const actual = specifications.map(({ member }) => member).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("candidate specifications must contain the fixed cohort");
  }
  const sharedFields = [
    "generation",
    "platform",
    "jsvu_version",
    "jetstream_commit",
    "workload",
  ];
  const first = specifications[0].spec;
  for (const entry of specifications) {
    for (const field of sharedFields) {
      if (entry.spec[field] !== first[field]) {
        throw new Error(`candidate specifications must use the same ${field}`);
      }
    }
    validateCommonSpec(entry.spec);
    if (entry.spec.engine.id !== entry.member) {
      throw new Error("candidate specification member must match engine.id");
    }
  }
  return specifications;
}

function buildMembers(options, specifications, runners) {
  const byId = new Map(specifications.map((entry) => [entry.member, entry]));
  return [
    {
      id: "js_engine",
      run(output) {
        return runners.jsEngine([
          "--jetstream",
          options.jetstream,
          "--jetstream-commit",
          byId.get("v8").spec.jetstream_commit,
          "--engine",
          options.engine,
          "--engine-commit",
          options.engineCommit,
          "--engine-tree-state",
          options.engineTreeState,
          "--workload",
          byId.get("v8").spec.workload,
          "--timeout-ms",
          String(options.timeoutMs),
          "--measurement-profile",
          MEASUREMENT_PROFILE,
          "--output",
          output,
        ]);
      },
    },
    ...[
      ["v8", runners.v8],
      ["javascriptcore", runners.javascriptcore],
      ["spidermonkey", runners.spidermonkey],
    ].map(([id, run]) => {
      const specification = byId.get(id);
      return {
        id,
        run(output) {
          return run([
            "--spec",
            path.join(__dirname, specification.filename),
            "--jetstream",
            options.jetstream,
            "--engine-root",
            path.join(options.jsvuRoot, specification.spec.engine.executable),
            "--timeout-ms",
            String(options.timeoutMs),
            "--measurement-profile",
            MEASUREMENT_PROFILE,
            "--output",
            output,
          ]);
        },
      };
    }),
  ];
}

function main(argv, dependencies = {}) {
  const environment = dependencies.environment || process.env;
  const stdout = dependencies.stdout || process.stdout;
  const now = dependencies.now || Date.now;
  const options = parseArgs(argv, environment);
  if (options.help) {
    stdout.write(usage());
    return "help";
  }
  if (
    fs.existsSync(options.outputDir) &&
    fs.readdirSync(options.outputDir).length > 0
  ) {
    throw new Error("output directory must be empty");
  }

  const specifications = validateSpecifications(
    (dependencies.readSpecifications || readSpecifications)(),
  );
  const members = buildMembers(
    options,
    specifications,
    dependencies.runners || DEFAULT_RUNNERS,
  );
  const byId = new Map(members.map((member) => [member.id, member]));
  const schedule = [EXPECTED_MEMBERS, [...EXPECTED_MEMBERS].reverse()];
  const observations = [];
  fs.mkdirSync(options.outputDir, { recursive: true });

  for (let pass = 0; pass < schedule.length; pass += 1) {
    for (let ordinal = 0; ordinal < schedule[pass].length; ordinal += 1) {
      const id = schedule[pass][ordinal];
      const member = byId.get(id);
      const filename = `pass-${pass + 1}-${id}.json`;
      const output = path.join(options.outputDir, filename);
      const started = now();
      let outcome;
      let failure;
      try {
        outcome = dependencies.runMember
          ? dependencies.runMember(member, output)
          : member.run(output);
      } catch (error) {
        outcome = "experiment_failed";
        failure = { message: error.message };
      }
      const ended = now();
      const observation = {
        pass: pass + 1,
        ordinal: ordinal + 1,
        member: id,
        outcome,
        raw_report: fs.existsSync(output) ? filename : null,
        started_at: new Date(started).toISOString(),
        ended_at: new Date(ended).toISOString(),
        duration_ms: Math.max(0, ended - started),
      };
      if (failure) observation.failure = failure;
      observations.push(observation);
    }
  }

  const index = {
    schema_version: 1,
    experiment: EXPERIMENT,
    generated_at: new Date(now()).toISOString(),
    timings_are_diagnostic_only: true,
    valid: observations.every(
      ({ member, outcome, raw_report }) =>
        raw_report !== null &&
        outcome === (member === "js_engine" ? "admitted" : "compatible"),
    ),
    inputs: {
      generation: specifications[0].spec.generation,
      platform: specifications[0].spec.platform,
      jsvu_version: specifications[0].spec.jsvu_version,
      jetstream_commit: specifications[0].spec.jetstream_commit,
      workload: specifications[0].spec.workload,
      measurement_profile: MEASUREMENT_PROFILE,
      iteration_count_override: null,
      worst_case_count_override: null,
      ordered_members: EXPECTED_MEMBERS,
      passes: schedule.length,
      schedule: "forward_reverse",
    },
    source: {
      repository_commit: environment.GITHUB_SHA || options.engineCommit,
      workflow_commit: environment.GITHUB_WORKFLOW_SHA || "unknown",
      specifications: specifications.map(({ member, filename, sha256 }) => ({
        member,
        path: `scripts/${filename}`,
        sha256,
      })),
    },
    workflow: {
      run_id: environment.GITHUB_RUN_ID || "local",
      run_attempt: environment.GITHUB_RUN_ATTEMPT || "1",
    },
    runner: {
      os: environment.RUNNER_OS || os.platform(),
      architecture: environment.RUNNER_ARCH || os.arch(),
      os_release: os.release(),
      node_version: process.version,
    },
    observations,
  };
  fs.writeFileSync(
    path.join(options.outputDir, "run-index.json"),
    `${JSON.stringify(index, null, 2)}\n`,
  );
  const result = index.valid ? "complete" : "invalid";
  stdout.write(`${JSON.stringify({ output: options.outputDir, result })}\n`);
  return result;
}

if (require.main === module) {
  try {
    const result = main(process.argv.slice(2));
    if (result === "invalid") process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`JetStream 3 reference experiment error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = { main, parseArgs };
