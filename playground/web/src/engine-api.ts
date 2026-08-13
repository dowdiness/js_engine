import {
  type Completion,
  type CompletionContext,
  type CompletionResult,
} from "@codemirror/autocomplete";
import { completionPath } from "@codemirror/lang-javascript";

type EngineApiPath = readonly string[];

export type EngineApiEntry = Completion & {
  path: EngineApiPath;
  documentation: string;
};

const engineSection = { name: "js_engine", rank: 0 };

type EntrySpec = {
  label: string;
  type: string;
  detail: string;
  documentation: string;
};

function makeEntries(
  path: EngineApiPath,
  specs: readonly EntrySpec[],
): readonly EngineApiEntry[] {
  return specs.map(spec => ({ ...spec, path, section: engineSection }));
}

// Mirrors the realm globals installed by interpreter/runtime/interpreter.mbt.
const installedGlobalEntries = makeEntries([], [
  {
    label: "globalThis",
    type: "variable",
    detail: "current realm",
    documentation: "The global object for the current fresh js_engine realm.",
  },
  {
    label: "undefined",
    type: "constant",
    detail: "undefined value",
    documentation: "The primitive value used for an uninitialized or absent result.",
  },
  {
    label: "NaN",
    type: "constant",
    detail: "not-a-number value",
    documentation: "The numeric value representing an unrepresentable result.",
  },
  {
    label: "Infinity",
    type: "constant",
    detail: "infinite number",
    documentation: "The numeric value representing positive or negative infinity.",
  },
  {
    label: "eval",
    type: "function",
    detail: "(source) => unknown",
    documentation: "Evaluates JavaScript source in the current realm.",
  },
  {
    label: "isFinite",
    type: "function",
    detail: "(value) => boolean",
    documentation: "Returns whether value coerces to a finite number.",
  },
  {
    label: "isNaN",
    type: "function",
    detail: "(value) => boolean",
    documentation: "Returns whether value coerces to NaN.",
  },
  {
    label: "parseInt",
    type: "function",
    detail: "(string, radix?) => number",
    documentation: "Parses a string as an integer in the supplied radix.",
  },
  {
    label: "parseFloat",
    type: "function",
    detail: "(string) => number",
    documentation: "Parses a string as a floating-point number.",
  },
  {
    label: "encodeURIComponent",
    type: "function",
    detail: "(component) => string",
    documentation: "Encodes a URI component.",
  },
  {
    label: "decodeURIComponent",
    type: "function",
    detail: "(encodedComponent) => string",
    documentation: "Decodes an encoded URI component.",
  },
  {
    label: "encodeURI",
    type: "function",
    detail: "(uri) => string",
    documentation: "Encodes a complete URI while preserving URI syntax.",
  },
  {
    label: "decodeURI",
    type: "function",
    detail: "(encodedURI) => string",
    documentation: "Decodes an encoded URI.",
  },
  {
    label: "escape",
    type: "function",
    detail: "(string) => string",
    documentation: "Returns the legacy escaped representation of a string.",
  },
  {
    label: "unescape",
    type: "function",
    detail: "(string) => string",
    documentation: "Decodes a legacy escaped string.",
  },
  {
    label: "String",
    type: "class",
    detail: "string constructor",
    documentation: "Creates strings or converts values to strings.",
  },
  {
    label: "Number",
    type: "class",
    detail: "number constructor",
    documentation: "Creates numbers or converts values to numbers.",
  },
  {
    label: "Boolean",
    type: "class",
    detail: "boolean constructor",
    documentation: "Converts a value to a boolean.",
  },
  {
    label: "Object",
    type: "class",
    detail: "object constructor",
    documentation: "Creates objects and provides object utility methods.",
  },
  {
    label: "Array",
    type: "class",
    detail: "array constructor",
    documentation: "Creates arrays and provides array utility methods.",
  },
  {
    label: "Function",
    type: "class",
    detail: "function constructor",
    documentation: "Creates function objects.",
  },
  {
    label: "RegExp",
    type: "class",
    detail: "regular expression",
    documentation: "Creates a regular expression object.",
  },
  {
    label: "Error",
    type: "class",
    detail: "error constructor",
    documentation: "Creates an Error object.",
  },
  {
    label: "TypeError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates a TypeError object.",
  },
  {
    label: "RangeError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates a RangeError object.",
  },
  {
    label: "ReferenceError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates a ReferenceError object.",
  },
  {
    label: "SyntaxError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates a SyntaxError object.",
  },
  {
    label: "URIError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates a URIError object.",
  },
  {
    label: "EvalError",
    type: "class",
    detail: "error constructor",
    documentation: "Creates an EvalError object.",
  },
  {
    label: "Date",
    type: "class",
    detail: "date constructor",
    documentation: "Creates Date objects.",
  },
  {
    label: "Math",
    type: "variable",
    detail: "math methods",
    documentation: "Provides mathematical constants and functions.",
  },
  {
    label: "JSON",
    type: "variable",
    detail: "serialization methods",
    documentation: "Provides JSON parsing and serialization methods.",
  },
  {
    label: "Symbol",
    type: "class",
    detail: "symbol constructor",
    documentation: "Creates unique Symbol values.",
  },
  {
    label: "Map",
    type: "class",
    detail: "key/value collection",
    documentation: "Creates an ordered key/value collection.",
  },
  {
    label: "Set",
    type: "class",
    detail: "value collection",
    documentation: "Creates a collection of unique values.",
  },
  {
    label: "WeakMap",
    type: "class",
    detail: "weak key/value collection",
    documentation: "Creates a key/value collection with weakly held object keys.",
  },
  {
    label: "WeakSet",
    type: "class",
    detail: "weak value collection",
    documentation: "Creates a collection with weakly held object values.",
  },
  {
    label: "Promise",
    type: "class",
    detail: "microtasks",
    documentation:
      "Promise implementation whose reactions run during the engine microtask checkpoints.",
  },
  {
    label: "Proxy",
    type: "class",
    detail: "object interception",
    documentation: "Creates an object that intercepts operations with handler traps.",
  },
  {
    label: "Reflect",
    type: "variable",
    detail: "reflection methods",
    documentation: "Provides the engine's reflective object operations.",
  },
  {
    label: "ArrayBuffer",
    type: "class",
    detail: "binary buffer",
    documentation: "Creates a fixed-length raw binary data buffer.",
  },
  {
    label: "DataView",
    type: "class",
    detail: "binary view",
    documentation: "Provides typed access to an ArrayBuffer.",
  },
  {
    label: "Int8Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of signed 8-bit integers.",
  },
  {
    label: "Uint8Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of unsigned 8-bit integers.",
  },
  {
    label: "Uint8ClampedArray",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of clamped unsigned 8-bit integers.",
  },
  {
    label: "Int16Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of signed 16-bit integers.",
  },
  {
    label: "Uint16Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of unsigned 16-bit integers.",
  },
  {
    label: "Int32Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of signed 32-bit integers.",
  },
  {
    label: "Uint32Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of unsigned 32-bit integers.",
  },
  {
    label: "Float32Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of 32-bit floating-point values.",
  },
  {
    label: "Float64Array",
    type: "class",
    detail: "typed array",
    documentation: "Creates an array of 64-bit floating-point values.",
  },
  {
    label: "BigInt64Array",
    type: "class",
    detail: "typed array · shape only",
    documentation:
      "Creates a shape-only BigInt64Array; BigInt element semantics are unsupported.",
  },
  {
    label: "BigUint64Array",
    type: "class",
    detail: "typed array · shape only",
    documentation:
      "Creates a shape-only BigUint64Array; BigInt element semantics are unsupported.",
  },
]);

