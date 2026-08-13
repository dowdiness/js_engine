# Issue #905 source-ownership map

This map records the pre-migration ownership boundary for the final #636
source-ownership slice. AST values remain compiler input during parsing and
lowering; they must not survive in finalized bytecode carriers or runtime
entry envelopes.

## Preserved assumptions

1. Supported bytecode function forms already carry exact parser source text.
2. Existing source-unit/program and function-local owner boundaries are enough
   to identify nested children; no global source-ID registry is required.
3. Runtime remains the owner of environment mutation, global-object semantics,
   JavaScript errors, realm installation, and exception conversion.

## Inventory

| Current use | Classification | Target owner |
| --- | --- | --- |
| `BytecodeProgram.source_stmts` | execution preparation leakage | immutable root-script preparation plus source metadata |
| `BytecodeUnverifiedProgram.source_stmts` | lowering carrier leakage | immutable root-script preparation |
| `BytecodeFunction.source_body` | verification/source-tree leakage | canonical preparation facts plus exact source metadata |
| `BytecodeHeaderProvenance.origin_body` | child identity leakage | source-unit/function-owner identity, parent owner, child index, consumer form |
| `physical_equal(origin_body, child.source_body)` | obsolete AST identity proof | typed child/header identity and coordinated facts |
| `validate_function_signature(... body)` during lowering | lowering-only source input | copied immutable signature facts tied to child/header provenance |
| `verify_executor_activation_capability(... body)` during lowering | lowering-only source input | opaque immutable activation-capability summary compared inside runtime |
| `Interpreter::run_compiled_script(stmts, ...)` | runtime AST entry ownership | prepared strictness, early-error proof, declaration facts, and runtime application |
| parser function-node source text | exact source metadata | immutable function source text copied at lowering |
| `SourceUnitHandle`, `SourcePointOwnerId` and source-point tables | typed diagnostics/observation identity | retained source identity and locations; no AST required |
| `DestructurePlan` runtime adapter | explicitly deferred runtime detail | unchanged, ephemeral plan-to-AST adapter while activation remains unsupported |

## Runtime script responsibilities to preserve

The prepared root entry must preserve strictness, early-error ordering,
global var/function/lexical setup order, TDZ setup, global-object mirroring and
property attributes, active-realm installation, and JavaScript exception
conversion. Preparation describes facts; runtime applies those facts through
the existing semantic operations.

Finalization receives no source AST. Child verification compares typed source
identity, exact source text, header snapshots, canonical signature/lexical
facts, declaration consumers, and the runtime-owned activation summary. Root
preparation is checked against the verified root's strictness, var names,
function names, and lexical binding order before the verified carrier is built.

## Required negative evidence

Verification tests must reject coordinated mutation of child identity, exact
source text, current header/signature fields, preparation facts, activation
capability, and root declaration preparation. The architecture audit must use
resolved type evidence and reject executable AST fields in finalized carriers.
