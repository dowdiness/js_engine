#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const { execFileSync, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const {
  main,
  parseArgs,
  payloadFingerprint,
  validateProbeSpec,
} = require("./jetstream3_quickjs_probe.js");

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
      id: "quickjs-ng",
      jsvu_engine: "quickjs",
      version: "0.16.1",
      executable: "qjs",
      shell_adapter: "jetstream3_quickjs_shell.js",
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

test("a probe specification contains one fixed QuickJS-ng candidate", () => {
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
        engine: { ...spec.engine, payload_sha256: undefined },
      }),
    /payload_sha256/,
  );
  assert.throws(
    () => validateProbeSpec({ ...spec, workload: "raytrace" }),
    /navier-stokes/,
  );
  assert.throws(
    () =>
      validateProbeSpec({
        ...spec,
        engine: { ...spec.engine, jsvu_engine: "v8" },
      }),
    /jsvu_engine must be quickjs/,
  );
});

test("the probe CLI does not expose a generic engine selector", () => {
  assert.throws(() => parseArgs(["--engine-id", "v8"]), /unknown option/);
});

test("the source-controlled generation is a valid QuickJS-ng probe", () => {
  const spec = validateProbeSpec(
    JSON.parse(
      fs.readFileSync(
        path.join(__dirname, "jetstream3_quickjs_probe.json"),
        "utf8",
      ),
    ),
  );

  assert.equal(spec.generation, 1);
  assert.equal(spec.jsvu_version, "3.0.5");
  assert.equal(spec.engine.id, "quickjs-ng");
  assert.equal(spec.engine.version, "0.16.1");
  assert.equal(spec.engine.shell_adapter, "jetstream3_quickjs_shell.js");
});

test("the QuickJS-ng adapter exposes basic globals and rejects fake isolation", () => {
  const loaded = [];
  const context = {
    Date,
    execArgv: [
      "qjs",
      "--std",
      "-I",
      "adapter.js",
      "cli.js",
      "--",
      "--test=navier-stokes",
    ],
    os: { now: () => 12.5 },
    print() {},
    std: {
      err: { puts() {} },
      loadFile(file) {
        return `contents:${file}`;
      },
      loadScript(file) {
        loaded.push(file);
      },
    },
  };
  context.globalThis = context;
  vm.runInNewContext(
    fs.readFileSync(
      path.join(__dirname, "jetstream3_quickjs_shell.js"),
      "utf8",
    ),
    context,
  );

  assert.deepEqual(Array.from(context.arguments), ["--test=navier-stokes"]);
  assert.equal(context.readFile("fixture.js"), "contents:fixture.js");
  context.load("fixture.js");
  assert.deepEqual(loaded, ["fixture.js"]);
  assert.throws(
    () => context.runString(""),
    /does not expose isolated globals required by JetStream/,
  );
  assert.equal(context.performance.now(), 12.5);
});

