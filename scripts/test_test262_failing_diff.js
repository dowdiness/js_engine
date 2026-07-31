#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const DIFF = path.join(__dirname, "test262_failing_diff.js");
const GATE = path.join(__dirname, "test262_regression_check.sh");

const EXPECTED_TEST262_SHARD_INVOCATION = [
  "./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \\",
  "--test262 ./test262 \\",
  "--mode ${{ matrix.mode }} \\",
  "--shard ${{ matrix.shard }}/${{ env.SHARD_TOTAL }} \\",
  "--threads 4 \\",
  "--timeout 12 \\",
  "--output test262-${{ matrix.mode }}-shard-${{ matrix.shard }}of${{ env.SHARD_TOTAL }}-results.json \\",
  "--summary",
];

function assertWorkflowUsesTimeout12(workflow) {
  const lines = workflow.split("\n").map(line => line.trim());
  const stepStart = lines.findIndex(line => line.startsWith("- name: Run Test262 ("));
  assert.ok(stepStart >= 0, "Test262 shard step is missing");
  const stepEnd = lines.findIndex(
    (line, index) => index > stepStart && line.startsWith("- name:"),
  );
  const invocationStart = lines.findIndex(
    (line, index) =>
      index > stepStart && index < stepEnd && line === EXPECTED_TEST262_SHARD_INVOCATION[0],
  );
  assert.ok(invocationStart >= 0, "authoritative Test262 shard invocation is missing");
  const invocation = lines.slice(
    invocationStart,
    invocationStart + EXPECTED_TEST262_SHARD_INVOCATION.length,
  );
  assert.deepEqual(
    invocation,
    EXPECTED_TEST262_SHARD_INVOCATION,
    "authoritative Test262 shard invocation must remain exact",
  );
}

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

function runGate(baselineStatus, candidateStatus, failure = "") {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "test262-regression-gate-"));
  const baselineRoot = path.join(root, "baseline");
  const binRoot = path.join(root, "bin");
  fs.mkdirSync(baselineRoot);
  fs.mkdirSync(binRoot);
  for (const mode of ["strict", "non-strict"]) {
    fs.writeFileSync(
      path.join(baselineRoot, `test262-${mode}-results.json`),
      JSON.stringify(artifact(baselineStatus, { mode })),
    );
    fs.writeFileSync(
      path.join(root, `test262-${mode}-results.json`),
      JSON.stringify(artifact(candidateStatus, { mode })),
    );
  }
  fs.writeFileSync(
    path.join(binRoot, "gh"),
    `#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "api" ]]; then
  [[ "\${FAKE_GH_FAILURE:-}" != "lookup" ]] || exit 17
  printf '123\\n'
  exit 0
fi
if [[ "\${1:-}" == "run" && "\${2:-}" == "download" ]]; then
  [[ "\${FAKE_GH_FAILURE:-}" != "download" ]] || exit 19
  destination=""
  while [[ "\$#" -gt 0 ]]; do
    if [[ "\$1" == "--dir" ]]; then
      destination="\$2"
      shift 2
    else
      shift
    fi
  done
  cp "\$FAKE_BASELINE_DIR"/test262-strict-results.json "\$destination"/
  cp "\$FAKE_BASELINE_DIR"/test262-non-strict-results.json "\$destination"/
  exit 0
fi
exit 21
`,
    { mode: 0o755 },
  );
  try {
    return spawnSync(GATE, {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${binRoot}${path.delimiter}${process.env.PATH}`,
        GITHUB_REPOSITORY: "dowdiness/js_engine",
        CURRENT_RUN_ID: "999",
        FAKE_BASELINE_DIR: baselineRoot,
        FAKE_GH_FAILURE: failure,
      },
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
  assert.match(workflow, /run: scripts\/test262_regression_check\.sh/);
});

test("the Test262 shard keeps bounded RegExp headroom", () => {
  const workflow = fs.readFileSync(
    path.join(__dirname, "..", ".github", "workflows", "test262.yml"),
    "utf8",
  );
  assertWorkflowUsesTimeout12(workflow);
});

test("the timeout assertion rejects a wrong authoritative command despite a decoy", () => {
  const workflow = fs.readFileSync(
    path.join(__dirname, "..", ".github", "workflows", "test262.yml"),
    "utf8",
  );
  const wrongAuthoritativeTimeout = workflow.replace(
    "            --timeout 12 \\\n",
    "            --timeout 8 \\\n",
  );
  const decoy = [
    "",
    "# unrelated command that must not satisfy the workflow contract",
    "./_build/native/debug/build/cmd/test262_runner/test262_runner.exe \\",
    "  --threads 4 \\",
    "  --timeout 12 \\",
    "",
  ].join("\n");
  assert.throws(
    () => assertWorkflowUsesTimeout12(wrongAuthoritativeTimeout + decoy),
    /authoritative Test262 shard invocation must remain exact/,
  );
});

test("the exact workflow gate fails regressions, passes clean results, and fails closed", () => {
  assert.equal(runGate("pass", "timeout").status, 1);
  assert.equal(runGate("pass", "pass").status, 0);
  assert.notEqual(runGate("pass", "pass", "lookup").status, 0);
  assert.notEqual(runGate("pass", "pass", "download").status, 0);
});

test("test262-required propagates regression-check failure", () => {
  const workflow = fs.readFileSync(
    path.join(__dirname, "..", ".github", "workflows", "test262.yml"),
    "utf8",
  );
  assert.match(workflow, /REGRESSION_RESULT: \$\{\{ needs\.regression-check\.result \}\}/);
  assert.ok(workflow.includes('            "$REGRESSION_RESULT"\n          do'));
  assert.ok(workflow.includes('            if [[ "$result" != "success" ]]'));
});
