const d = require("./test262-results.json");
console.log("=== Test262 Results ===");
console.log("Date:", d.date);
console.log("Engine:", d.engine);
console.log();

const s = d.summary;
console.log("=== Per-Task (strict + non-strict) ===");
console.log("Total test tasks:", s.total);
console.log("Skipped:", s.skipped);
const executed = s.passed + s.failed + s.timeout + (s.error || 0);
console.log("Executed:", executed);
console.log("Passed:", s.passed);
console.log("Failed:", s.failed);
console.log("Timeouts:", s.timeout);
console.log("Pass rate:", s.pass_rate + "%");

// Per-file dedup: a file passes only if ALL its modes (strict, non-strict) pass
const files = new Map();
for (const r of d.results) {
  if (r.status === "skip") continue;
  const f = r.path;
  const cur = files.get(f);
  if (cur === undefined) {
    files.set(f, r.status);
  } else if (cur === "pass" && r.status !== "pass") {
    files.set(f, r.status);
  }
}
let fPass = 0, fFail = 0, fTimeout = 0, fError = 0;
for (const [, st] of files) {
  if (st === "pass") fPass++;
  else if (st === "fail") fFail++;
  else if (st === "timeout") fTimeout++;
  else fError++;
}
const fTotal = fPass + fFail + fTimeout + fError;
console.log("\n=== Per-File (strict + non-strict combined) ===");
console.log("Executed files:", fTotal);
console.log("Passed:", fPass);
console.log("Failed:", fFail);
console.log("Timeout:", fTimeout);
console.log("Pass rate:", (fPass / fTotal * 100).toFixed(1) + "%");

// Non-strict only comparison (matching old runner methodology)
const nsFiles = new Map();
for (const r of d.results) {
  if (r.status === "skip") continue;
  if (r.mode !== "non-strict") continue;
  nsFiles.set(r.path, r.status);
}
let nsPass = 0, nsFail = 0, nsTimeout = 0;
for (const [, st] of nsFiles) {
  if (st === "pass") nsPass++;
  else if (st === "fail") nsFail++;
  else if (st === "timeout") nsTimeout++;
}
const nsTotal = nsPass + nsFail + nsTimeout;
console.log("\n=== Non-Strict Only (comparable to previous runs) ===");
console.log("Executed files:", nsTotal);
console.log("Passed:", nsPass);
console.log("Failed:", nsFail);
console.log("Timeout:", nsTimeout);
console.log("Pass rate:", (nsPass / nsTotal * 100).toFixed(1) + "%");
console.log("\nPrevious (2026-02-18): 24,519 / 27,599 (88.8%)");
console.log("Delta:", nsPass - 24519, "tests");

// Category breakdown from JSON
if (d.categories) {
  console.log("\n=== Category Breakdown (per-task) ===");
  console.log("Category".padEnd(50), "Pass".padStart(6), "Fail".padStart(6), "Skip".padStart(6), "Rate".padStart(8));
  console.log("-".repeat(76));
  const cats = Object.entries(d.categories).sort((a, b) => b[1].failed - a[1].failed);
  for (const [name, data] of cats) {
    const exec = data.passed + data.failed + (data.timeout || 0);
    if (exec === 0) continue;
    const rate = (data.passed / exec * 100).toFixed(1);
    console.log(
      name.padEnd(50),
      String(data.passed).padStart(6),
      String(data.failed).padStart(6),
      String(data.skipped).padStart(6),
      (rate + "%").padStart(8)
    );
  }
}
