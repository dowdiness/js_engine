# Bytecode try/catch/finally

The ordinary and candidate bytecode compilers share general completion handling
for try/catch/finally. Returns, labeled breaks, and continues are supported inside
protected code, catch clauses, and finalizers. Functions are not excluded merely
because their try statements contain abrupt completions.

## Completion handling

Each handler records its protected range, handler range, environment, and resource
snapshot. Its phase is protected execution, catch execution, or finally execution
with a saved completion. A pure decision function chooses whether to stay in a
region, enter catch, enter finally, or unwind. The VM applies the decision.

A normally completing finally resumes the saved completion. An abrupt completion
from finally replaces it. Nested handlers apply the same rule independently.
This follows [ECMAScript TryStatement evaluation](https://tc39.es/ecma262/multipage/ecmascript-language-statements-and-declarations.html#sec-try-statement-runtime-semantics-evaluation).

Once lowering fixes branch destinations, it marks exits requiring handler unwind.
Ordinary Jump and Return instructions retain direct VM behavior. Crossing jumps
use LeaveHandler; crossing returns use ReturnThroughHandler. ResumeCompletion
continues a finalizer's saved jump, return, or throw.

A labeled exit may remove enumeration frames before reaching finally. The handler
retains the live enumeration objects while finally runs, because finally can
replace that exit with a continue. The pending jump records the enumeration depth
required by the selected continuation.

Catch receives a fresh environment. Unwinding restores the surrounding environment
and optional-chain state, and discards unfinished operand, binding-reference, and
argument resources. Internal errors and non-JavaScript aborts remain uncatchable
by guest catch clauses.

## Verification

The verifier checks region bounds, nesting, fixed handler exits, resume ownership,
and crossings between regions. Ordinary branches and returns cannot bypass
unwinding. Region entries and normal exits have no temporary operand, argument,
or binding-reference resources.

Conservative exception and finally-resumption edges supplement ordinary control
flow. Both observation snapshots and the independently owned immutable authority
record those edges. Exception entry uses the handler's saved resource shape;
pending jump destinations also retain their ordinary transfer checks.

Regression tests cover completion precedence, nested finally, catch shadowing,
closures, arguments and eval preparation, labeled enumeration cleanup, and iterator
cleanup with competing exceptions. Separate negative tests check malformed region
boundaries and missing exception observation edges. Direct bytecode execution and
candidate route assertions prevent Tree fallback from masking missing support.

## Remaining scope

Existing compiler and activation restrictions still apply, including destructured
catch parameters, block lexical declarations, for-of, suspended function families,
and some for-in forms. Public API signatures are unchanged. General completion
handling is a foundation for expanding bytecode coverage; it does not establish
full JavaScript coverage or a performance guarantee.
