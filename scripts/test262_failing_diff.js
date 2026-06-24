// Diff two Test262 runner artifacts by per-mode failing SET.
//
// Usage: node scripts/test262_failing_diff.js <baseline.json> <candidate.json>
//
// Emits the per-mode (path, mode) failures that the candidate INTRODUCES
// (regressions, baseline-pass -> candidate-fail) and RESOLVES (fixed,
// baseline-fail -> candidate-pass). Set-difference, not counts: a run that
// trades one fail for another nets zero on counts but is surfaced here.
//
// Each artifact conforms to scripts/test262_result_contract.schema.json:
// results[] carry `path`, `status` ("fail"), and `mode` ("strict" /
// "non-strict"); summary.failed is the authoritative fail count. Before
// trusting any diff we validate summary.failed === count(status === "fail")
// for each input — a mismatch means the extractor or artifact is broken, so
// we abort rather than report a false "0 regressions".

function loadFails(path) {
  const data = require(require("path").resolve(path));
  const fails = new Set();
  let counted = 0;
  for (const r of data.results) {
    if (r.status === "fail") {
      fails.add(`${r.path}\t${r.mode}`);
      counted++;
    }
  }
  if (counted !== data.summary.failed) {
    throw new Error(
      `${path}: summary.failed=${data.summary.failed} but counted ${counted} ` +
        `fail results — artifact/extractor disagree, refusing to diff`,
    );
  }
  return fails;
}

function report(title, set) {
  console.log(`${title} (${set.size}):`);
  for (const key of [...set].sort()) {
    const [p, mode] = key.split("\t");
    console.log(`  ${mode.padEnd(10)} ${p}`);
  }
  if (set.size === 0) console.log("  (none)");
}

function main() {
  const [, , baselinePath, candidatePath] = process.argv;
  if (!baselinePath || !candidatePath) {
    console.error(
      "usage: node scripts/test262_failing_diff.js <baseline.json> <candidate.json>",
    );
    process.exit(2);
  }
  const baseline = loadFails(baselinePath);
  const candidate = loadFails(candidatePath);
  const regressions = new Set([...candidate].filter((k) => !baseline.has(k)));
  const fixed = new Set([...baseline].filter((k) => !candidate.has(k)));

  report("REGRESSIONS (newly failing)", regressions);
  console.log();
  report("FIXED (newly passing)", fixed);
  console.log();
  console.log(
    `baseline fails=${baseline.size}  candidate fails=${candidate.size}  ` +
      `regressions=${regressions.size}  fixed=${fixed.size}`,
  );

  process.exit(regressions.size === 0 ? 0 : 1);
}

main();
