# Candidate execution routing

Candidate execution is the build-time default for the stable engine facade.
It prepares an execution candidate once at the start of each evaluation and
selects verified bytecode only for supported source. A replacement virtual
policy may disable candidate preparation and keep the existing tree-walking
path.

Preparation produces an immutable, verified program plan. Each function
activation keeps its own selected route and may start either bytecode or the
tree walker. A function value owns the capability and child plan it needs, so
functions created by an earlier evaluation remain valid after later
evaluations. Tree child materialization resolves the exact parser location and
consumer form stored in the request to the immutable child slot; it never
consumes children in runtime order or matches a name, signature, source
string, or AST body. A repeated evaluation of one site therefore reuses the
same verified candidate. Fresh direct-eval parses temporarily clear the
enclosing materializer and cannot consume its plan. Routing never uses a
mutable “current program” registry.

The private lifecycle is deliberately closed:

```text
prepared → start(bytecode | tree walker) → complete(normal | abrupt)
```

The selected route is checked against the prepared decision before start. A
started activation cannot be downgraded or replayed through another executor.
Mixed trees are deliberately asymmetric until captured binding storage is
executor-neutral. A tree-walking parent can own a bytecode child. If a child
requires the tree walker, its nearest bytecode-candidate parent also selects
the tree walker before activation, so a tree child never loses bindings held
in bytecode-local slots.

Function forms that the executor-neutral materialization contract cannot yet
represent, including generator and async functions, use a stricter boundary.
If any such form occurs in the prepared source unit, that evaluation runs on
the plain tree walker without installing a candidate materializer. This keeps
function kind, constructor identity, parameter initialization, and nested
function creation under one established semantic owner. Fully supported
source continues to use verified bytecode by default.

Candidate mode does not change the public engine API, the default executor,
or the set of JavaScript operations supported by the interpreter. It is an
execution-routing boundary only; unsupported lowering or activation is
decided before the selected activation begins.
