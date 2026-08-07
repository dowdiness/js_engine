# Diago Feature Restoration

This context defines the language used to decide whether the Current Release of
Diago may practically restore a previously unsupported feature.

## Language

**Diago Restoration Readiness**:
A one-time js_engine repository decision that the Current Release is practical
for Diago to evaluate with restored LaTeX and sketch features. The decision
covers every official target and profile and requires representative former
Diago workloads to behave correctly through js_engine's public interface without
an observed crash, hang, or host-stack overflow; it neither changes Diago nor
proves General Stack Safety.
_Avoid_: Diago Restoration Acceptance, Diago Product Guarantee, Issue #24 closure

**Current Release**:
The single Diago revision, js_engine revision, toolchain, and embedded
MathJax/Rough.js assets being evaluated for restoration now.
_Avoid_: Supported version range, forward compatibility

**General Stack Safety**:
Host-stack independence work defined by JavaScript execution semantics and
engine invariants, without special treatment for Diago, MathJax, or Rough.js.
_Avoid_: Diago hardening, bundle-specific stack safety

**Practical Evidence**:
Representative executable evidence sufficient for Diago Restoration Readiness,
without exhaustive path enumeration or a proof that every JavaScript execution
is host-stack independent.
_Avoid_: Formal proof, exhaustive bundle certification

**Pinned Diago Workload**:
A checked-in, hash-identified copy of the pre-removal MathJax or Rough.js source
and its minimal execution adapter, exercised only through js_engine's root public
interface. It has no runtime network dependency and does not execute a Diago
library, CLI, or Wasm ABI.
_Avoid_: Diago integration test, live upstream dependency

**General Operation Slice**:
The smallest JavaScript-semantics-defined execution family whose current
behavior prevents a Pinned Diago Workload from completing. A restoration fix
may deepen the existing execution module for this family, but must not recognize
Diago, a bundle identity, or a bundle-specific source shape.
_Avoid_: Bundle-specific admission, Diago fast path, big-bang stack-safety rewrite

**Readiness Check**:
A reproducible, target-and-profile-specific execution of the Pinned Diago
Workloads for the exact Current Release. Its fixture and command remain in the
repository, but it is not a required gate for future pull requests.
_Avoid_: Permanent stack-safety gate, forward-compatibility certification

**Diago Harness Adapter**:
A test-only local adapter that replaces Diago parsing, layout, and final SVG
assembly while preserving the pre-removal engine invocation sequence, real
MathJax/Rough.js source, checkpoints, and representative inputs. It observes
real engine results and must not return canned LaTeX metrics or drawing output.
_Avoid_: Diago mock, Diago emulator, Diago integration adapter

**Readiness Oracle**:
The minimal observable result used by the Readiness Check: MathJax must produce
real math SVG and the historical simple-formula dimensions, the former complex
formula inputs must produce real SVG with positive finite dimensions, and
Rough.js must produce multiple real drawing paths. Diago layout coordinates,
final SVG assembly, and D2 input diagnostics are outside this oracle.
_Avoid_: Full SVG snapshot, Diago layout equivalence, canned success value

**Readiness Failure**:
Any target/profile attempt that does not produce the Readiness Oracle within its
fixed execution bound, including a crash, hang, or ordinary test failure. A
retry does not convert a failed attempt into readiness evidence.
_Avoid_: Flaky pass, retry-qualified success, partial matrix success

**Restoration-Compatible Change**:
A private deepening of the existing execution module for a General Operation
Slice that leaves the root interface, dependencies, executor selection, and
JavaScript behavior unchanged. It does not make bytecode mandatory or expose
tree-walker-specific execution types to bytecode.
_Avoid_: Public restoration interface, executor switch, shared recipe VM
