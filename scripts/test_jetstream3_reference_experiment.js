#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const { main, parseArgs } = require("./jetstream3_reference_experiment.js");

test("the upstream-default experiment allows one full js_engine invocation", () => {
  const options = parseArgs(
    [
      "--jetstream",
      "JetStream",
      "--engine",
      "js_engine",
      "--jsvu-root",
      "jsvu",
      "--output-dir",
      "evidence",
    ],
    {},
  );

  assert.equal(options.timeoutMs, 600_000);
});

test("the feasibility experiment runs one mirrored complete cohort", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-experiment-"),
  );
  try {
    const outputDir = path.join(tempRoot, "evidence");
    const calls = [];
    const result = main(
      [
        "--jetstream",
        path.join(tempRoot, "JetStream"),
        "--engine",
        path.join(tempRoot, "js_engine"),
        "--jsvu-root",
        path.join(tempRoot, "jsvu"),
        "--output-dir",
        outputDir,
      ],
      {
        environment: {
          GITHUB_RUN_ATTEMPT: "2",
          GITHUB_RUN_ID: "1234",
          GITHUB_SHA: "engine-commit",
          GITHUB_WORKFLOW_SHA: "workflow-commit",
          RUNNER_ARCH: "X64",
          RUNNER_OS: "Linux",
        },
        now: (() => {
          let value = 0;
          return () => value++;
        })(),
        runMember: (member, output) => {
          calls.push(member.id);
          fs.mkdirSync(path.dirname(output), { recursive: true });
          fs.writeFileSync(
            output,
            `${JSON.stringify({ assessment: { result: "admitted" } })}\n`,
          );
          return member.id === "js_engine" ? "admitted" : "compatible";
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "complete");
    assert.deepEqual(calls, [
      "js_engine",
      "v8",
      "javascriptcore",
      "spidermonkey",
      "spidermonkey",
      "javascriptcore",
      "v8",
      "js_engine",
    ]);
    const index = JSON.parse(
      fs.readFileSync(path.join(outputDir, "run-index.json"), "utf8"),
    );
    assert.equal(index.experiment, "jetstream3-cross-engine-feasibility");
    assert.equal(index.valid, true);
    assert.equal(index.timings_are_diagnostic_only, true);
    assert.equal(index.observations.length, 8);
    assert.deepEqual(index.inputs, {
      generation: 1,
      platform: "linux64",
      jsvu_version: "3.0.5",
      jetstream_commit: "7769b693502fa80f28a97bbfacd3296e0513acc5",
      workload: "navier-stokes",
      measurement_profile: "upstream-default",
      iteration_count_override: null,
      worst_case_count_override: null,
      ordered_members: [
        "js_engine",
        "v8",
        "javascriptcore",
        "spidermonkey",
      ],
      passes: 2,
      schedule: "forward_reverse",
    });
    assert.deepEqual(
      index.observations.map(({ pass, ordinal, member }) => [
        pass,
        ordinal,
        member,
      ]),
      [
        [1, 1, "js_engine"],
        [1, 2, "v8"],
        [1, 3, "javascriptcore"],
        [1, 4, "spidermonkey"],
        [2, 1, "spidermonkey"],
        [2, 2, "javascriptcore"],
        [2, 3, "v8"],
        [2, 4, "js_engine"],
      ],
    );
    assert.equal(index.source.repository_commit, "engine-commit");
    assert.equal(index.source.workflow_commit, "workflow-commit");
    assert.equal(index.workflow.run_id, "1234");
    assert.equal(index.workflow.run_attempt, "2");
    assert.equal(index.runner.os, "Linux");
    assert.equal(index.runner.architecture, "X64");
    assert.equal(index.observations[0].started_at, "1970-01-01T00:00:00.000Z");
    assert.equal(index.observations[0].ended_at, "1970-01-01T00:00:00.001Z");
    assert.equal(index.observations[0].duration_ms, 1);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("the reference experiment selects upstream JetStream measurement policy", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-profile-"),
  );
  try {
    const calls = [];
    const runner = (member, outcome) => (argv) => {
      calls.push({ member, argv });
      const output = argv[argv.indexOf("--output") + 1];
      fs.mkdirSync(path.dirname(output), { recursive: true });
      fs.writeFileSync(output, "{}\n");
      return outcome;
    };
    const outputDir = path.join(tempRoot, "evidence");

    const result = main(
      [
        "--jetstream",
        path.join(tempRoot, "JetStream"),
        "--engine",
        path.join(tempRoot, "js_engine"),
        "--jsvu-root",
        path.join(tempRoot, "jsvu"),
        "--output-dir",
        outputDir,
      ],
      {
        environment: {},
        now: () => 0,
        runners: {
          javascriptcore: runner("javascriptcore", "compatible"),
          jsEngine: runner("js_engine", "admitted"),
          spidermonkey: runner("spidermonkey", "compatible"),
          v8: runner("v8", "compatible"),
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "complete");
    assert.equal(calls.length, 8);
    for (const call of calls) {
      assert.deepEqual(
        call.argv.slice(
          call.argv.indexOf("--measurement-profile"),
          call.argv.indexOf("--measurement-profile") + 2,
        ),
        ["--measurement-profile", "upstream-default"],
      );
    }
    const index = JSON.parse(
      fs.readFileSync(path.join(outputDir, "run-index.json"), "utf8"),
    );
    assert.equal(index.inputs.measurement_profile, "upstream-default");
    assert.equal(index.inputs.iteration_count_override, null);
    assert.equal(index.inputs.worst_case_count_override, null);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("one failed invocation invalidates the experiment without hiding later evidence", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-failure-"),
  );
  try {
    const outputDir = path.join(tempRoot, "evidence");
    let call = 0;
    const result = main(
      [
        "--jetstream",
        path.join(tempRoot, "JetStream"),
        "--engine",
        path.join(tempRoot, "js_engine"),
        "--jsvu-root",
        path.join(tempRoot, "jsvu"),
        "--output-dir",
        outputDir,
      ],
      {
        environment: {},
        now: () => 0,
        runMember: (member, output) => {
          call += 1;
          if (call === 2) throw new Error("fixture launch failed");
          fs.mkdirSync(path.dirname(output), { recursive: true });
          fs.writeFileSync(output, "{}\n");
          return member.id === "js_engine" ? "admitted" : "compatible";
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "invalid");
    assert.equal(call, 8);
    const index = JSON.parse(
      fs.readFileSync(path.join(outputDir, "run-index.json"), "utf8"),
    );
    assert.equal(index.valid, false);
    assert.equal(index.observations.length, 8);
    assert.deepEqual(index.observations[1].failure, {
      message: "fixture launch failed",
    });
    assert.equal(index.observations[1].outcome, "experiment_failed");
    assert.equal(index.observations[7].member, "js_engine");
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("mismatched candidate inputs are rejected before any engine runs", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-mismatch-"),
  );
  try {
    const specifications = [
      ["v8", "jetstream3_v8_probe.json"],
      ["javascriptcore", "jetstream3_javascriptcore_probe.json"],
      ["spidermonkey", "jetstream3_spidermonkey_probe.json"],
    ].map(([member, filename]) => ({
      member,
      filename,
      sha256: "a".repeat(64),
      spec: JSON.parse(fs.readFileSync(path.join(__dirname, filename), "utf8")),
    }));
    specifications[1].spec.workload = "raytrace";
    let calls = 0;

    assert.throws(
      () =>
        main(
          [
            "--jetstream",
            path.join(tempRoot, "JetStream"),
            "--engine",
            path.join(tempRoot, "js_engine"),
            "--jsvu-root",
            path.join(tempRoot, "jsvu"),
            "--output-dir",
            path.join(tempRoot, "evidence"),
          ],
          {
            environment: {},
            readSpecifications: () => specifications,
            runMember: () => {
              calls += 1;
              return "compatible";
            },
            stdout: { write() {} },
          },
        ),
      /same workload/,
    );
    assert.equal(calls, 0);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("a successful outcome without its raw report is not complete evidence", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-missing-report-"),
  );
  try {
    let call = 0;
    const outputDir = path.join(tempRoot, "evidence");
    const result = main(
      [
        "--jetstream",
        path.join(tempRoot, "JetStream"),
        "--engine",
        path.join(tempRoot, "js_engine"),
        "--jsvu-root",
        path.join(tempRoot, "jsvu"),
        "--output-dir",
        outputDir,
      ],
      {
        environment: {},
        now: () => 0,
        runMember: (member, output) => {
          call += 1;
          if (call !== 3) {
            fs.mkdirSync(path.dirname(output), { recursive: true });
            fs.writeFileSync(output, "{}\n");
          }
          return member.id === "js_engine" ? "admitted" : "compatible";
        },
        stdout: { write() {} },
      },
    );

    assert.equal(result, "invalid");
    const index = JSON.parse(
      fs.readFileSync(path.join(outputDir, "run-index.json"), "utf8"),
    );
    assert.equal(index.observations[2].outcome, "compatible");
    assert.equal(index.observations[2].raw_report, null);
    assert.equal(index.valid, false);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("an existing evidence directory cannot supply stale reports", () => {
  const tempRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "jetstream3-reference-stale-"),
  );
  try {
    const outputDir = path.join(tempRoot, "evidence");
    fs.mkdirSync(outputDir);
    fs.writeFileSync(path.join(outputDir, "pass-1-v8.json"), "{}\n");
    let calls = 0;

    assert.throws(
      () =>
        main(
          [
            "--jetstream",
            path.join(tempRoot, "JetStream"),
            "--engine",
            path.join(tempRoot, "js_engine"),
            "--jsvu-root",
            path.join(tempRoot, "jsvu"),
            "--output-dir",
            outputDir,
          ],
          {
            environment: {},
            runMember: () => {
              calls += 1;
              return "compatible";
            },
            stdout: { write() {} },
          },
        ),
      /output directory must be empty/,
    );
    assert.equal(calls, 0);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});
