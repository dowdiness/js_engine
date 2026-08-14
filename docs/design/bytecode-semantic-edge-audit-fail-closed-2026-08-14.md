# Bytecode semantic-edge audit: fail-closed evidence

This note records the issue #897 starting evidence and the resolver boundary
that the audit hardens. It is source-backed at `9632e92d876c36bb47f34906aa3ff7176be42838`;
the historical issue counts are not used as current evidence.

## Starting evidence

The canonical roots remain exactly:

```
BytecodeExecutorCode::start
BytecodeFrame::step
BytecodeFrame::deliver_activation_completion
run_bytecode_function
```

The canonical command is:

```
python3 scripts/audit_bytecode_vm_semantic_edges.py --root . --self-test
```

The checked-in baseline has SHA-256
`b871d9699f89ebe673881a7a2d2d892bd5ac0ac0f0e383af100036f7b0d19054`, 238
edges, and 100 runtime boundaries. Its JSON version is 2 and its roots are
the four symbols above. Before implementation, the deterministic fixture
self-test passed. A fresh canonical index found 239 edges and 101 runtime
boundaries: the only difference was the executable
`BytecodeFrame::step_bytecode` →
`@dowdiness/js_engine/interpreter/runtime.raise_js_exception` edge at
`compiler/bytecode_vm.mbt:1188:18`. This is the only baseline update candidate;
it must be reproduced by the canonical command after the resolver is hardened.

## Affected callers and reachable values

The audit has one resolver pipeline:

| Caller | Reachable value | Current boundary |
| --- | --- | --- |
| `main` → `ensure_semantic_index` | `CompletedProcess` from `moon check --deny-warn` | index failure raises a command error |
| `semantic_edges_from_roots` → `load_symbols` | JSONL `dict` entries with `kind`, `pkg`, `path`, `range`, and `name_range` | compiler/runtime packages are retained |
| `semantic_edges_from_roots` → `candidate_locations` | source path, line/column, and spelling candidates | text coordinates are sent to hover |
| `resolve_hover` | subprocess return code, stdout/stderr, JSON object, `contents` strings, callable identity | failure, malformed JSON, missing identity, and non-unique mapping collapse to `None` |
| `local_target` | compiler identity or simple-name matches | zero/multiple matches collapse to `None`; first unique match is selected |
| `semantic_references` fallback | reference locations parsed from stdout | nonzero command and malformed/unmatched output collapse to an empty list |
| `semantic_edges_from_roots` | edge tuples `(enclosing, path, line, column, kind, target)` | only resolved compiler/runtime tuples survive |
| `render_payload` / baseline comparison | JSON payload and edge counts | unresolved candidates never reach the report |

The resolver implementation keeps these values distinct: resolved compiler,
resolved runtime, resolved out-of-scope, intentional ignore, unresolved
candidate, and ambiguous candidate. A diagnostic retains the candidate path,
line, column, enclosing symbol, spelling, resolver phase, command, and JSON or
identity/candidate detail. Diagnostics are sorted before reporting.

## Former silent discards

The current implementation silently skips all of the following when hover or
reference resolution returns no usable target:

1. Moon IDE hover/index nonzero exit.
2. Malformed hover JSON.
3. Missing required hover JSON fields.
4. Hover payload without a callable identity.
5. Ambiguous or unresolved unqualified compiler mapping.
6. A failed `find-references` fallback (indistinguishable from no references).
7. Candidate text in comments, raw `#|` strings, escaped interpolation, or
   literal-only text (these remain intentional ignores, not errors).

Successfully resolved calls outside the compiler/runtime packages remain
`ResolvedOutOfScope` and are not graph edges or errors. Runtime and compiler
simple-name collisions are never resolved by receiver spelling or by a text
allowlist; multiple local matches produce an explicit sorted ambiguity.

## Preserved assumptions

`moon ide gen-symbols` plus a fresh `moon check --deny-warn` is the semantic-index authority.
Only compiler-package and interpreter/runtime callable identities become graph edges.
Canonical baseline update is valid only for the built-in four roots and never for a partial graph.
