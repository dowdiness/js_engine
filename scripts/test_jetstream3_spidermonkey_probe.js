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
} = require("./jetstream3_spidermonkey_probe.js");

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
      id: "spidermonkey",
      jsvu_engine: "spidermonkey",
      version: "155.0b5",
      executable: "spidermonkey-155.0b5",
      payload_sha256: payloadSha256,
    },
  };
}

function successfulJetStreamResult() {
  return `${JSON.stringify({
    "JetStream3.0": {
      tests: {
        "navier-stokes": {
          metrics: { Score: { current: [649.2] } },
        },
      },
    },
  })}\n`;
}

test("a SpiderMonkey probe fixes one reproducible candidate", () => {
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
    /jsvu_engine must be spidermonkey/,
  );
});

test("the source-controlled SpiderMonkey generation is fixed", () => {
  const spec = validateProbeSpec(
    JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "jetstream3_spidermonkey_probe.json"),
        "utf8",
      ),
    ),
  );

  assert.equal(spec.generation, 1);
  assert.equal(spec.engine.version, "155.0b5");
  assert.equal(spec.workload, "navier-stokes");
});

test("SpiderMonkey uses its stock shell and payload libraries", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-spidermonkey-compatible-"),
  );
  try {
    const engineRoot = path.join(tempRoot, "spidermonkey-155.0b5");
    fs.mkdirSync(engineRoot);
    fs.writeFileSync(
      path.join(engineRoot, "spidermonkey-155.0b5"),
      "installed payload\n",
    );
    fs.writeFileSync(path.join(engineRoot, "libnspr4.so"), "library payload\n");
    fs.writeFileSync(path.join(tempRoot, "cli.js"), "// fixture\n");
    const specPath = path.join(tempRoot, "probe.json");
    fs.writeFileSync(
      specPath,
      `${JSON.stringify(probeSpec(payloadFingerprint(engineRoot)))}\n`,
    );
    const output = path.join(tempRoot, "report.json");
    const invocations = [];
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
        spawn: (executable, args, options) => {
          invocations.push({ executable, args, options });
          return responses.shift();
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "compatible");
    assert.equal(
      invocations[0].executable,
      path.join(engineRoot, "spidermonkey-155.0b5"),
    );
    assert.deepEqual(invocations[0].args, [
      path.join(tempRoot, "cli.js"),
      "--no-prefetch",
      "--dump-test-list",
      "--test=navier-stokes",
    ]);
    assert.equal(invocations[0].options.env.LD_LIBRARY_PATH, engineRoot);
    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.engine.compatibility, "compatible");
    assert.deepEqual(report.probes[0].environment, {
      LD_LIBRARY_PATH: engineRoot,
    });
    assert.equal(report.scope.timings_are_diagnostic_only, true);
    assert.equal("cohort" in report, false);

    const measurementOutput = path.join(tempRoot, "measurement-report.json");
    responses.push(
      { status: 0, signal: null, stderr: "", stdout: "navier-stokes\n" },
      {
        status: 0,
        signal: null,
        stderr: "",
        stdout: successfulJetStreamResult(),
      },
    );
    assert.equal(
      main(
        [
          "--spec",
          specPath,
          "--jetstream",
          tempRoot,
          "--engine-root",
          engineRoot,
          "--measurement-profile",
          "upstream-default",
          "--output",
          measurementOutput,
        ],
        {
          now: () => 0,
          readRevision: () => JETSTREAM_COMMIT,
          readTreeState: () => "clean",
          spawn: (executable, args, options) => {
            invocations.push({ executable, args, options });
            return responses.shift();
          },
          stdout: { write() {} },
        },
      ),
      "compatible",
    );
    assert.equal(invocations[3].args.includes("--iteration-count=2"), false);
    assert.equal(invocations[3].args.includes("--worst-case-count=1"), false);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
