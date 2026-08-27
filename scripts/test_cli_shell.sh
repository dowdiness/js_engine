#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

printf '%s\n' 'console.log(40 + 2);' >"$fixture_root/main.js"

cd "$repo_root"
moon build --target native cmd/main

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/main.js")"
if [[ "$actual" != "42" ]]; then
  printf 'expected file execution to print 42, got:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' 'console.log(arguments.join("|"));' >"$fixture_root/arguments.js"

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/arguments.js" -- alpha --beta)"
if [[ "$actual" != "alpha|--beta" ]]; then
  printf 'expected script arguments, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/arguments.js" -- --fixture x y)"
if [[ "$actual" != "--fixture|x|y" ]]; then
  printf 'expected -- to end all shell option parsing, got:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' 'function add(a, b) { return a + b; }' >"$fixture_root/lib.js"
printf '%s\n' 'load("./lib.js"); console.log(add(20, 22));' >"$fixture_root/load_main.js"

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/load_main.js")"
if [[ "$actual" != "42" ]]; then
  printf 'expected load() to evaluate relative to the loading script, got:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' 'payload' >"$fixture_root/data.txt"
printf '%s\n' \
  'console.log(read("./data.txt").trim());' \
  'console.log(scriptArgs.length, scriptArgs[1]);' \
  'let before = performance.now();' \
  'let after = performance.now();' \
  'performance.mark("sample");' \
  'performance.measure("sample", "sample");' \
  'console.log(typeof before, after >= before, typeof performance.mark, typeof performance.measure);' \
  >"$fixture_root/host_api.js"

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/host_api.js" -- alpha)"
expected=$'payload\n2 alpha\nnumber true function function'
if [[ "$actual" != "$expected" ]]; then
  printf 'expected read(), scriptArgs, and monotonic performance.now(), got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'console.log(arguments.join("|"));' -- alpha --beta)"
if [[ "$actual" != "alpha|--beta" ]]; then
  printf 'expected -- to pass arguments in eval mode, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'print(globalThis.arguments === arguments, globalThis.scriptArgs === scriptArgs);' -- alpha)"
if [[ "$actual" != "true true" ]]; then
  printf 'expected argument arrays to be global object properties, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe --module -e 'console.log(typeof load, typeof read, typeof readFile, typeof runString, typeof performance, typeof arguments === "undefined" ? "missing" : arguments.join("|"), typeof scriptArgs === "undefined" ? "missing" : scriptArgs.join("|"));' -- alpha)"
if [[ "$actual" != "function function function function object alpha -e|alpha" ]]; then
  printf 'expected module execution to use the general Shell host, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'print("arguments" in globalThis, "scriptArgs" in globalThis);')"
if [[ "$actual" != "false false" ]]; then
  printf 'expected argument globals to be absent without eval arguments, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'console.assert(true); print("ok");')"
if [[ "$actual" != "ok" ]]; then
  printf 'expected a successful console.assert() to be silent, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'function earlierFallback() { try { return 1; } catch (_) { return 0; } } function* value() { return 42; } let iterator = value(); print(iterator.next().value, iterator.next().done);')"
if [[ "$actual" != "42 true" ]]; then
  printf 'expected bytecode-default CLI to preserve generator semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let iterator = (function* () { return 42; })(); print(iterator.next().value);')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve generator expression semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let factorial = function self(value) { return value === 1 ? 1 : self(value - 1) * value; }; print(factorial(3));')"
if [[ "$actual" != "6" ]]; then
  printf 'expected bytecode-default CLI to preserve named function expression self-binding, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'async function value() { return 42; } value().then(result => print(result));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async function semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let value = async function () { return 42; }; value().then(result => print(result));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async function expression semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let value = async () => 42; value().then(result => print(result));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async arrow semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'async function* value() { return 42; } value().next().then(result => print(result.value));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async generator semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let value = async function* () { return 42; }; value().next().then(result => print(result.value));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async generator expression semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let holder = { *value() { return 42; } }; print(holder.value().next().value);')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve generator method semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let holder = { async value() { return 42; } }; holder.value().then(result => print(result));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async method semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let holder = { async *value() { return 42; } }; holder.value().next().then(result => print(result.value));')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI to preserve async generator method semantics, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'function outer() { var value = 42; function inner(input) { try { throw input; } catch (_) { return value; } } return inner(null); } print(outer());')"
if [[ "$actual" != "42" ]]; then
  printf 'expected bytecode-default CLI fallback to preserve captured bindings, got:\n%s\n' "$actual" >&2
  exit 1
fi

actual="$(_build/native/debug/build/cmd/main/main.exe -e 'let g = runString("globalThis.answer = 41"); print(g !== globalThis, g.answer); g.loadString("globalThis.answer += 1"); print(g.answer);')"
if [[ "$actual" != $'true 41\n42' ]]; then
  printf 'expected runString() to create and retain an isolated realm, got:\n%s\n' "$actual" >&2
  exit 1
fi

printf '\001\002\377' >"$fixture_root/data.bin"
printf '%s\n' \
  'let bytes = new Uint8Array(read("./data.bin", "binary"));' \
  'console.log(bytes.length, bytes[0], bytes[2]);' \
  >"$fixture_root/binary.js"

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/binary.js")"
if [[ "$actual" != "3 1 255" ]]; then
  printf 'expected binary read() to return an ArrayBuffer, got:\n%s\n' "$actual" >&2
  exit 1
fi

mkdir -p "$fixture_root/sub"
printf '%s\n' 'load("../two.js");' >"$fixture_root/sub/one.js"
printf '%s\n' 'globalThis.nestedValue = 42;' >"$fixture_root/two.js"
printf '%s\n' 'load("./sub/one.js"); console.log(nestedValue);' >"$fixture_root/nested.js"

actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/nested.js")"
if [[ "$actual" != "42" ]]; then
  printf 'expected nested load() to follow each referrer, got:\n%s\n' "$actual" >&2
  exit 1
fi

if actual="$(_build/native/debug/build/cmd/main/main.exe -e 'throw new TypeError("boom");' 2>&1)"; then
  printf 'expected an uncaught JavaScript exception to fail the process\n' >&2
  exit 1
fi
if [[ "$actual" != "TypeError: boom" ]]; then
  printf 'expected a shell-style uncaught exception, got:\n%s\n' "$actual" >&2
  exit 1
fi

if actual="$(_build/native/debug/build/cmd/main/main.exe -e 'console.log("before"); throw new TypeError("after output");' 2>&1)"; then
  printf 'expected the script with output and an exception to fail\n' >&2
  exit 1
fi
expected=$'before\nTypeError: after output'
if [[ "$actual" != "$expected" ]]; then
  printf 'expected output emitted before an exception to be preserved, got:\n%s\n' "$actual" >&2
  exit 1
fi

printf '%s\n' 'throw new TypeError("loaded boom");' >"$fixture_root/throws.js"
printf '%s\n' 'load("./throws.js");' >"$fixture_root/load_throws.js"
if actual="$(_build/native/debug/build/cmd/main/main.exe "$fixture_root/load_throws.js" 2>&1)"; then
  printf 'expected an exception from load() to fail the process\n' >&2
  exit 1
fi
if [[ "$actual" != "TypeError: loaded boom" ]]; then
  printf 'expected load() to preserve the JavaScript exception, got:\n%s\n' "$actual" >&2
  exit 1
fi
