# Task 4B report — migrate name-only pattern consumers

## Outcome and caller inventory

The semantic inventory used both `moon ide find-references walk_pattern_idents`
and scoped `rg`. It found 22 symbol references: the helper/its five recursive
self-calls, plus consumers in `hoisting.mbt` (eval var names, declaration names,
var hoisting, var-scoped preflight, lexical names, Annex B catch-frame names,
and TDZ hoisting), `interpreter.mbt` (duplicate checks, `arguments`, and strict
binding validation), `call.mbt` (eval conflicts and parameter predeclaration),
`construct.mbt` (constructor parameter predeclaration), and `generator.mbt`
(generator parameter predeclaration). Every consumer now loops in source order
over its newly owned `@static_semantics.bound_names` result. The old callback
helper was deleted, and final IDE/text searches find no reference.

## Assumptions

- BoundNames order reviewed in Task 2 is the compatibility order for every migrated name-only consumer.
- Set insertion and environment effects must occur once per returned name, in that order.
- Expression-sensitive and statement traversal semantics are outside this slice.

## Red / green evidence

The test first constructs 4,096 nested direct-AST array binding patterns. On JS
before production edits it failed with `RangeError: Maximum call stack size
exceeded`, repeating `check_duplicate_pattern_binding_names`. After migration it
passes and directly covers duplicate first occurrence/exact diagnostics, strict
`eval` validation, early-stop `arguments` detection, eval/var-name collection,
var hoisting, and lexical TDZ preparation. The production call, constructor, and
generator predeclaration sites use the same tested BoundNames loop without
entering runtime destructuring evaluation.

## Files and commits

- Production: `interpreter/runtime/{hoisting,interpreter,call,construct,generator}.mbt`
- Test: `interpreter/runtime/pattern_bound_names_wbtest.mbt`
- Report: `.superpowers/sdd/task-4b-report.md`
- Implementation/test commit: `1b847c8` (`refactor(runtime): use stack-safe BoundNames preparation`).

## Commands / results

- Baseline and after-file `moon check`: passed, except the expected temporary
  unbound-helper errors while its proven cross-file callers were being migrated;
  each was eliminated immediately by completing that caller migration.
- Red JS focused test: 0/1, host `RangeError` in duplicate pattern recursion.
- Green JS/native focused test: 1/1 each.
- `moon test interpreter --filter '*post-parse stack safety*'`: 7/7.
- `moon test interpreter/runtime`: 168/168.
- `moon check --deny-warn`: passed.
- `moon info`: passed; no generated interface diff.
- Touched-file `moon fmt`, final `moon check`, and `git diff --check`: passed.

## Interface audit

No public or generated interface changed. Three private functions lost obsolete
`raise Error` effects after callback removal.

## Remaining recursive pattern scans and disposition

- `pattern_contains_expression` (`interpreter.mbt`): explicitly excluded;
  expression-sensitive, not a BoundNames consumer.
- `pattern_contains_yield` (`generator.mbt`): explicitly excluded auxiliary
  predicate for Task 5.
- Early-error `Pattern` tasks in `hoisting.mbt`: already Task 3's iterative,
  expression/lex-form-aware machine and intentionally not replaced.
- Destructuring evaluation walkers and statement/Annex B walkers: intentionally
  unchanged by 4B; later Task 4/linked runtime work owns them.

## Concerns

The regression isolates shared preparation primitives rather than invoking a
deep function/generator/constructor destructuring call, because doing so would
exercise the explicitly excluded recursive runtime destructuring evaluator.
