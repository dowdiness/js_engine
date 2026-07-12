# Plan 001: Enforce private-member `yield` and `await` early errors

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report; do not improvise. When done, update
> this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat f806f28..HEAD -- ast/ast.mbt parser/early_errors.mbt parser/parser_test.mbt`
> If any in-scope file changed, compare the current-state excerpts with live code.
> A semantic mismatch is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `f806f28`, 2026-07-13

## Why this matters

The parser's `Contains YieldExpression` and `Contains AwaitExpression` scans do
not traverse the recently added private-member expression variants. The engine
therefore accepts syntactically invalid arrow parameter initializers such as a
private-member read whose receiver contains `yield` or `await`. This plan adds
spec-anchored regression coverage and fixes only that missing traversal; the
larger containment-walk refactor is deliberately isolated in plan 006.

## Current state

- `ast/ast.mbt:122,186-188` defines `PrivateMemberAssign`, `PrivateIdent`, and
  `PrivateMember`. A private read contains one child expression; a private
  assignment contains receiver and value child expressions.
- `parser/early_errors.mbt:46-113` recursively implements `expr_has_yield` but
  has no private-member arms and ends in `_ => false`.
- `parser/early_errors.mbt:163-230` has the same omission in `expr_has_await`.
- `parser/early_errors.mbt:82-100,199-217` intentionally treats arrow parameter
  defaults, class heritage, and computed class keys differently from full
  function boundaries. Preserve those distinctions.
- `test262/test/language/expressions/arrow-function/param-dflt-yield-expr.js:9-21`
  quotes the applicable rule: it is a syntax error when `ArrowParameters`
  Contains `YieldExpression`.
- `parser/parser_test.mbt:753-779` demonstrates the local parser-test convention:
  call `@parser.parse`, catch the error into a `Result`, and assert the error
  outcome. Match that convention rather than snapshotting error prose.

Observed reproductions at `f806f28`:

- Inside a generator class method, an arrow default containing
  `(yield this).#x` is accepted and the script reaches `console.log("parsed")`.
- Inside an async class method, an arrow default containing
  `(await this).#x` is accepted and reaches the same marker.
- Node.js rejects both during parsing. This parity probe is supporting evidence;
  the Test262/spec rule, not Node's message text, defines the contract.

MoonBit conventions: keep top-level blocks separated by `///|`; use `guard` for
early exits; do not hand-edit `pkg.generated.mbti`; run `moon check` after every
source-file edit before touching another source file.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Caller/shape audit | `moon ide outline parser/ && moon ide outline ast/` | exit 0; current parser and AST symbols listed |
| Focused parser tests | `moon test parser --filter '*private*early*error*'` | after implementation, all selected tests pass |
| Typecheck after each edit | `moon check` | exit 0, no diagnostics |
| Full tests | `moon test` | exit 0, all tests pass |
| Interfaces | `moon info` | exit 0; no public-interface change expected |
| Format | `moon fmt` | exit 0 |

## Suggested executor toolkit

- Read `skill://moonbit-agent-guide` and `skill://moonbit-verification` if those
  skills are available.
- Read the `info` field of the cited Test262 test before writing assertions.
- Use `moon ide` for MoonBit definitions/references; fall back to text search only
  if the IDE cannot resolve the native/current package.

## Scope

**In scope**:

- `parser/parser_test.mbt` — end-to-end parse regressions and controls.
- `parser/early_errors.mbt` — explicit private-node traversal.

**Read-only context**:

- `ast/ast.mbt` — confirms variant child shapes; do not change it.
- Targeted Test262 files under `test262/test/language/expressions/`.

**Out of scope**:

- Runtime private-brand storage, private access evaluation, or class semantics.
- Moving early errors into `static_semantics/`.
- General AST visitor/fold extraction; plan 006 owns that refactor.
- Compiler support for private syntax.
- Error-message wording changes or generated interface edits.

## Git workflow

- Branch: `fix/private-member-early-errors`.
- Commit the failing tests separately if the operator wants a visible TDD
  sequence; otherwise one focused `fix(parser): traverse private members in early errors` commit is acceptable.
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Audit callers, node shapes, and the exact rule

1. Use semantic navigation to enumerate every caller of `expr_has_yield`,
   `pat_has_yield`, `expr_has_await`, and `pat_has_await`.
2. Inspect the possible `@ast.Expr` variants supplied on each path. Confirm that
   the functions are containment scans for arrow/default early errors, not
   general evaluator scans.