const hostGlobalEntries = makeEntries([], [
  {
    label: "console",
    type: "variable",
    detail: "host output",
    documentation:
      "The js_engine host output object. Only console.log is supported.",
  },
  {
    label: "queueMicrotask",
    type: "function",
    detail: "(callback) => undefined",
    documentation:
      "Queues a callback for the next js_engine microtask checkpoint.",
  },
  {
    label: "setTimeout",
    type: "function",
    detail: "timer · (callback, delay?, ...args) => number",
    documentation:
      "Schedules a timer callback in the fresh js_engine realm.",
  },
  {
    label: "clearTimeout",
    type: "function",
    detail: "(handle) => undefined",
    documentation: "Cancels a timer scheduled by setTimeout.",
  },
  {
    label: "setInterval",
    type: "function",
    detail: "timer · (callback, delay?, ...args) => number",
    documentation:
      "Schedules a repeating timer callback. The playground drains bounded timer work.",
  },
  {
    label: "clearInterval",
    type: "function",
    detail: "(handle) => undefined",
    documentation: "Cancels a timer scheduled by setInterval.",
  },
]);

const memberEntries = [
  ...makeEntries(["console"], [
    {
      label: "log",
      type: "method",
      detail: "(...values) => undefined",
      documentation: "Writes values to the Playground Console output.",
    },
  ]),
  ...makeEntries(["Promise"], [
    {
      label: "resolve",
      type: "method",
      detail: "(value) => Promise",
      documentation: "Returns a fulfilled Promise for value.",
    },
    {
      label: "reject",
      type: "method",
      detail: "(reason) => Promise",
      documentation: "Returns a rejected Promise for reason.",
    },
    {
      label: "all",
      type: "method",
      detail: "(iterable) => Promise",
      documentation: "Returns a Promise fulfilled when all input Promises fulfill.",
    },
    {
      label: "race",
      type: "method",
      detail: "(iterable) => Promise",
      documentation: "Returns a Promise settled by the first input Promise to settle.",
    },
  ]),
  ...makeEntries(["Reflect"], [
    {
      label: "get",
      type: "method",
      detail: "(target, propertyKey, receiver?) => unknown",
      documentation: "Reads a property using the reflective get operation.",
    },
    {
      label: "set",
      type: "method",
      detail: "(target, propertyKey, value, receiver?) => boolean",
      documentation: "Writes a property using the reflective set operation.",
    },
    {
      label: "ownKeys",
      type: "method",
      detail: "(target) => (string | symbol)[]",
      documentation: "Returns the target's own property keys.",
    },
  ]),
  ...makeEntries(["JSON"], [
    {
      label: "parse",
      type: "method",
      detail: "(text, reviver?) => unknown",
      documentation: "Parses JSON text into a JavaScript value.",
    },
    {
      label: "stringify",
      type: "method",
      detail: "(value, replacer?, space?) => string | undefined",
      documentation: "Serializes a JavaScript value as JSON text.",
    },
  ]),
] as const;

