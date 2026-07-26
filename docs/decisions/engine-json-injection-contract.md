# Stable Engine host-owned JSON injection contract

Date: 2026-07-26

## Status

Accepted for implementation by the root facade.

## Context

An embedder needs to provide trusted scripts with host-owned configuration and
plain input data before executable host callbacks are exposed. The existing
strict JSON bridge already copies `Json` into a realm without consulting the
realm's mutable `JSON` object or invoking JavaScript code.

Injection must preserve that non-executing boundary. It must also avoid
creating two independently mutable views of the same host value or silently
replacing a script-owned global.

## Decision

Add one stable root-facade operation:

```moonbit nocheck
pub fn Engine::inject_json(
  Self,
  name : String,
  value : Json,
) -> Result[Unit, EngineDiagnostic]
```

The operation copies `value` into the Engine's realm and publishes the copy as
both:

- an initialized immutable global lexical binding; and
- an own data property of `globalThis`.

The property is non-writable, enumerable, and non-configurable. The binding and
property therefore expose the same immutable realm-owned value through both
identifier lookup and `globalThis[name]` without allowing script-side
replacement.

## Collision and lifecycle policy

Injection succeeds only when all of the following are true:

- the global environment has no binding named `name`;
- `globalThis` has no own property named `name`; and
- the global object is extensible.

Any existing binding or own property is a collision, including a value created
by an earlier injection. Injection never overwrites, updates, or redefines a
name. A future host-update API requires a separate compatibility decision.

Inherited global-object properties do not collide. The new own property may
shadow one because no inherited object is mutated.

`name` is an opaque property-key string. Strings that are not JavaScript
identifiers remain usable through `globalThis[name]`, although they cannot be
written as bare identifier syntax.

Separate Engines receive separate recursive copies. Later mutation of the
MoonBit `Json` input or of one Engine's injected objects does not affect another
Engine.

## Non-executing and failure contract

The operation:

- uses the direct JSON-to-realm bridge;
- does not call `JSON.parse`, `JSON.stringify`, getters, setters, Proxy traps,
  or `toJSON`;
- does not run microtasks or timers; and
- does not roll back or alter jobs that were already pending.

Conversion is completed before either global view is installed. Collision and
global-extensibility checks are also completed before installation. After
those checks, installation uses the Engine's ordinary global environment and
known ordinary global object without executing JavaScript.

Expected failures return a reusable `EngineDiagnostic` with no retained effects
and a snapshot of jobs that were already pending:

| Failure | kind | operation | phase |
|---|---|---|---|
| Invalid JSON number or recursive conversion failure | `json-conversion-error` | `inject-json` | `conversion` |
| Existing binding/property or non-extensible global object | `injection-conflict` | `inject-json` | `define` |

Unexpected runtime failures use `internal-error`, report Engine integrity as
`discard`, and leave retained effects and pending jobs unknown. The operation
does not add a variant to `EngineError`; failure kinds remain the existing open
string vocabulary on `EngineDiagnostic`.

## Compatibility consequences

This is an additive root-facade API. Existing `EngineError` variants, existing
operation signatures, raw runtime representations, and generated interfaces of
the interpreter packages remain unchanged.

The new root interface entry is intentional. External consumers can inject and
observe JSON without importing `Interpreter` or runtime `Value`.
