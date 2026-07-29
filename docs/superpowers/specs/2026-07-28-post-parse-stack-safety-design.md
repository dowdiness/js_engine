# Post-parse stack safety design

## Goal

Make deterministic post-parse AST validation, fact collection, and preparation
independent of host call-stack depth without changing accepted programs,
diagnostic selection, source locations, strictness, or scope boundaries.

Dynamic guest execution and runtime re-entry remain outside this design. Parser
recursion is classified separately whenever parsing fails before producing an
AST.

## Invariants

- Finite guest-controlled AST depth consumes constant host call depth and an
  engine-owned work stack proportional to pending traversal depth.
- Every iterative traversal preserves the recursive implementation's exact
  operation order, including checks performed before or between child visits.
- The first raised diagnostic remains the same in kind, message, and source
  location.
- Strictness, binding role, statement-list policy, and lexical-frame lifetime
  are carried explicitly by work items rather than traversal-global flags.
- Function, arrow, class, pattern-expression, and module boundaries remain
  operation-specific.
- Internal mutable work collections never escape. Fact-producing operations
  return newly owned, source-ordered results.

## Architecture

Early-error validation uses one private heterogeneous work machine because its
statement, expression, pattern, parameter, class-member, and statement-list
operations are mutually recursive and observably ordered. Deferred checks are
represented as work items, and children are pushed in reverse so the existing
left-to-right processing order is preserved.

Pattern binding-name extraction becomes one stack-safe static-semantic
operation. Hoisting, Annex B, eval containment, yield/await predicates, and
module graph algorithms retain separate operation-specific iterative walkers;
their traversal boundaries are not interchangeable.

The existing immediate-expression and immediate-pattern child APIs are reused
only where their documented edge set and order exactly match the owning
semantic operation. Special function, class, template, assignment, and pattern
cases remain explicit and exhaustive.

## Functional core and imperative shell

Deterministic walkers consume AST plus immutable context and either return
ordered facts or raise the existing diagnostic immediately. Environment
mutation, module state changes, reporting, and execution stay in existing
interpreter adapters. Private arrays may implement work stacks, but adapters
receive only final owned facts.

## Scope inventory

The implementation inventory covers recursive post-parse traversals reachable
from script execution, direct eval, function and generator preparation, block
entry, compiled-script preparation, and module entry. Each traversal is marked
iterative, proven bounded for parser-produced ASTs, or assigned to a linked
follow-up.

Parser recursion, tree-walking execution recursion, closure conversion, and
bytecode lowering are classified explicitly but are not silently folded into
this change.

## Testing

Each proven recursion shape receives a focused regression before its walker is
changed. The permanent end-to-end regression includes the 512-level comma
expression characterized by issue #616. Direct-AST tests isolate statement,
pattern, class, and module preparation from parser and execution recursion.

Shallow competing-error tests pin diagnostic order at function, class, switch,
template, pattern, and strict-mode boundaries. Cross-target checks use fixed
depths with substantial margin and never encode measured host-stack thresholds
as engine behavior.

## Delivery

Changes land in reviewable slices: caller inventory and behavior
characterization, shared binding-name facts, early-error work machine,
declaration and Annex B walkers, auxiliary preparation scans, then module AST
and graph traversal. Every slice keeps the repository buildable and testable.
