import assert from "node:assert/strict";
import test from "node:test";
import {
  compareExampleSources,
  diagnosticSelection,
  isCurrentResponse,
  isCurrentWorker,
  isSourceWithinLimit,
} from "../src/playground-contracts.ts";

test("accepts only the response from the active request and worker", () => {
  const activeRun = { requestId: "new-request", workerId: 2 };

  assert.equal(
    isCurrentResponse(activeRun, { requestId: "new-request" }, 2),
    true,
  );
  assert.equal(
    isCurrentResponse(activeRun, { requestId: "old-request" }, 2),
    false,
  );
  assert.equal(
    isCurrentResponse(activeRun, { requestId: "new-request" }, 1),
    false,
  );
  assert.equal(
    isCurrentResponse(undefined, { requestId: "new-request" }, 2),
    false,
  );
  assert.equal(isCurrentWorker(activeRun, 2), true);
  assert.equal(isCurrentWorker(activeRun, 1), false);
  assert.equal(isCurrentWorker(undefined, 2), false);
});

test("does not select a diagnostic from a changed source", () => {
  const location = {
    start: { line: 1, column: 5, offset: 4 },
    end: { line: 1, column: 6, offset: 5 },
  };

  assert.deepEqual(
    diagnosticSelection("let =", "let =", location),
    { from: 4, to: 5 },
  );
  assert.equal(diagnosticSelection("let =", "safe();", location), undefined);
  assert.equal(diagnosticSelection("let =", "let =", null), undefined);
  assert.deepEqual(
    diagnosticSelection(
      "safe();",
      "safe();",
      {
        start: { offset: 99 },
        end: { offset: 99 },
      },
    ),
    { from: 7, to: 7 },
  );
  assert.deepEqual(
    diagnosticSelection(
      "safe();",
      "safe();",
      {
        start: { offset: 99 },
        end: { offset: 0 },
      },
    ),
    { from: 7, to: 7 },
  );
});

test("reports example files that are missing, changed, or unexpected", () => {
  assert.deepEqual(
    compareExampleSources(
      {
        arith: "1 + 2;",
        closure: "(() => 1)();",
      },
      {
        arith: "1 + 3;",
        extra: "true;",
      },
    ),
    {
      missing: ["closure"],
      unexpected: ["extra"],
      changed: ["arith"],
    },
  );
});

test("enforces the source limit in UTF-16 code units", () => {
  assert.equal(isSourceWithinLimit("x".repeat(100_000), 100_000), true);
  assert.equal(isSourceWithinLimit("x".repeat(100_001), 100_000), false);
  assert.equal(isSourceWithinLimit("😀", 1), false);
  assert.equal(isSourceWithinLimit("😀", 2), true);
});