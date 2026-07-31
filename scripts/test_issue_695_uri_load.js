#!/usr/bin/env node

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REPO_ROOT = path.resolve(__dirname, "..");
const BENCHMARK = path.join(REPO_ROOT, "scripts", "test262_uri_load_repro.js");

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
const entries = fs.readFileSync(testsFile, "utf8").split(/\\n/).filter(Boolean);
const results = entries.map(path => ({
  path,
  mode,
  status: path.includes("known-hang.js") ? "timeout" : "pass",
  reason: path.includes("known-hang.js") ? "Exceeded 5s timeout" : "",
  duration_ms: path.includes("known-hang.js") ? 5000 : 2,
}));
const counts = status => results.filter(result => result.status === status).length;
fs.writeFileSync(output, JSON.stringify({
  engine: "fake",
  summary: { total: results.length, passed: counts("pass"), failed: 0, skipped: 0, timeout: counts("timeout"), error: 0 },
  categories: {},
  results,
}));
process.stdout.write(JSON.stringify({ mode, threads: Number(value("--threads")) }) + "\\n");
`,
    0o755,
  );

  const output = path.join(root, "result.json");
  const run = spawnSync(
    process.execPath,
    [
      BENCHMARK,
      "--runner",
      fakeRunner,
      "--engine",
      "fake",
      "--test262",
      suite,
      "--control",
      control,
      "--iterations",
      "1",
      "--timeout",
      "5",
      "--output",
      output,
    ],
    { cwd: REPO_ROOT, encoding: "utf8" },
  );
  assert.equal(run.status, 0, run.stderr || run.stdout);

  const artifact = JSON.parse(fs.readFileSync(output, "utf8"));
  assert.equal(artifact.ticket, 695);
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
  assert.ok(artifact.runs.every(run => run.results.length === 4));
  assert.equal(artifact.controls.length, 4, "control runs cover both modes/conditions");
  assert.ok(artifact.controls.every(run => run.process_exit === 0));
  assert.ok(
    artifact.controls.every(run =>
      run.results.length === 1 && run.results[0].status === "timeout" && run.results[0].mode === run.mode,
    ),
  );
  assert.ok(artifact.assessment.result);
}

main();