export const engineApiEntries: readonly EngineApiEntry[] = [
  ...installedGlobalEntries,
  ...hostGlobalEntries,
  ...memberEntries,
];

const completionCache = new Map<string, readonly Completion[]>();
const identifier = /^[\w$]*$/;

function pathKey(path: EngineApiPath): string {
  return path.join(".");
}

function asCompletion(entry: EngineApiEntry): Completion {
  const { path: _path, documentation, ...completion } = entry;
  return { ...completion, info: documentation };
}

export function completionsForPath(path: EngineApiPath): readonly Completion[] {
  const key = pathKey(path);
  const cached = completionCache.get(key);
  if (cached) return cached;
  const completions = engineApiEntries
    .filter(entry => pathKey(entry.path) === key)
    .map(asCompletion);
  completionCache.set(key, completions);
  return completions;
}

export function engineCompletionSource(
  context: CompletionContext,
): CompletionResult | null {
  const path = completionPath(context);
  if (!path) return null;
  const options = completionsForPath(path.path);
  if (options.length === 0) return null;
  return {
    from: context.pos - path.name.length,
    options,
    validFor: identifier,
  };
}


export function findEngineApiEntryByLabel(
  path: EngineApiPath,
  label: string,
): EngineApiEntry | undefined {
  const key = pathKey(path);
  return engineApiEntries.find(
    entry => pathKey(entry.path) === key && entry.label === label,
  );
}
