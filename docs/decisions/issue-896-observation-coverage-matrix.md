# Issue #896 observation-coverage matrix

This matrix fixes the verifier seam before representation work. `[]` means no
mandatory observation is active. `S` and `E` name the function-local statement
and expression observation entries currently emitted by lowering; a barrier
instruction itself is entered with its parent context, and the instructions
after it run with the new context. A context may be left when lowering returns
from a nested statement/expression region. A reachable edge may therefore
enter a context equal to, or a prefix of, the source context after the
instruction, but may not enter the middle of a deeper or different region.

| Edge family / lowering shape | Successors | Active observations at the edge | Intentional skip | Illegal entry | Current metadata suffices? |
| --- | --- | --- | --- | --- | --- |
| `Jump` (unconditional) | target only | source post-context → target context | yes, when target exits a region (for example a break/optional short-circuit exit) | target after a mandatory `S`/`E` entry, or in a sibling/deeper region | No: roles and source identities do not encode region context |
| `JumpIfFalse` | target and fallthrough | condition `E` is complete at both exits; each branch enters its own statement region at its `S` barrier | else branch may skip the then statement; loop false branch may skip the body | either successor enters a statement/expression body after its barrier | No |
| `JumpIfFalseKeep` | target and fallthrough | logical-left `E`; target keeps the left value, fallthrough enters logical-right `E` barrier | target skips right-hand syntax by design | target enters the right-hand body after its `E` barrier | No |
| `JumpIfTrueKeep` | target and fallthrough | same shape as `JumpIfFalseKeep`, with truthy target | target skips right-hand syntax by design | middle entry to right-hand `E` body | No |
| `JumpIfNotNullishKeep` | target and fallthrough | nullish-left `E`; optional/member continuation or logical-right `E` begins at its own barrier when one exists | target may skip a nullish continuation or right-hand operand | target enters continuation/key/argument work after its mandatory entry | No |
| `JumpIfNotOptionalChainShortCircuitKeep` | target and fallthrough | current optional-chain `E`; target continues only after the chain short-circuit check | short-circuited chain may skip the continuation | target enters a continuation region after its chain/child observation | No |
| `ForInNext` target | target and fallthrough | loop condition/iterator context is complete; target exits through `EndForIn` cleanup | target skips loop body when enumeration is done | target enters cleanup or a later body after an observation barrier | No |
| `ForInNext` fallthrough | target and fallthrough | iterator context remains active; body starts at its `S` barrier | no body skip on this successor | fallthrough-side mutation into body middle or a later statement | No |
| normal fallthrough | `index + 1` | instruction post-context to next instruction context | leaving a completed nested region is valid | next instruction is inside a deeper region without its barrier | No |
| `code.length` terminal | no instruction | `[]` after ordinary completion; abrupt `Return`/`Throw` may discard loop resources | normal completion can fall out at the terminal boundary | a reachable non-empty region is represented as terminal without its barrier | No |
| loop entry | condition/body successor | outer context; condition and body each enter at their emitted barriers | a zero-iteration loop skips the body region | entry after body `S`/`E` observation | No |
| loop continue | continue target (condition or update) | outer context; target begins at the loop's next condition/update region | body remainder is intentionally skipped | target enters condition/update middle | No |
| loop back-edge | condition target | outer context after body/update | body remainder is skipped; condition is re-evaluated | target enters condition body after its `E` barrier | No |
| loop break / exit | cleanup or loop exit | outer context; `for-in` break first enters `EndForIn` | remaining loop body/update is skipped | break target enters later statement/expression middle | No |
| nested function child | child function entry independently starts at `[]` | parent only reaches the child value/declaration instruction; child CFG has a fresh context root | parent does not inherit the child's active observations | malformed child target or child metadata may not be accepted through parent verification | No: current recursive verification checks source ownership, not observation coverage |

The existing `instruction_sources` table and exhaustive
`bytecode_instruction_transfer` function provide source roles and successor
shape, but neither records the active observation context at each instruction
or the context after an abrupt edge. The smallest added fact is a pair of
function-local typed tables emitted by lowering: an immutable context snapshot
before each instruction, plus an edge fact carrying the expected target
context for every non-fallthrough successor and every fallthrough whose scope
pop changes context. The verifier independently checks each edge fact against
the actual exhaustive transfer and target snapshot, then traverses reachable
states separately from resource-shape states. Source-point identity anchors
entries to actual `ObserveStatement`/`ObserveExpression` instructions; no
locations, AST ranges, runtime state, or second opcode registry are involved.
