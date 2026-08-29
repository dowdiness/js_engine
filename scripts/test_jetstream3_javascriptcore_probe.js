#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  main,
  payloadFingerprint,
  validateProbeSpec,
} = require("./jetstream3_javascriptcore_probe.js");

const JETSTREAM_COMMIT = "7769b693502fa80f28a97bbfacd3296e0513acc5";

function probeSpec(payloadSha256) {
  return {
    schema_version: 1,
    generation: 1,
    platform: "linux64",
    jsvu_version: "3.0.5",
    jetstream_commit: JETSTREAM_COMMIT,
    workload: "navier-stokes",
    engine: {
      id: "javascriptcore",
      jsvu_engine: "javascriptcore",
      version: "320015@main",
      executable: "javascriptcore-320015@main",
      payload_sha256: payloadSha256,
    },
  };
}

function successfulJetStreamResult() {
  return `${JSON.stringify({
    "JetStream3.0": {
      tests: {
        "navier-stokes": {
          metrics: { Score: { current: [123.5] } },
        },
      },
    },
  })}\n`;
}

test("a JavaScriptCore probe fixes one reproducible candidate", () => {
  const spec = probeSpec("a".repeat(64));

  assert.equal(validateProbeSpec(spec), spec);
  assert.throws(
    () => validateProbeSpec({ ...spec, jsvu_version: "latest" }),
    /jsvu_version/,
  );
  assert.throws(
    () =>
      validateProbeSpec({
        ...spec,
        engine: { ...spec.engine, version: "latest" },
      }),
    /engine.version/,
  );
  assert.throws(
    () =>
      validateProbeSpec({
        ...spec,
        engine: { ...spec.engine, jsvu_engine: "v8" },
      }),
    /jsvu_engine must be javascriptcore/,
  );
});

test("the source-controlled JavaScriptCore generation is fixed", () => {
  const spec = validateProbeSpec(
    JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "jetstream3_javascriptcore_probe.json"),
        "utf8",
      ),
    ),
  );

  assert.equal(spec.generation, 1);
  assert.equal(spec.engine.version, "320015@main");
  assert.equal(spec.workload, "navier-stokes");
});

test("JavaScriptCore uses its standard shell without a repository adapter", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-javascriptcore-compatible-"),
  );
  try {
    const engineRoot = path.join(tempRoot, "javascriptcore-320015");
    fs.mkdirSync(engineRoot);
    fs.mkdirSync(path.join(engineRoot, "lib"));
    fs.writeFileSync(
      path.join(engineRoot, "javascriptcore-320015@main"),
      "installed payload\n",
    );
    fs.writeFileSync(
      path.join(engineRoot, "lib", "ld-linux-x86-64.so.2"),
      "loader payload\n",
    );
    fs.writeFileSync(path.join(tempRoot, "cli.js"), "// fixture\n");
    const specPath = path.join(tempRoot, "probe.json");
    fs.writeFileSync(
      specPath,
      `${JSON.stringify(probeSpec(payloadFingerprint(engineRoot)))}\n`,
    );
    const output = path.join(tempRoot, "report.json");
    const commands = [];
    const responses = [
      { status: 0, signal: null, stderr: "", stdout: "navier-stokes\n" },
      {
        status: 0,
        signal: null,
        stderr: "",
        stdout: successfulJetStreamResult(),
      },
    ];

    const result = main(
      [
        "--spec",
        specPath,
        "--jetstream",
        tempRoot,
        "--engine-root",
        engineRoot,
        "--output",
        output,
      ],
      {
        now: () => 0,
        readRevision: () => JETSTREAM_COMMIT,
        readTreeState: () => "clean",
        spawn: (executable, args) => {
          commands.push([executable, ...args]);
          return responses.shift();
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "compatible");
    assert.deepEqual(commands[0], [
      path.join(engineRoot, "lib", "ld-linux-x86-64.so.2"),
      "--library-path",
      path.join(engineRoot, "lib"),
      path.join(engineRoot, "javascriptcore-320015@main"),
      path.join(tempRoot, "cli.js"),
      "--",
      "--no-prefetch",
      "--dump-test-list",
      "--test=navier-stokes",
    ]);
    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.engine.compatibility, "compatible");
    assert.equal(report.scope.timings_are_diagnostic_only, true);
    assert.equal("cohort" in report, false);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
