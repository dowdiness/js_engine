# Candidate execution routing

Candidate execution is an opt-in build-time mode for the stable engine
facade. The default build keeps the existing tree-walking path: it does not
prepare, lower, or allocate candidate execution data. A build that replaces
the virtual policy implementation enables candidate preparation once at the
start of each evaluation.

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
Mixed trees are therefore expected: a bytecode parent can own a tree-walking
child, and a tree-walking parent can own a bytecode child.

Candidate mode does not change the public engine API, the default executor,
or the set of JavaScript operations supported by the interpreter. It is an
execution-routing boundary only; unsupported lowering or activation is
decided before the selected activation begins.
