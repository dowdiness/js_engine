#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { execFileSync } = require("node:child_process");
const test = require("node:test");

const {
  assessAdmission,
  main,
  parseArgs,
} = require("./jetstream3_admission.js");

const PINNED_COMMIT = "7769b693502fa80f28a97bbfacd3296e0513acc5";

test("parseArgs accepts an explicit admission workload", () => {
  const options = parseArgs([
    "--jetstream",
    ".",
    "--jetstream-commit",
    PINNED_COMMIT,
    "--engine",
    "./js_engine",
    "--workload",
    "navier-stokes",
  ]);

  assert.equal(options.workload, "navier-stokes");
});

function probe(stdout, { status = 0, stderr = "" } = {}) {
  return {
    command: ["fake-engine"],
    duration_ms: 1,
    error: null,
    signal: null,
    status,
    stderr,
    stdout,
  };
}

function successfulProbes() {
  return {
    discovery: probe("raytrace\n"),
    execution: probe(
      `${JSON.stringify({
        "JetStream3.0": {
          metrics: { Score: ["Geometric"] },
          tests: {
            raytrace: {
              metrics: {
                Score: { current: [123.5] },
                Time: ["Geometric"],
              },
              tests: {
                First: { metrics: { Time: { current: [8.1] } } },
                Worst: { metrics: { Time: { current: [9.2] } } },
                Average: { metrics: { Time: { current: [7.3] } } },
              },
            },
          },
        },
      })}\n`,
    ),
  };
}

test("admission requires discovery, execution, validation, and structured results", () => {
  const assessment = assessAdmission(successfulProbes(), "raytrace");

  assert.equal(assessment.result, "admitted");
  assert.deepEqual(
    assessment.stages.map((stage) => [stage.name, stage.status]),
    [
      ["test_discovery", "pass"],
      ["workload_execution", "pass"],
      ["workload_result_validation", "pass"],
      ["structured_result", "pass"],
    ],
  );
  assert.deepEqual(assessment.evidence_errors, []);
});

test("exit zero without a structured result is not admitted", () => {
  const probes = successfulProbes();
  probes.execution = probe(
    "Error in runCode:  InternalError: bytecode env slot binding missing for 'HashMap'\n",
  );

  const assessment = assessAdmission(probes, "raytrace");

  assert.equal(assessment.result, "not_admitted");
  assert.equal(
    assessment.stages.find((stage) => stage.name === "workload_execution")
      .status,
    "pass",
  );
  assert.equal(
    assessment.stages.find((stage) => stage.name === "structured_result")
      .status,
    "fail",
  );
});

test("diagnostic text cannot override a valid structured result", () => {
  const probes = successfulProbes();
  probes.execution.stdout = `TypeError: benchmark fixture text\n${probes.execution.stdout}`;

  const assessment = assessAdmission(probes, "raytrace");

  assert.equal(assessment.result, "admitted");
  assert.deepEqual(assessment.evidence_errors, []);
});

test("nonzero exit cannot be overridden by a valid structured result", () => {
  const probes = successfulProbes();
  probes.execution.status = 1;

  const assessment = assessAdmission(probes, "raytrace");

  assert.equal(assessment.result, "not_admitted");
  assert.equal(
    assessment.stages.find((stage) => stage.name === "workload_execution")
      .status,
    "fail",
  );
  assert.equal(
    assessment.stages.find((stage) => stage.name === "structured_result")
      .status,
    "pass",
  );
  assert.equal(
    assessment.stages.find(
      (stage) => stage.name === "workload_result_validation",
    ).status,
    "pass",
  );
});

test("a non-positive workload score is not admitted", () => {
  const probes = successfulProbes();
  const result = JSON.parse(probes.execution.stdout);
  result["JetStream3.0"].tests.raytrace.metrics.Score.current = [0];
  probes.execution.stdout = `${JSON.stringify(result)}\n`;

  const assessment = assessAdmission(probes, "raytrace");

  assert.equal(assessment.result, "not_admitted");
  assert.equal(
    assessment.stages.find(
      (stage) => stage.name === "workload_result_validation",
    ).status,
    "fail",
  );
});