3. Read the nearest Test262 `info` blocks for yield and await in formal
   parameters. Confirm whether private-member syntax changes only traversal, not
   the surrounding grammar context.
4. Record assumptions in the work log in at most three lines. They must include:
   private member reads traverse the receiver; private assignments traverse
   receiver and value; `PrivateIdent` has no expression child.

**Verify**: the caller list and variant map account for all four private-related
AST forms. If a new private form exists at HEAD, stop and revise the test matrix
before editing.

### Step 2: Add failing end-to-end parser tests

Add parser tests whose names contain `private early error` so the focused filter
is stable. Cover all observable boundaries:

1. Generator method + nested arrow default + private read receiver containing
   `yield` → parse error.
2. Generator method + nested arrow default + private assignment receiver
   containing `yield` → parse error.
3. Generator method + nested arrow default + private assignment value containing
   `yield` → parse error, if that source form is valid enough to reach the
   Contains rule.
4. Async method equivalents for `await` read/receiver/value.
5. Positive controls: ordinary `this.#x` and `this.#x = value` in defaults that
   contain no forbidden expression still parse in the private-name lexical
   scope.
6. A boundary control showing `yield`/`await` inside a nested full function body
   is not attributed to the enclosing arrow parameters.

Use `@parser.parse` directly. Assert parse success/failure, not Node-specific
message strings.

**Verify**: `moon test parser --filter '*private*early*error*'` must fail only on
the new negative cases because the parser incorrectly accepts them. If it fails
for lexical private-name resolution before reaching the intended rule, adjust
the enclosing class fixture; do not weaken the assertion.

### Step 3: Implement the minimal private-node traversal

In both containment functions:

- Treat `PrivateMember(receiver, ...)` like other named-member expressions and
  recurse into `receiver`.
- Treat `PrivateMemberAssign(receiver, ..., value, ...)` like ordinary named
  member assignment and recurse into both expression children.
- Treat `PrivateIdent` as a leaf.
- Do not alter function, arrow, class, destructuring, or async boundary rules.
- Keep the change explicit; do not introduce a visitor abstraction in this bug
  fix.

**Verify immediately after editing `parser/early_errors.mbt`**: `moon check` →
exit 0. Do not edit another source file until it passes.

### Step 4: Prove the focused contract

Run `moon test parser --filter '*private*early*error*'`.

Expected: every new negative and positive control passes. Then run the existing
nearby parser early-error tests to ensure the change did not broaden rejection.

### Step 5: Finalize and inspect public surface

Run, in order:

1. `moon test parser`
2. `moon test`
3. `moon info`
4. Review `git diff -- '*pkg.generated.mbti'`; expected: no semantic public API
   change.
5. `moon fmt`
6. `moon check`
7. Re-run `moon test parser --filter '*private*early*error*'` after formatting.

## Test plan

The required tests are the six negative read/assignment receiver/value cases,
positive private read/assignment controls, and one nested-function boundary
control. They defend parse acceptance/rejection, which is the observable
contract. They must fail before implementation for the expected false-negative
reason and remain deterministic under the full suite.

## Done criteria

- [ ] Caller/type audit is recorded and assumptions fit in three lines.
- [ ] New tests demonstrate the pre-fix false-negative parse behavior.
- [ ] `expr_has_yield` and `expr_has_await` explicitly cover every private AST
      variant according to its child shape.
- [ ] Focused private early-error tests pass.
- [ ] `moon test parser` and `moon test` exit 0.
- [ ] `moon info` exits 0 and generated-interface review shows no unintended API
      change.
- [ ] `moon fmt` and final `moon check` exit 0.
- [ ] Only in-scope files are modified, plus formatter-generated changes within
      those files.
- [ ] The status row in `plans/README.md` is updated.

## STOP conditions

Stop and report if:

- The exact ECMAScript/Test262 rule contradicts the proposed containment cases.
- Current private AST variants differ from the stated child shapes.
- A negative fixture fails for undeclared-private-name parsing instead of the
  yield/await formal-parameter rule.
- Correct behavior requires grammar-context changes outside
  `parser/early_errors.mbt`.
- Any source edit cannot be made type-correct before another source file must be
  changed.
- A focused verification fails twice after a reasonable correction.

## Maintenance notes

When any new `@ast.Expr` variant is added, review all containment scans before
merging it. Plan 006 centralizes traversal mechanics but must preserve the
semantic boundary matrix pinned here. Reviewers should verify that this fix does
not accidentally descend into nested full function bodies or change error
ordering/message behavior.
