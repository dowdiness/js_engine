#!/usr/bin/env node

"use strict";

const path = require("node:path");

const {
  payloadFingerprint,
  runReferenceProbe,
  validateCommonSpec,
} = require("./jetstream3_reference_probe_core.js");

const usage = `Usage: node scripts/jetstream3_javascriptcore_probe.js [options]

Required:
  --spec FILE          source-controlled JavaScriptCore probe specification
  --jetstream DIR      checkout at the specification's JetStream revision
  --engine-root DIR    installed jsvu engine payload directory

Options:
  --output FILE        probe report (default: jetstream3-javascriptcore-probe.json)
  --timeout-ms N       timeout for each compatibility probe (default: 180000)
  --help               show this help
`;

function validateProbeSpec(spec) {
  validateCommonSpec(spec);
  if (spec.engine.id !== "javascriptcore") {
    throw new Error("engine.id must be javascriptcore");
  }
  if (spec.engine.jsvu_engine !== "javascriptcore") {
    throw new Error("engine.jsvu_engine must be javascriptcore");
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

function resolveInvocation({ engineRoot, executable }) {
  const loader = path.join(engineRoot, "lib", "ld-linux-x86-64.so.2");
  return {
    executable: loader,
    prefix: ["--library-path", path.join(engineRoot, "lib"), executable],
  };
}

function main(argv, dependencies = {}) {
  return runReferenceProbe(
    argv,
    {
      buildCommands,
      defaultOutput: "jetstream3-javascriptcore-probe.json",
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
      `JetStream 3 JavaScriptCore probe error: ${error.message}\n`,
    );
    process.exitCode = 1;
  }
}

module.exports = {
  main,
  payloadFingerprint,
  validateProbeSpec,
};
