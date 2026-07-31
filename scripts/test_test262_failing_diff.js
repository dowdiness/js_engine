#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const DIFF = path.join(__dirname, "test262_failing_diff.js");

function artifact(status, { mode = "strict", pathname = "test262/test/built-ins/encodeURI/case.js" } = {}) {
  return {
    engine: "moonbit-js-engine",
    date: "1970-01-01T00:00:00Z",
    summary: {
      total: 1,
      passed: status === "pass" ? 1 : 0,
      failed: status === "fail" ? 1 : 0,
      skipped: status === "skip" ? 1 : 0,
      timeout: status === "timeout" ? 1 : 0,
      error: status === "error" ? 1 : 0,
      pass_rate: status === "pass" ? 100 : 0,
    },
    categories: {},
    results: [
      {
        path: pathname,
        status,
        reason: "fixture",
        duration_ms: 1,
        mode,
      },
    ],
  };
}

function runDiff(baseline, candidate, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "test262-failing-diff-"));
  try {
    const baselinePath = path.join(root, "baseline.json");
    const candidatePath = path.join(root, "candidate.json");
    fs.writeFileSync(baselinePath, JSON.stringify(artifact(baseline, options)));
    fs.writeFileSync(candidatePath, JSON.stringify(artifact(candidate, options)));
    return spawnSync(process.execPath, [DIFF, baselinePath, candidatePath], {
      encoding: "utf8",
    });
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}

test("a previously passing timeout fails the required diff", () => {
  const result = runDiff("pass", "timeout");
  assert.equal(result.status, 1, result.stdout + result.stderr);
});

test("pass to fail, timeout, and error fail in either mode", () => {
  for (const mode of ["strict", "non-strict"]) {
    for (const status of ["fail", "timeout", "error"]) {
      const result = runDiff("pass", status, { mode });
      assert.equal(result.status, 1, `${mode} ${status}: ${result.stdout}${result.stderr}`);
    }
  }
});

test("lost coverage fails while recovery passes", () => {
  assert.equal(runDiff("pass", "skip").status, 1);
  assert.equal(runDiff("fail", "skip").status, 1);
  assert.equal(runDiff("fail", "pass").status, 0);
  assert.equal(runDiff("timeout", "pass", { mode: "non-strict" }).status, 0);
  assert.equal(runDiff("error", "pass").status, 0);
});

test("malformed and incomplete artifacts fail closed", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "test262-failing-diff-invalid-"));
  try {
    const baselinePath = path.join(root, "baseline.json");
    const candidatePath = path.join(root, "candidate.json");
    const baseline = artifact("pass");
    const candidate = artifact("pass");

    candidate.summary.passed = 0;
    fs.writeFileSync(baselinePath, JSON.stringify(baseline));
    fs.writeFileSync(candidatePath, JSON.stringify(candidate));
    assert.equal(spawnSync(process.execPath, [DIFF, baselinePath, candidatePath]).status, 3);

    candidate.summary.passed = 1;
    candidate.results.push({
      ...candidate.results[0],
      path: "test262/test/built-ins/encodeURI/extra.js",
    });
    candidate.summary.total = 2;
    candidate.summary.passed = 2;
    fs.writeFileSync(candidatePath, JSON.stringify(candidate));
    assert.equal(spawnSync(process.execPath, [DIFF, baselinePath, candidatePath]).status, 3);

    const duplicate = artifact("pass");
    duplicate.summary.total = 2;
    duplicate.results.push({ ...duplicate.results[0] });
    duplicate.summary.passed = 2;
    fs.writeFileSync(candidatePath, JSON.stringify(duplicate));
    assert.equal(spawnSync(process.execPath, [DIFF, baselinePath, candidatePath]).status, 3);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("the required workflow invokes the per-test regression policy", () => {
  const workflow = fs.readFileSync(
    path.join(__dirname, "..", ".github", "workflows", "test262.yml"),
    "utf8",
  );
  assert.match(workflow, /node scripts\/test262_failing_diff\.js/);
});
