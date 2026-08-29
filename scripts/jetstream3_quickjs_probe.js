#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const {
  parseProbeArgs,
  payloadFingerprint,
  requireString,
  runReferenceProbe,
  validateCommonSpec,
} = require("./jetstream3_reference_probe_core.js");

const usage = `Usage: node scripts/jetstream3_quickjs_probe.js [options]

Required:
  --spec FILE          source-controlled QuickJS-ng probe specification
  --jetstream DIR      checkout at the specification's JetStream revision
  --engine-root DIR    installed jsvu engine payload directory

Options:
  --output FILE        probe report (default: jetstream3-quickjs-probe.json)
  --timeout-ms N       timeout for each compatibility probe (default: 180000)
  --help               show this help
`;

function validateProbeSpec(spec) {
  validateCommonSpec(spec);
  const engine = spec.engine;
  requireString(engine.shell_adapter, "engine.shell_adapter");
  if (engine.id !== "quickjs-ng") {
    throw new Error("engine.id must be quickjs-ng");
  }
  if (engine.jsvu_engine !== "quickjs") {
    throw new Error("engine.jsvu_engine must be quickjs");
  }
  if (
    path.isAbsolute(engine.shell_adapter) ||
    engine.shell_adapter.split(/[\\/]/).includes("..")
  ) {
    throw new Error("engine.shell_adapter must stay beside the specification");
  }
  return spec;
}

function parseArgs(argv) {
  return parseProbeArgs(argv, "jetstream3-quickjs-probe.json");
}

function buildCommands({ cli, options, spec }) {
  const shellAdapter = path.resolve(
    path.dirname(options.spec),
    spec.engine.shell_adapter,
  );
  if (!fs.statSync(shellAdapter).isFile()) {
    throw new Error("specified shell adapter is not beside the specification");
  }
  const prefix = ["--std", "-I", shellAdapter, cli, "--"];
  return {
    discovery: [
      ...prefix,
      "--no-prefetch",
      "--dump-test-list",
      `--test=${spec.workload}`,
    ],
    execution: [
      ...prefix,
      `--test=${spec.workload}`,
      "--iteration-count=2",
      "--worst-case-count=1",
      "--no-prefetch",
      "--dump-json-results",
    ],
  };
}

function main(argv, dependencies = {}) {
  return runReferenceProbe(
    argv,
    {
      buildCommands,
      defaultOutput: "jetstream3-quickjs-probe.json",
      reportEngineFields: (spec) => ({
        shell_adapter: spec.engine.shell_adapter,
      }),
      usage,
      validateSpec: validateProbeSpec,
    },
    dependencies,
  );
}

if (require.main === module) {
  try {
    const result = main(process.argv.slice(2));
    if (result === "probe_failed") process.exitCode = 1;
  } catch (error) {
    process.stderr.write(`JetStream 3 QuickJS-ng probe error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  main,
  parseArgs,
  payloadFingerprint,
  validateProbeSpec,
};