test("preparation stops before execution when the installed payload changed", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-mismatch-"),
  );
  try {
    const engineRoot = path.join(tempRoot, "quickjs-0.16.1");
    fs.mkdirSync(engineRoot);
    fs.writeFileSync(path.join(engineRoot, "qjs"), "installed payload\n");
    const specPath = path.join(tempRoot, "probe.json");
    fs.writeFileSync(
      specPath,
      `${JSON.stringify(probeSpec("0".repeat(64)))}\n`,
    );

    assert.throws(
      () =>
        main(
          [
            "--spec",
            specPath,
            "--jetstream",
            tempRoot,
            "--engine-root",
            engineRoot,
            "--output",
            path.join(tempRoot, "report.json"),
          ],
          {
            readRevision: () => JETSTREAM_COMMIT,
            readTreeState: () => "clean",
            spawn: () => {
              throw new Error("workload must not run");
            },
          },
        ),
      /payload fingerprint mismatch/,
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("preparation records QuickJS-ng outcomes without performance claims", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-compatible-"),
  );
  try {
    const engineRoot = path.join(tempRoot, "quickjs-0.16.1");
    fs.mkdirSync(engineRoot);
    fs.writeFileSync(path.join(engineRoot, "qjs"), "installed payload\n");
    const specPath = path.join(tempRoot, "probe.json");
    const adapterPath = path.join(tempRoot, "jetstream3_quickjs_shell.js");
    fs.copyFileSync(
      path.join(__dirname, "jetstream3_quickjs_shell.js"),
      adapterPath,
    );
    fs.writeFileSync(
      specPath,
      `${JSON.stringify(probeSpec(payloadFingerprint(engineRoot)))}\n`,
    );
    fs.writeFileSync(path.join(tempRoot, "cli.js"), "// fixture\n");
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
        spawn: (_executable, args) => {
          commands.push(args);
          return responses.shift();
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "compatible");
    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.schema_version, 1);
    assert.equal(report.candidate.generation, 1);
    assert.equal(report.engine.id, "quickjs-ng");
    assert.equal(report.engine.compatibility, "compatible");
    assert.equal(report.scope.workload, "navier-stokes");
    assert.equal(report.scope.timings_are_diagnostic_only, true);
    assert.equal("score" in report, false);
    assert.equal("cohort" in report, false);
    assert.deepEqual(commands[0].slice(0, 4), [
      "--std",
      "-I",
      adapterPath,
      path.join(tempRoot, "cli.js"),
    ]);
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
          output,
        ],
        {
          now: () => 0,
          readRevision: () => JETSTREAM_COMMIT,
          readTreeState: () => "clean",
          spawn: (_executable, args) => {
            commands.push(args);
            return responses.shift();
          },
          stdout: { write() {} },
        },
      ),
      "compatible",
    );
    assert.equal(commands[3].includes("--iteration-count=2"), false);
    assert.equal(commands[3].includes("--worst-case-count=1"), false);
    const runWith = (response) => {
      const outcome = main(
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
          spawn: () => response,
          stdout: { write() {} },
        },
      );
      return {
        outcome,
        report: JSON.parse(fs.readFileSync(output, "utf8")),
      };
    };

    const launchFailure = runWith({
      error: new Error("spawn ETIMEDOUT"),
      signal: null,
      status: null,
      stderr: "",
      stdout: "",
    });
    assert.equal(launchFailure.outcome, "probe_failed");
    assert.equal(launchFailure.report.engine.compatibility, "probe_failed");
    assert.match(launchFailure.report.probes[0].error, /ETIMEDOUT/);

    const signalFailure = runWith({
      error: null,
      signal: "SIGKILL",
      status: null,
      stderr: "",
      stdout: "",
    });
    assert.equal(signalFailure.outcome, "probe_failed");
    assert.equal(signalFailure.report.engine.compatibility, "probe_failed");

    const engineIncompatibility = runWith({
      error: null,
      signal: null,
      status: 1,
      stderr: "isolated globals are unavailable",
      stdout: "",
    });
    assert.equal(engineIncompatibility.outcome, "incompatible");
    assert.equal(
      engineIncompatibility.report.engine.compatibility,
      "incompatible",
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("the probe CLI exits nonzero after preserving launch-failure evidence", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-cli-failure-"),
  );
  try {
    const jetstream = path.join(tempRoot, "JetStream");
    fs.mkdirSync(jetstream);
    execFileSync("git", ["-C", jetstream, "init", "--quiet"]);
    fs.writeFileSync(path.join(jetstream, "cli.js"), "// fixture\n");
    execFileSync("git", ["-C", jetstream, "add", "cli.js"]);
    execFileSync("git", [
      "-C",
      jetstream,
      "-c",
      "user.name=Fixture",
      "-c",
      "user.email=fixture@example.com",
      "commit",
      "--quiet",
      "-m",
      "fixture",
    ]);
    const revision = execFileSync(
      "git",
      ["-C", jetstream, "rev-parse", "HEAD"],
      { encoding: "utf8" },
    ).trim();

    const engineRoot = path.join(tempRoot, "quickjs-0.16.1");
    fs.mkdirSync(engineRoot);
    fs.writeFileSync(path.join(engineRoot, "qjs"), "not executable\n", {
      mode: 0o644,
    });
    const specPath = path.join(tempRoot, "probe.json");
    fs.copyFileSync(
      path.join(__dirname, "jetstream3_quickjs_shell.js"),
      path.join(tempRoot, "jetstream3_quickjs_shell.js"),
    );
    fs.writeFileSync(
      specPath,
      `${JSON.stringify({
        ...probeSpec(payloadFingerprint(engineRoot)),
        jetstream_commit: revision,
      })}\n`,
    );
    const output = path.join(tempRoot, "report.json");

    const result = spawnSync(
      process.execPath,
      [
        path.join(__dirname, "jetstream3_quickjs_probe.js"),
        "--spec",
        specPath,
        "--jetstream",
        jetstream,
        "--engine-root",
        engineRoot,
        "--output",
        output,
      ],
      { encoding: "utf8" },
    );

    assert.equal(result.status, 1);
    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.engine.compatibility, "probe_failed");
    assert.match(report.probes[0].error, /EACCES/);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