test("a result containing another workload is not admitted", () => {
  const probes = successfulProbes();
  const result = JSON.parse(probes.execution.stdout);
  result["JetStream3.0"].tests.another = result["JetStream3.0"].tests.raytrace;
  probes.execution.stdout = `${JSON.stringify(result)}\n`;

  const assessment = assessAdmission(probes, "raytrace");

  assert.equal(assessment.result, "not_admitted");
  assert.equal(
    assessment.stages.find(
      (stage) => stage.name === "workload_result_validation",
    ).status,
    "fail",
  );
});

test("main writes a complete report without turning incompatibility into infrastructure failure", () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "jetstream3-admission-"));
  try {
    const suiteRoot = path.join(tempRoot, "JetStream");
    fs.mkdirSync(suiteRoot);
    fs.writeFileSync(path.join(suiteRoot, "cli.js"), "// fixture\n");
    const engine = path.join(tempRoot, "js_engine");
    fs.writeFileSync(engine, "fixture\n");
    const output = path.join(tempRoot, "admission.json");
    const probes = successfulProbes();
    probes.execution = probe("JetStream3 failed: InternalError: fixture\n");
    const responses = [probes.discovery, probes.execution];

    const result = main(
      [
        "--jetstream",
        suiteRoot,
        "--jetstream-commit",
        PINNED_COMMIT,
        "--engine",
        engine,
        "--engine-commit",
        "engine-fixture",
        "--engine-tree-state",
        "dirty",
        "--output",
        output,
      ],
      {
        now: () => 0,
        readMoonBitVersion: () => "moon fixture",
        readRevision: () => PINNED_COMMIT,
        readTreeState: () => "clean",
        spawn: (_engine, args) => {
          if (args.includes("--help")) throw new Error("unexpected help probe");
          return responses.shift();
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "not_admitted");
    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.schema_version, 1);
    assert.equal(report.jetstream.commit, PINNED_COMMIT);
    assert.equal(report.engine.commit, "engine-fixture");
    assert.equal(report.engine.tree_state, "dirty");
    assert.equal(report.engine.target, "native");
    assert.equal(report.engine.profile, "release");
    assert.equal(report.environment.moonbit_version, "moon fixture");
    assert.equal(typeof report.environment.architecture, "string");
    assert.equal(report.scope.workload, "raytrace");
    assert.equal(report.assessment.result, "not_admitted");
    assert.equal(report.probes.length, 2);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("main rejects a locally modified JetStream checkout", () => {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "jetstream3-dirty-"));
  try {
    const suiteRoot = path.join(tempRoot, "JetStream");
    fs.mkdirSync(suiteRoot);
    fs.writeFileSync(path.join(suiteRoot, "cli.js"), "// fixture\n");
    execFileSync("git", ["-C", suiteRoot, "init", "--quiet"]);
    execFileSync("git", ["-C", suiteRoot, "add", "cli.js"]);
    execFileSync("git", [
      "-C",
      suiteRoot,
      "-c",
      "user.name=fixture",
      "-c",
      "user.email=fixture@example.invalid",
      "commit",
      "--quiet",
      "-m",
      "fixture",
    ]);
    const revision = execFileSync(
      "git",
      ["-C", suiteRoot, "rev-parse", "HEAD"],
      { encoding: "utf8" },
    ).trim();
    fs.appendFileSync(path.join(suiteRoot, "cli.js"), "// modified\n");
    const engine = path.join(tempRoot, "js_engine");
    fs.writeFileSync(engine, "fixture\n");

    assert.throws(
      () =>
        main(
          [
            "--jetstream",
            suiteRoot,
            "--jetstream-commit",
            revision,
            "--engine",
            engine,
          ],
          {
            readMoonBitVersion: () => "moon fixture",
            spawn: () => probe(""),
            stdout: { write() {} },
          },
        ),
      /local modifications/,
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
