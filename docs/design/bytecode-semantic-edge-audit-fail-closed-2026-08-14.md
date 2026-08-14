# Bytecode semantic-edge audit: fail-closed v3 evidence

This note records the issue #897 migration from the coordinate-bearing v2
callsite inventory to the coordinate-independent semantic lifecycle
multigraph. The audit remains source-backed evidence; it does not classify
bytecode instructions or change runtime behavior.

## Baseline migration evidence

The canonical roots are exactly:

```
BytecodeExecutorCode::start
BytecodeFrame::step
BytecodeFrame::deliver_activation_completion
run_bytecode_function
```

Before migration, the checked-in v2 baseline had SHA-256
`b871d9699f89ebe673881a7a2d2d892bd5ac0ac0f0e383af100036f7b0d19054`, 238
resolved callsites, and 100 runtime-boundary callsites. The v3 baseline has
SHA-256 `6790f3d29a7a23dcc96f6b2dd8bff49549c34655d38c8ac9decaf739c76e733d`,
114 semantic edges, 241 callsites after resolver hardening, and 103 runtime
boundaries. Its 78 runtime edge records carry those 103 callsite counts.

The migration proof covered every v2 callsite exactly once: 238 v2 callsites,
238 aggregated v2 callsites, and multiplicity conservation true. Three newly
resolved direct runtime calls were added to the reviewed current graph:

```
compiler/bytecode_vm.mbt:355  make_bytecode_func
  -> @dowdiness/js_engine/interpreter/runtime.make_prepared_executor_function
compiler/bytecode_vm.mbt:393  make_bytecode_method_func
  -> @dowdiness/js_engine/interpreter/runtime.make_prepared_executor_function
compiler/bytecode_vm.mbt:417  make_bytecode_arrow_func
  -> @dowdiness/js_engine/interpreter/runtime.make_prepared_executor_arrow_function
```

## Resolver boundary

The resolver returns explicit `ResolvedCompiler`, `ResolvedRuntime`,
`ResolvedOutOfScope`, `IntentionallyIgnored`, `UnresolvedCandidate`, or
`AmbiguousCandidate` outcomes. Only compiler-package and interpreter/runtime
identities become graph edges. Comments, raw text, escaped interpolation, and
literal-only text remain intentional ignores; resolved external identities are
out of scope rather than failures.

Unresolved and ambiguous executable candidates fail closed. Their deterministic
diagnostics retain path, line, column, enclosing symbol, spelling, resolver
phase, command/JSON/identity detail, and sorted ambiguity candidates. The
report starts with unresolved and ambiguous totals, followed by sorted source
locations.

## Multigraph identity

Each v3 baseline record is keyed only by `enclosing`, `kind`, and `target`, and
stores callsite `count` plus the sorted canonical-root subset in
`reachable_from`. Source path and coordinates remain on live raw diagnostics
and are excluded from baseline equality. Thus comments, blank lines,
coordinate-only movement, and moving a symbol between files do not change the
baseline; call addition/removal, caller/kind/target changes, multiplicity, or
root reachability do.

The implementation keeps semantic parsing, classification, aggregation, and
comparison deterministic. Moon IDE/index processes and temporary fixture
files remain in the thin audit shell.

## Canonical update safety

`--update --root-symbol ...` is rejected before indexing and before the
baseline is opened or written. Only the built-in four-root graph may update
the canonical file. A canonical `--update --self-test` records v2 migration
evidence before writing the v3 payload.
