#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const { main, makeScript } = require("./compat_table_runner.js");

function writeFixture(root) {
  const compatRoot = path.join(root, "compat-table");
  fs.mkdirSync(path.join(compatRoot, "test-utils"), { recursive: true });
  fs.writeFileSync(path.join(compatRoot, "data-common.json"), "{}\n");
  fs.writeFileSync(
    path.join(compatRoot, "test-utils", "testHelpers.js"),
    'exports.createIterableHelper = "";\n',
  );
  fs.writeFileSync(
    path.join(compatRoot, "data-es5.js"),
    `exports.name = "ES5";
exports.tests = [
  {
    name: "Core feature",
    significance: "large",
    subtests: [
      { name: "passes", exec: function () {/* return "PASS_STANDARD"; */}, res: {} },
      { name: "fails", exec: function () {/* return "FAIL_STANDARD"; */}, res: {} }
    ]
  },
  {
    name: "Annex feature",
    category: "annex b",
    significance: "small",
    exec: function () {/* return "PASS_ANNEX"; */},
    res: {}
  }
];
`,
  );

  return compatRoot;
}

test("CLI separates standard and Annex B and writes reproducible reports", () => {
  const tempRoot = fs.mkdtempSync(path.join("/tmp", "compat-table-runner-"));
  try {
    const compatRoot = writeFixture(tempRoot);
    const output = path.join(tempRoot, "results.json");
    const markdown = path.join(tempRoot, "summary.md");
    main([
        "--compat-table",
        compatRoot,
        "--compat-table-commit",
        "fixture-commit",
        "--engine",
        process.execPath,
        "--output",
        output,
        "--markdown",
        markdown,
        "--suite",
        "es5",
        "--timeout-ms",
        "200",
      ],
      {
        spawn(_engine, args) {
          const annexB = args[0] === "--annex-b";
          const source = args[args.length - 1] || "";
          const passed =
            (source.includes("PASS_STANDARD") && !annexB) ||
            (source.includes("PASS_ANNEX") && annexB);
          return {
            status: 0,
            signal: null,
            stdout: passed ? "[SUCCESS]\n" : "",
            stderr: "",
          };
        },
        stdout: { write() {} },
      },
    );

    const report = JSON.parse(fs.readFileSync(output, "utf8"));
    assert.equal(report.schema_version, 1);
    assert.equal(report.compat_table.commit, "fixture-commit");
    assert.deepEqual(report.scope.suites, ["es5"]);
    assert.deepEqual(report.summary.standard, {
      features: 1,
      subtests: 2,
      passed: 1,
      failed: 1,
      skipped: 0,
      timeout: 0,
      weighted_earned: 0.5,
      weighted_possible: 1,
      weighted_percent: 50,
      passed_percent: 50,
    });
    assert.equal(report.summary.annex_b.features, 1);
    assert.equal(report.summary.annex_b.passed, 1);
    assert.equal(report.summary.annex_b.weighted_percent, 100);
    assert.equal(report.results.length, 3);
    assert.equal(
      report.results.find((entry) => entry.test === "Annex feature").annex_b,
      true,
    );

    const rendered = fs.readFileSync(markdown, "utf8");
    assert.match(rendered, /compat-table feature coverage/);
    assert.match(rendered, /\| ES5 \| 50\.0% \| 1 \/ 2 \|/);
    assert.match(rendered, /Annex B/);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("CLI treats engine launch errors as infrastructure failures", () => {
  const tempRoot = fs.mkdtempSync(path.join("/tmp", "compat-table-runner-"));
  try {
    const compatRoot = writeFixture(tempRoot);
    const launchError = new Error("spawn EACCES");
    launchError.code = "EACCES";
    assert.throws(
      () =>
        main(
          [
            "--compat-table",
            compatRoot,
            "--compat-table-commit",
            "fixture-commit",
            "--engine",
            process.execPath,
            "--output",
            path.join(tempRoot, "results.json"),
            "--markdown",
            path.join(tempRoot, "summary.md"),
            "--suite",
            "es5",
          ],
          {
            spawn() {
              return {
                error: launchError,
                status: null,
                signal: null,
                stdout: "",
                stderr: "",
              };
            },
            stdout: { write() {} },
          },
        ),
      /engine execution failed: spawn EACCES/,
    );
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
});

test("async helper does not report success after test evaluation throws", async () => {
  const output = [];
  const testCode = `(function () {
    setTimeout(function () { asyncTestPassed(); }, 0);
    throw new Error("boom");
  })()`;
  vm.runInNewContext(makeScript(testCode, ""), {
    console: { log(value) { output.push(value); } },
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.deepEqual(output, []);
});
