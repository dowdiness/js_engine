#!/usr/bin/env node

"use strict";

const {
  payloadFingerprint,
  runReferenceProbe,
  validateCommonSpec,
} = require("./jetstream3_reference_probe_core.js");

const usage = `Usage: node scripts/jetstream3_v8_probe.js [options]

Required:
  --spec FILE          source-controlled V8 probe specification
  --jetstream DIR      checkout at the specification's JetStream revision
  --engine-root DIR    installed jsvu engine payload directory

Options:
  --output FILE        probe report (default: jetstream3-v8-probe.json)
  --timeout-ms N       timeout for each compatibility probe (default: 180000)
  --help               show this help
`;

function validateProbeSpec(spec) {
  validateCommonSpec(spec);
  if (spec.engine.id !== "v8") {
    throw new Error("engine.id must be v8");
  }
  if (spec.engine.jsvu_engine !== "v8") {
    throw new Error("engine.jsvu_engine must be v8");
  }
  return spec;
}

function buildCommands({ cli, spec }) {
  return {
    discovery: [
      cli,
      "--",
      "--no-prefetch",
      "--dump-test-list",
      `--test=${spec.workload}`,
    ],
    execution: [
      cli,
      "--",
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
      defaultOutput: "jetstream3-v8-probe.json",
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
    process.stderr.write(`JetStream 3 V8 probe error: ${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  main,
  payloadFingerprint,
  validateProbeSpec,
};
