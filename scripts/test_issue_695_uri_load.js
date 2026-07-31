#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..");
const BENCHMARK = path.join(REPO_ROOT, "scripts", "test262_uri_load_repro.js");
const HARNESS_TIMEOUT_SECONDS = 12;

function writeFile(file, content, mode) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  if (mode !== undefined) fs.chmodSync(file, mode);
}

function main() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "issue-695-contract-"));
  const suite = path.join(root, "test262");
  const tests = [
    "built-ins/encodeURI/S15.1.3.3_A2.3_T1.js",
    "built-ins/encodeURIComponent/S15.1.3.4_A2.3_T1.js",
  ];
  for (const test of tests) {
    writeFile(path.join(suite, "test", test), "/*---\ndescription: fixture\n---*/\n");
  }
  writeFile(path.join(suite, "harness", "sta.js"), "");
  writeFile(path.join(suite, "harness", "assert.js"), "");
  const control = path.join(root, "known-hang.js");
  writeFile(control, "/*---\ndescription: control\n---*/\n");

  const fakeRunner = path.join(root, "fake-runner.js");
  writeFile(
    fakeRunner,
    `#!/usr/bin/env node
const fs = require("node:fs");
const args = process.argv.slice(2);
const value = name => args[args.indexOf(name) + 1];
const mode = value("--mode");
const testsFile = value("--tests-file");
const output = value("--output");
const timeout = Number(value("--timeout"));
const entries = fs.readFileSync(testsFile, "utf8").split(/\\n/).filter(Boolean);
const scenario = process.env.FAKE_SCENARIO || "";
const isControl = entries.some(path => path.includes("known-hang.js"));
const results = entries.map(path => ({
  path,
  mode,
  timeout_seconds: timeout,
  status: path.includes("known-hang.js") ? "timeout" : "pass",
  reason: path.includes("known-hang.js") ? \`Exceeded \${timeout}s timeout\` : "",
  duration_ms: path.includes("known-hang.js") ? timeout * 1000 : 2,
}));
if (isControl && scenario === "control-missing") results.splice(0);
if (isControl && scenario === "control-extra") results.push({ ...results[0] });
if (isControl && scenario === "control-mode") {
  results[0].mode = mode === "strict" ? "non-strict" : "strict";
}
if (!isControl && scenario === "uri-missing") results.splice(-1);
if (!isControl && scenario === "uri-extra") results.push({ ...results[0], path: results[0].path + ".extra" });
if (!isControl && scenario === "uri-fail") {
  results[0].status = "fail";
  results[0].reason = "fake URI failure";
}
const counts = status => results.filter(result => result.status === status).length;
fs.writeFileSync(output, JSON.stringify({
  engine: "fake",
  summary: { total: results.length, passed: counts("pass"), failed: counts("fail"), skipped: counts("skip"), timeout: counts("timeout"), error: counts("error") },
  categories: {},
  results,
}));
process.stdout.write(JSON.stringify({ mode, threads: Number(value("--threads")), timeout }) + "\\n");
`,
    0o755,
  );

  const output = path.join(root, "result.json");
  const benchmarkArgs = [
    BENCHMARK,
    "--runner",
    fakeRunner,
    "--engine",
    "fake",
    "--test262",
    suite,
    "--test262-revision",
    "fake-test262",
    "--control",
    control,
    "--iterations",
    "1",
    "--timeout",
    String(HARNESS_TIMEOUT_SECONDS),
    "--output",
    output,
  ];
  const run = spawnSync(process.execPath, benchmarkArgs, {
    cwd: REPO_ROOT,
    encoding: "utf8",
  });
  assert.equal(run.status, 0, run.stderr || run.stdout);

  const artifact = JSON.parse(fs.readFileSync(output, "utf8"));
  assert.equal(artifact.ticket, 695);
  assert.match(artifact.git_commit, /^[0-9a-f]{40}$/);
  assert.equal(artifact.test262_revision, "fake-test262");
  assert.equal(artifact.test262_revision_source, "argument:--test262-revision");
  assert.equal(artifact.runs.length, 4, "one isolated/load run per mode");
  assert.deepEqual(
    artifact.runs.map(run => [run.condition, run.mode, run.threads]),
    [
      ["isolated", "strict", 1],
      ["load", "strict", 4],
      ["isolated", "non-strict", 1],
      ["load", "non-strict", 4],
    ],
  );
  assert.ok(artifact.runs.every(run => run.process_exit === 0));
  const measuredRuns = [...artifact.runs, ...artifact.controls];
  assert.ok(
    measuredRuns.every(run =>
      run.timeout_seconds === HARNESS_TIMEOUT_SECONDS &&
      run.results.every(result => result.timeout_seconds === HARNESS_TIMEOUT_SECONDS),
    ),
    "every measured run must receive the explicit 12-second timeout",
  );
  assert.ok(
    artifact.runs.every(run =>
      run.results.length === 4 &&
      run.results.every(result =>
        result.status === "pass" && result.mode === run.mode &&
        result.reason === "" && result.duration_ms === 2 &&
        result.timeout_seconds === HARNESS_TIMEOUT_SECONDS,
      ),
    ),
    "URI cases must pass in every mode and load condition",
  );
  assert.equal(artifact.controls.length, 4, "control runs cover both modes/conditions");
  assert.ok(artifact.controls.every(run => run.process_exit === 0));
  assert.ok(
    artifact.controls.every(run =>
      run.results.length === 1 &&
      run.results[0].status === "timeout" &&
      run.results[0].mode === run.mode &&
      run.results[0].reason === "Exceeded 12s timeout" &&
      run.results[0].duration_ms === HARNESS_TIMEOUT_SECONDS * 1000 &&
      run.results[0].timeout_seconds === HARNESS_TIMEOUT_SECONDS,
    ),
  );
  assert.ok(artifact.assessment.result);

  const missingRevisionOutput = path.join(root, "missing-revision.json");
  const missingRevisionArgs = benchmarkArgs
    .filter(value => value !== "--test262-revision" && value !== "fake-test262")
    .map(value => (value === output ? missingRevisionOutput : value));
  const cleanEnv = { ...process.env };
  delete cleanEnv.TEST262_REVISION;
  delete cleanEnv.TEST262_COMMIT;
  const missingRevision = spawnSync(process.execPath, missingRevisionArgs, {
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: cleanEnv,
  });
  assert.equal(missingRevision.status, 2, "missing Test262 provenance must fail before measuring");

  const gitSuite = path.join(root, "test262-git");
  fs.cpSync(suite, gitSuite, { recursive: true });
  const gitEnv = {
    ...cleanEnv,
    GIT_AUTHOR_NAME: "issue-695-test",
    GIT_AUTHOR_EMAIL: "issue-695-test@example.invalid",
    GIT_COMMITTER_NAME: "issue-695-test",
    GIT_COMMITTER_EMAIL: "issue-695-test@example.invalid",
  };
  const runGit = args => {
    const result = spawnSync("git", ["-C", gitSuite, ...args], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      env: gitEnv,
    });
    assert.equal(result.status, 0, result.stderr);
  };
  runGit(["init", "--quiet"]);
  runGit(["add", "."]);
  runGit(["commit", "--quiet", "-m", "fixture"]);
  const gitHead = spawnSync("git", ["-C", gitSuite, "rev-parse", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: gitEnv,
  }).stdout.trim();
  const gitOutput = path.join(root, "git-suite.json");
  const gitArgs = benchmarkArgs
    .filter(value => value !== "--test262-revision" && value !== "fake-test262")
    .map(value => {
      if (value === suite) return gitSuite;
      if (value === output) return gitOutput;
      return value;
    });
  const gitRun = spawnSync(process.execPath, gitArgs, {
    cwd: REPO_ROOT,
    encoding: "utf8",
    env: cleanEnv,
  });
  assert.equal(gitRun.status, 0, gitRun.stderr || gitRun.stdout);
  const gitArtifact = JSON.parse(fs.readFileSync(gitOutput, "utf8"));
  assert.equal(gitArtifact.test262_revision, gitHead);
  assert.equal(gitArtifact.test262_revision_source, "git");

  for (const scenario of [
    "control-missing",
    "control-extra",
    "control-mode",
    "uri-missing",
    "uri-extra",
    "uri-fail",
  ]) {
    const scenarioOutput = path.join(root, `${scenario}.json`);
    const scenarioArgs = benchmarkArgs.map(value =>
      value === output ? scenarioOutput : value,
    );
    const invalid = spawnSync(process.execPath, scenarioArgs, {
      cwd: REPO_ROOT,
      encoding: "utf8",
      env: { ...process.env, FAKE_SCENARIO: scenario },
    });
    assert.notEqual(
      invalid.status,
      0,
      `${scenario} must fail the evidence contract despite runner exit 0`,
    );
    const invalidArtifact = JSON.parse(fs.readFileSync(scenarioOutput, "utf8"));
    assert.equal(invalidArtifact.assessment.result, "invalid");
    assert.ok(invalidArtifact.evidence_errors.length > 0);
  }
}

main();
