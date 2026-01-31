# js_engine

A minimal JavaScript tree-walking interpreter written in [MoonBit](https://www.moonbitlang.com/).

## Features

- Numeric literals (IEEE 754 doubles), strings, booleans, `null`, `undefined`
- Variable declarations: `let`, `const`, `var`
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `<`, `>`, `<=`, `>=`
- Equality: `==`, `===`, `!=`, `!==`
- Logical: `&&`, `||`, `!`
- Control flow: `if`/`else`, `while`, `for`, `break`, `continue`, `return`
- Functions: declarations, expressions, closures, recursion
- Ternary operator: `? :`
- `typeof` operator
- `console.log()` output
- String concatenation (including mixed types)
- Single-line (`//`) and multi-line (`/* */`) comments

## Package Structure

```
token/          Token types and source locations
lexer/          Tokenizer
ast/            AST node definitions
parser/         Recursive descent parser with Pratt precedence
interpreter/    Tree-walking evaluator with closures and scope chains
cmd/main/       CLI entry point
```

## Usage

### CLI

```sh
moon run cmd/main -- 'console.log(1 + 2)'
# 3
```

```sh
moon run cmd/main -- '
function fib(n) {
  if (n <= 1) { return n; }
  return fib(n - 1) + fib(n - 2);
}
console.log(fib(10));
'
# 55
```

### As a Library

```moonbit
let (output, result) = @js_engine.run("console.log(1 + 2)")
// output = ["3"], result = "undefined"
```

## Development

```sh
moon check        # Type check
moon fmt          # Format code
moon info         # Update .mbti interface files
moon test         # Run tests
moon test --update # Update snapshot tests
moon build        # Build
```

## License

Apache-2.0
