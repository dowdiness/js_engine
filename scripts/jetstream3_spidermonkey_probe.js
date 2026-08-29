#!/usr/bin/env node

"use strict";

const {
  payloadFingerprint,
  runReferenceProbe,
  validateCommonSpec,
} = require("./jetstream3_reference_probe_core.js");

const usage = `Usage: node scripts/jetstream3_spidermonkey_probe.js [options]

Required:
  --spec FILE          source-controlled SpiderMonkey probe specification
  --jetstream DIR      checkout at the specification's JetStream revision
  --engine-root DIR    installed jsvu engine payload directory

Options:
  --output FILE        probe report (default: jetstream3-spidermonkey-probe.json)
  --timeout-ms N       timeout for each compatibility probe (default: 180000)
  --help               show this help
`;

function validateProbeSpec(spec) {
  validateCommonSpec(spec);
  if (spec.engine.id !== "spidermonkey") {
    throw new Error("engine.id must be spidermonkey");
  }
  if (spec.engine.jsvu_engine !== "spidermonkey") {
    throw new Error("engine.jsvu_engine must be spidermonkey");
  }
  return spec;
}

function buildCommands({ cli, spec }) {
  return {
    discovery: [
      cli,
      "--no-prefetch",
      "--dump-test-list",
      `--test=${spec.workload}`,
    ],
    execution: [
      cli,
      `--test=${spec.workload}`,
      "--iteration-count=2",
      "--worst-case-count=1",
      "--no-prefetch",
      "--dump-json-results",
    ],
  };
}

function resolveInvocation({ engineRoot, executable }) {
  return {
    executable,
    prefix: [],
    environment: { LD_LIBRARY_PATH: engineRoot },
  };
}

function main(argv, dependencies = {}) {
  return runReferenceProbe(
    argv,
    {
      buildCommands,
      defaultOutput: "jetstream3-spidermonkey-probe.json",
      resolveInvocation,
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
    process.stderr.write(
      `JetStream 3 SpiderMonkey probe error: ${error.message}\n`,
    );
    process.exitCode = 1;
  }
}

module.exports = {
  main,
  payloadFingerprint,
  validateProbeSpec,
};
