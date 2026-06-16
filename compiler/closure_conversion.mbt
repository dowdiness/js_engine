// Closure-conversion execution path — legacy experimental.
//
// This file implements an opt-in closure-conversion prototype. It is retained
// as a benchmark comparison path and research artifact, not as the long-term
// optimization architecture. See docs/architecture-execution-plan-2026-06-12.md
// §8 (Closure-Conversion Policy) for the retirement criteria and the list of
// allowed and forbidden work.
//
// Do not add new syntax coverage or new semantic special cases here unless the
// change is required to keep existing benchmark comparisons meaningful or to
// retire this path.

///|
using @runtime {
  type BindingKind,
  type Callable,
  type Environment,
  type ExecContext,
  type FuncDataExt,
  type Interpreter,
  type ObjectData,
  type PropDescriptor,
  type PropertyBag,
  type ProxyData,
  type Signal,
  type Value,
}

///|
priv enum CompiledArg {
  Plain((Interpreter, ExecContext, Environment) -> Value raise Error)
  Spread(
    (Interpreter, ExecContext, Environment) -> Value raise Error,
    @token.Loc
  )
}

///|
priv struct CompiledBody(
  (Interpreter, ExecContext, Environment) -> Signal raise Error
)

///|
priv enum CompiledObjectProp {
  StaticData(
    String,
    (Interpreter, ExecContext, Environment) -> Value raise Error
  )
  ComputedData(
    (Interpreter, ExecContext, Environment) -> Value raise Error,
    (Interpreter, ExecContext, Environment) -> Value raise Error
  )
}

///|
/// Compile a supported expression into a MoonBit closure that evaluates that
/// expression against an interpreter, execution context, and lexical
/// environment.
///
/// The current tree-walking interpreter matches on `@ast.Expr` every time an
/// expression runs. This prototype performs that match once at compile time and
/// stores the chosen behavior in a closure, so hot execution paths invoke
/// already-selected code directly. The `ExecContext` is retained as an explicit
/// input so direct eval and strict function validation can preserve the caller's
/// strictness. Function expressions still capture the `Environment` passed to
/// the returned closure, matching `FuncData.closure` in the normal interpreter
/// path.
///
/// Limitations: this is a prototype for benchmark exploration. It supports the
/// statement and expression subset needed by the closure-factory workloads, but
/// it intentionally does not compile classes, generators, async functions,
/// destructuring, object-literal accessors/spread, or the full ECMAScript
/// hoisting surface yet.
pub fn compile_expr_to_closure(
  expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled = compile_expr_to_closure_inner(expr)
  fn(interp, ctx, env) raise {
    env.realm_state = Some(interp.realm_state)
    env.interpreter_context = Some(interp)
    interp.with_active_value(fn() raise { compiled(interp, ctx, env) })
  }
}

///|
fn compile_expr_to_closure_inner(
  expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match expr {
    NumberLit(n, _, _) => fn(_, _, _) { Value::Number(n) }
    StringLit(s, _, _, _) => fn(_, _, _) { Value::String_(s) }
    BoolLit(b, _) => fn(_, _, _) { Value::Bool(b) }
    NullLit(_) => fn(_, _, _) { Value::Null }
    UndefinedLit(_) => fn(_, _, _) { Value::Undefined }
    Ident(name, _) => compile_ident(name)
    ThisExpr(_) => compile_this()
    ObjectLit(props, _) => compile_object_lit(props)
    ArrayLit(elements, _) => compile_array_lit(elements)
    Assign(name, value_expr, _) => compile_assign(name, value_expr)
    MemberAssign(obj, prop, value, loc) =>
      compile_member_assign(obj, prop, value, loc)
    ComputedAssign(obj, key, value, loc) =>
      compile_computed_assign(obj, key, value, loc)
    CompoundAssign(op, target, value, loc) =>
      compile_compound_assign(op, target, value, loc)
    Grouping(inner, _) => compile_expr_to_closure_inner(inner)
    Unary(op, operand, loc) => compile_unary(op, operand, loc)
    Binary(op, left, right, loc) => {
      let left_fn = compile_expr_to_closure_inner(left)
      let right_fn = compile_expr_to_closure_inner(right)
      fn(interp, ctx, env) raise {
        eval_compiled_binary(interp, ctx, env, op, left_fn, right_fn, loc)
      }
    }
    Ternary(cond, then_expr, else_expr, _) =>
      compile_ternary(cond, then_expr, else_expr)
    FuncExpr(name, params, body, _) => compile_func_expr(name, params, body)
    FuncExprExt(name, params, rest_param, body, _) =>
      compile_func_expr_ext(name, params, rest_param, body)
    ArrowFunc(params, body, _) => compile_arrow_func(params, body)
    ArrowFuncExt(params, rest_param, body, _) =>
      compile_arrow_func_ext(params, rest_param, body)
    Call(callee, args, loc) => compile_call(callee, args, loc)
    Member(Ident("console", _), prop, loc) =>
      fn(interp, _, _) raise { compiled_console_member(interp, prop, loc) }
    Member(obj, prop, loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj)
      fn(interp, ctx, env) raise {
        interp.get_property(obj_fn(interp, ctx, env), prop, loc)
      }
    }
    ComputedMember(obj, key, loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj)
      let key_fn = compile_expr_to_closure_inner(key)
      fn(interp, ctx, env) raise {
        interp.get_computed_property(
          obj_fn(interp, ctx, env),
          key_fn(interp, ctx, env),
          loc,
        )
      }
    }
    NewExpr(callee, args, loc) => compile_new(callee, args, loc)
    UpdateExpr(op, operand, prefix, loc) =>
      compile_update(op, operand, prefix, loc)
    Comma(left, right, _) => compile_comma(left, right)
    _ => unsupported_expr("expression kind")
  }
}

///|
/// Compile a statement list into a reusable program closure.
///
/// This is intentionally opt-in for benchmarks. It does not replace
/// `Interpreter::run`; callers choose a prepared `Interpreter`, `ExecContext`,
/// and `Environment` so benchmark code can isolate parse, compile, and execute
/// costs explicitly.
pub fn compile_program_to_closure(
  stmts : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let body = compile_body(stmts)
  fn(interp, ctx, env) raise {
    env.realm_state = Some(interp.realm_state)
    env.interpreter_context = Some(interp)
    interp.with_active_value(fn() raise {
      reduce_program_signal((body.0)(interp, ctx, env))
    })
  }
}

///|
/// Compile a script into a closure that runs with the same outer execution
/// envelope as `Interpreter::run`.
///
/// This wrapper keeps declaration hoisting, directive-prologue strictness,
/// static early-error checks, current-interpreter setup, and JS error wrapping
/// in the runtime package. The compiled body still avoids repeated AST matches
/// for the supported statement/expression subset during execution.
pub fn compile_script_to_closure(
  stmts : Array[@ast.Stmt],
) -> (Interpreter) -> Value raise Error {
  let program = compile_program_to_closure(stmts)
  fn(interp) raise {
    interp.run_compiled_script(stmts, fn(ctx, env) raise {
      program(interp, ctx, env)
    })
  }
}

///|
fn compile_ident(
  name : String,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(interp, _ctx, env) raise {
    env.get(name) catch {
      @errors.ReferenceError(_) =>
        match interp.global_this {
          Value::Object(data) =>
            match data.bag.properties.get(name) {
              Some(v) => v
              None =>
                raise @errors.ReferenceError(message="\{name} is not defined")
            }
          _ => raise @errors.ReferenceError(message="\{name} is not defined")
        }
      other => raise other
    }
  }
}

///|
fn compile_this() -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, _, env) raise {
    env.get("this") catch {
      @errors.ReferenceError(message~) => {
        if message.contains("before initialization") {
          raise @errors.ReferenceError(
            message="Must call super constructor in derived class before accessing 'this' or returning from derived constructor",
          )
        }
        Value::Undefined
      }
      other => raise other
    }
  }
}

///|
fn compile_array_lit(
  elements : Array[@ast.Expr],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled : Array[
    (Interpreter, ExecContext, Environment) -> Value raise Error,
  ] = []
  for element in elements {
    match element {
      ArrayHole(_) => compiled.push(fn(_, _, _) { Value::Undefined })
      SpreadExpr(_, _) => return unsupported_expr("array spread")
      _ => compiled.push(compile_expr_to_closure_inner(element))
    }
  }
  fn(interp, ctx, env) raise {
    let values : Array[Value] = []
    for run in compiled {
      values.push(run(interp, ctx, env))
    }
    @runtime.make_array(values)
  }
}

///|
fn compile_object_lit(
  props : Array[@ast.Property],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled : Array[CompiledObjectProp] = []
  for prop in props {
    match prop.kind {
      Init =>
        if prop.computed {
          compiled.push(
            ComputedData(
              compile_expr_to_closure_inner(prop.key),
              compile_property_value(prop),
            ),
          )
        } else {
          compiled.push(
            StaticData(
              static_object_key(prop.key),
              compile_property_value(prop),
            ),
          )
        }
      Get | Set => return unsupported_expr("object literal accessor property")
      Spread => return unsupported_expr("object literal spread property")
    }
  }
  fn(interp, ctx, env) raise {
    let properties : Map[String, Value] = {}
    let symbol_properties : Map[Int, Value] = {}
    let descriptors : Map[String, PropDescriptor] = {}
    let symbol_descriptors : Map[Int, PropDescriptor] = {}
    let mut proto_override : Value? = None
    let default_obj_proto = env.get("[[ObjectPrototype]]") catch {
      _ => Value::Null
    }
    let bag : PropertyBag = {
      properties,
      symbol_properties,
      descriptors,
      symbol_descriptors,
      internal_slots: {},
    }
    let object_data : ObjectData = {
      bag,
      prototype: default_obj_proto,
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    }
    let home_object = Value::Object(object_data)
    let method_env = Environment::new(parent=Some(env))
    method_env.def_builtin("[[HomeObject]]", home_object)
    for prop in compiled {
      match prop {
        StaticData(key, value_fn) => {
          let value = value_fn(interp, ctx, method_env)
          if key == "__proto__" {
            match value {
              Value::Object(_)
              | Value::Array(_)
              | Value::Map(_)
              | Value::Set(_) => proto_override = Some(value)
              Value::Null => proto_override = Some(Value::Null)
              _ => properties[key] = value
            }
          } else {
            @runtime.set_function_name(value, key)
            properties[key] = value
          }
        }
        ComputedData(key_fn, value_fn) => {
          let key = @runtime.to_property_key(
            key_fn(interp, ctx, method_env),
            interp=Some(interp),
          )
          let value = value_fn(interp, ctx, method_env)
          match key {
            Value::Symbol(sym) => {
              let sym_name = match sym.description {
                Some(d) => "[\{d}]"
                None => ""
              }
              @runtime.set_function_name(value, sym_name)
              symbol_properties[sym.id] = value
            }
            Value::String_(key_str) => {
              @runtime.set_function_name(value, key_str)
              properties[key_str] = value
            }
            _ => abort("to_property_key returned non-property key")
          }
        }
      }
    }
    match proto_override {
      Some(proto) => object_data.prototype = proto
      None => ()
    }
    home_object
  }
}

///|
fn compile_property_value(
  prop : @ast.Property,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  if prop.is_method {
    match prop.value {
      FuncExpr(name, params, body, _) =>
        compile_func_expr_with_constructable(name, params, body, false)
      _ => compile_expr_to_closure_inner(prop.value)
    }
  } else {
    compile_expr_to_closure_inner(prop.value)
  }
}

///|
fn static_object_key(expr : @ast.Expr) -> String {
  match expr {
    StringLit(s, _, _, _) => s
    Ident(name, _) => name
    NumberLit(n, _, _) => {
      let i = n.to_int()
      if i.to_double() == n {
        i.to_string()
      } else {
        n.to_string()
      }
    }
    _ => ""
  }
}

///|
fn compile_assign(
  name : String,
  value_expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let value_fn = compile_expr_to_closure_inner(value_expr)
  fn(interp, ctx, env) raise {
    let value = value_fn(interp, ctx, env)
    env.assign(name, value) catch {
      @errors.ReferenceError(_) =>
        if ctx.strict {
          raise @errors.ReferenceError(message="\{name} is not defined")
        } else {
          interp.global.def(name, value, BindingKind::VarBinding)
        }
      other => raise other
    }
    value
  }
}

///|
fn compile_member_assign(
  obj_expr : @ast.Expr,
  prop : String,
  value_expr : @ast.Expr,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let obj_fn = compile_expr_to_closure_inner(obj_expr)
  let value_fn = compile_expr_to_closure_inner(value_expr)
  fn(interp, ctx, env) raise {
    let obj = obj_fn(interp, ctx, env)
    let value = value_fn(interp, ctx, env)
    interp.set_property(obj, prop, value, loc, strict=ctx.strict)
  }
}

///|
fn compile_computed_assign(
  obj_expr : @ast.Expr,
  key_expr : @ast.Expr,
  value_expr : @ast.Expr,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let obj_fn = compile_expr_to_closure_inner(obj_expr)
  let key_fn = compile_expr_to_closure_inner(key_expr)
  let value_fn = compile_expr_to_closure_inner(value_expr)
  fn(interp, ctx, env) raise {
    let obj = obj_fn(interp, ctx, env)
    let key = key_fn(interp, ctx, env)
    let value = value_fn(interp, ctx, env)
    interp.set_computed_property(obj, key, value, loc, strict=ctx.strict)
  }
}

///|
fn compile_unary(
  op : @ast.UnaryOp,
  operand : @ast.Expr,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match op {
    Delete => unsupported_expr("delete unary operator")
    Typeof =>
      match operand {
        Ident(name, _) =>
          fn(interp, _, env) raise {
            if env.has(name) {
              Value::String_(@runtime.type_of(env.get(name)))
            } else {
              match interp.global_this {
                Value::Object(data) =>
                  match data.bag.properties.get(name) {
                    Some(value) => Value::String_(@runtime.type_of(value))
                    None => Value::String_("undefined")
                  }
                _ => Value::String_("undefined")
              }
            }
          }
        _ => {
          let operand_fn = compile_expr_to_closure_inner(operand)
          fn(interp, ctx, env) raise {
            Value::String_(@runtime.type_of(operand_fn(interp, ctx, env)))
          }
        }
      }
    Void => {
      let operand_fn = compile_expr_to_closure_inner(operand)
      fn(interp, ctx, env) raise {
        let _ = operand_fn(interp, ctx, env)
        Value::Undefined
      }
    }
    Neg | Pos | Not | BitNot => {
      let operand_fn = compile_expr_to_closure_inner(operand)
      fn(interp, ctx, env) raise {
        let value = operand_fn(interp, ctx, env)
        match op {
          Neg => Value::Number(-@runtime.to_number(value, interp=Some(interp)))
          Pos => Value::Number(@runtime.to_number(value, interp=Some(interp)))
          Not => Value::Bool(!@runtime.is_truthy(value))
          BitNot =>
            Value::Number(
              @runtime.to_int32(@runtime.to_number(value, interp=Some(interp)))
              .lnot()
              .to_double(),
            )
          _ =>
            raise @errors.InternalError(
              message="Unexpected unary operator at line \{loc.line}, col \{loc.col}",
            )
        }
      }
    }
  }
}

///|
fn compile_compound_assign(
  op : @ast.CompoundOp,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match op {
    LogicalAndAssign | LogicalOrAssign | NullishAssign =>
      return compile_logical_assign(op, target, value_expr, loc)
    _ => ()
  }
  let bin_op = compound_op_to_bin_op(op)
  let value_fn = compile_expr_to_closure_inner(value_expr)
  match target {
    Ident(name, _) =>
      fn(interp, ctx, env) raise {
        let current = env.get(name)
        let rhs = value_fn(interp, ctx, env)
        let result = @runtime.eval_binary_op(
          bin_op,
          current,
          rhs,
          loc,
          interp=Some(interp),
        )
        env.assign(name, result)
        result
      }
    Member(obj_expr, prop, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let current = interp.get_property(obj, prop, member_loc)
        let rhs = value_fn(interp, ctx, env)
        let result = @runtime.eval_binary_op(
          bin_op,
          current,
          rhs,
          loc,
          interp=Some(interp),
        )
        let _ = interp.set_property(obj, prop, result, loc, strict=ctx.strict)
        result
      }
    }
    ComputedMember(obj_expr, key_expr, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      let key_fn = compile_expr_to_closure_inner(key_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let key = key_fn(interp, ctx, env)
        ensure_property_base(obj)
        let prop_key = @runtime.to_property_key(key, interp=Some(interp))
        let current = interp.get_computed_property(obj, prop_key, member_loc)
        let rhs = value_fn(interp, ctx, env)
        let result = @runtime.eval_binary_op(
          bin_op,
          current,
          rhs,
          loc,
          interp=Some(interp),
        )
        let _ = interp.set_computed_property(
          obj,
          prop_key,
          result,
          loc,
          strict=ctx.strict,
        )
        result
      }
    }
    _ => invalid_assignment_target(loc)
  }
}

///|
fn compile_logical_assign(
  op : @ast.CompoundOp,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let value_fn = compile_expr_to_closure_inner(value_expr)
  let should_assign = logical_assign_predicate(op)
  match target {
    Ident(name, _) =>
      fn(interp, ctx, env) raise {
        let current = env.get(name)
        if should_assign(current) {
          let rhs = value_fn(interp, ctx, env)
          env.assign(name, rhs)
          rhs
        } else {
          current
        }
      }
    Member(obj_expr, prop, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let current = interp.get_property(obj, prop, member_loc)
        if should_assign(current) {
          let rhs = value_fn(interp, ctx, env)
          interp.set_property(obj, prop, rhs, loc, strict=ctx.strict)
        } else {
          current
        }
      }
    }
    ComputedMember(obj_expr, key_expr, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      let key_fn = compile_expr_to_closure_inner(key_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let key = key_fn(interp, ctx, env)
        ensure_property_base(obj)
        let prop_key = @runtime.to_property_key(key, interp=Some(interp))
        let current = interp.get_computed_property(obj, prop_key, member_loc)
        if should_assign(current) {
          let rhs = value_fn(interp, ctx, env)
          interp.set_computed_property(
            obj,
            prop_key,
            rhs,
            loc,
            strict=ctx.strict,
          )
        } else {
          current
        }
      }
    }
    _ => invalid_assignment_target(loc)
  }
}

///|
fn compound_op_to_bin_op(op : @ast.CompoundOp) -> @ast.BinOp {
  match op {
    AddAssign => Add
    SubAssign => Sub
    MulAssign => Mul
    ExpAssign => Exp
    DivAssign => Div
    ModAssign => Mod
    BitAndAssign => BitAnd
    BitOrAssign => BitOr
    BitXorAssign => BitXor
    LShiftAssign => LShift
    RShiftAssign => RShift
    URShiftAssign => URShift
    LogicalAndAssign | LogicalOrAssign | NullishAssign => Add
  }
}

///|
fn logical_assign_predicate(op : @ast.CompoundOp) -> (Value) -> Bool {
  match op {
    LogicalAndAssign => value => @runtime.is_truthy(value)
    LogicalOrAssign => value => !@runtime.is_truthy(value)
    NullishAssign => value => value is Value::Null || value is Value::Undefined
    _ => _ => false
  }
}

///|
fn ensure_property_base(obj : Value) -> Unit raise Error {
  match obj {
    Value::Null =>
      raise @errors.TypeError(message="Cannot read properties of null")
    Value::Undefined =>
      raise @errors.TypeError(message="Cannot read properties of undefined")
    _ => ()
  }
}

///|
fn invalid_assignment_target(
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, _, _) raise {
    raise @errors.SyntaxError(
      message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
    )
  }
}

///|
fn compile_ternary(
  cond : @ast.Expr,
  then_expr : @ast.Expr,
  else_expr : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let cond_fn = compile_expr_to_closure_inner(cond)
  let then_fn = compile_expr_to_closure_inner(then_expr)
  let else_fn = compile_expr_to_closure_inner(else_expr)
  fn(interp, ctx, env) raise {
    if @runtime.is_truthy(cond_fn(interp, ctx, env)) {
      then_fn(interp, ctx, env)
    } else {
      else_fn(interp, ctx, env)
    }
  }
}

///|
fn compile_comma(
  left : @ast.Expr,
  right : @ast.Expr,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let left_fn = compile_expr_to_closure_inner(left)
  let right_fn = compile_expr_to_closure_inner(right)
  fn(interp, ctx, env) raise {
    let _ = left_fn(interp, ctx, env)
    right_fn(interp, ctx, env)
  }
}

///|
fn compile_update(
  op : @ast.UpdateOp,
  operand : @ast.Expr,
  prefix : Bool,
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  match operand {
    Ident(name, _) =>
      fn(interp, _, env) raise {
        let old = env.get(name)
        let old_num = @runtime.to_number(old, interp=Some(interp))
        let new_value = match op {
          Increment => Value::Number(old_num + 1.0)
          Decrement => Value::Number(old_num - 1.0)
        }
        env.assign(name, new_value)
        if prefix {
          new_value
        } else {
          Value::Number(old_num)
        }
      }
    Member(obj_expr, prop, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let old = interp.get_property(obj, prop, member_loc)
        let old_num = @runtime.to_number(old, interp=Some(interp))
        let new_value = match op {
          Increment => Value::Number(old_num + 1.0)
          Decrement => Value::Number(old_num - 1.0)
        }
        let _ = interp.set_property(
          obj,
          prop,
          new_value,
          loc,
          strict=ctx.strict,
        )
        if prefix {
          new_value
        } else {
          Value::Number(old_num)
        }
      }
    }
    ComputedMember(obj_expr, key_expr, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      let key_fn = compile_expr_to_closure_inner(key_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let key = key_fn(interp, ctx, env)
        let prop_key = @runtime.to_property_key(key, interp=Some(interp))
        let old = interp.get_computed_property(obj, prop_key, member_loc)
        let old_num = @runtime.to_number(old, interp=Some(interp))
        let new_value = match op {
          Increment => Value::Number(old_num + 1.0)
          Decrement => Value::Number(old_num - 1.0)
        }
        let _ = interp.set_computed_property(
          obj,
          prop_key,
          new_value,
          loc,
          strict=ctx.strict,
        )
        if prefix {
          new_value
        } else {
          Value::Number(old_num)
        }
      }
    }
    _ => unsupported_expr("update target")
  }
}

///|
fn compile_call(
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled_args = compile_args(args)
  match callee {
    Member(Ident("console", _), prop, member_loc) =>
      fn(interp, ctx, env) raise {
        let callee_value = compiled_console_member(interp, prop, member_loc)
        let values = eval_compiled_args(interp, ctx, env, compiled_args)
        interp.call_value(callee_value, Value::Undefined, values, loc)
      }
    Member(obj_expr, prop, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let callee_value = interp.get_property(obj, prop, member_loc)
        let values = eval_compiled_args(interp, ctx, env, compiled_args)
        interp.call_value(callee_value, obj, values, loc)
      }
    }
    ComputedMember(obj_expr, key_expr, member_loc) => {
      let obj_fn = compile_expr_to_closure_inner(obj_expr)
      let key_fn = compile_expr_to_closure_inner(key_expr)
      fn(interp, ctx, env) raise {
        let obj = obj_fn(interp, ctx, env)
        let key = key_fn(interp, ctx, env)
        let callee_value = interp.get_computed_property(obj, key, member_loc)
        let values = eval_compiled_args(interp, ctx, env, compiled_args)
        interp.call_value(callee_value, obj, values, loc)
      }
    }
    _ =>
      if is_direct_eval_callee(callee) {
        fn(interp, ctx, env) raise {
          eval_compiled_direct_eval(interp, ctx, env, compiled_args, loc)
        }
      } else {
        let callee_fn = compile_expr_to_closure_inner(callee)
        fn(interp, ctx, env) raise {
          let callee_value = callee_fn(interp, ctx, env)
          let values = eval_compiled_args(interp, ctx, env, compiled_args)
          interp.call_value(callee_value, Value::Undefined, values, loc)
        }
      }
  }
}

///|
fn compiled_console_member(
  interp : Interpreter,
  prop : String,
  _loc : @token.Loc,
) -> Value raise Error {
  if prop == "log" {
    let output = interp.host.output
    @runtime.make_native_func(
      name="log",
      realm_state=Some(interp.realm_state),
      fn(args) {
        let parts : Array[String] = args.map(fn(a) { a.to_string() })
        output.push(parts.join(" "))
        Value::Undefined
      },
    )
  } else {
    raise @errors.TypeError(message="console.\{prop} is not supported")
  }
}

///|
fn compile_new(
  callee : @ast.Expr,
  args : Array[@ast.Expr],
  loc : @token.Loc,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let callee_fn = compile_expr_to_closure_inner(callee)
  let compiled_args = compile_args(args)
  fn(interp, ctx, env) raise {
    let ctor = callee_fn(interp, ctx, env)
    let values = eval_compiled_args(interp, ctx, env, compiled_args)
    interp.construct_value(ctor, values, loc)
  }
}

///|
fn compile_func_expr(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  compile_func_expr_with_constructable(name, params, body, true)
}

///|
fn compile_func_expr_with_constructable(
  name : String?,
  params : Array[String],
  body : Array[@ast.Stmt],
  constructable : Bool,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled_body = compile_body(body)
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, name, params, body)
    make_compiled_func(
      name,
      params,
      env,
      ctx.strict || @static_semantics.has_use_strict(body),
      body=Some(compiled_body),
      constructable~,
    )
  }
}

///|
fn compile_func_expr_ext(
  name : String?,
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature_ext(
      ctx.strict,
      name,
      params,
      rest_param,
      body,
    )
    let func_data : FuncDataExt = {
      name,
      params,
      rest_param,
      body,
      closure: env,
      strict: ctx.strict || @static_semantics.has_use_strict(body),
      has_name_binding: name is Some(_),
      is_method: false,
    }
    @runtime.make_func_ext(func_data)
  }
}

///|
fn compile_arrow_func(
  params : Array[String],
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  let compiled_body = compile_body(body)
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature(ctx.strict, None, params, body)
    make_compiled_arrow_func(
      params,
      env,
      ctx.strict || @static_semantics.has_use_strict(body),
      compiled_body,
    )
  }
}

///|
fn compile_arrow_func_ext(
  params : Array[@ast.Param],
  rest_param : String?,
  body : Array[@ast.Stmt],
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, ctx, env) raise {
    @runtime.validate_function_signature_ext(
      ctx.strict,
      None,
      params,
      rest_param,
      body,
    )
    let func_data : FuncDataExt = {
      name: None,
      params,
      rest_param,
      body,
      closure: env,
      strict: ctx.strict || @static_semantics.has_use_strict(body),
      has_name_binding: false,
      is_method: false,
    }
    make_arrow_func_ext(func_data, arrow_ext_length(params))
  }
}

///|
fn compile_args(args : Array[@ast.Expr]) -> Array[CompiledArg] {
  let compiled : Array[CompiledArg] = []
  for arg in args {
    match arg {
      SpreadExpr(inner, loc) =>
        compiled.push(Spread(compile_expr_to_closure_inner(inner), loc))
      _ => compiled.push(Plain(compile_expr_to_closure_inner(arg)))
    }
  }
  compiled
}

///|
fn compile_body(stmts : Array[@ast.Stmt]) -> CompiledBody {
  let compiled : Array[
    (Interpreter, ExecContext, Environment) -> Signal raise Error,
  ] = []
  for stmt in stmts {
    compiled.push(compile_stmt(stmt))
  }
  CompiledBody(fn(interp, ctx, env) raise {
    let mut last = Value::Undefined
    for run in compiled {
      match run(interp, ctx, env) {
        Signal::Normal(value) => last = value
        sig => return sig
      }
    }
    Signal::Normal(last)
  })
}

///|
/// Return true only for statement shapes that cannot introduce block-scoped
/// bindings or require function-scoped `var` declaration handling in the
/// current compiled subset. Conservative false keeps the old block Environment
/// path for declarations and unsupported complex statements.
fn block_can_reuse_env(stmts : Array[@ast.Stmt]) -> Bool {
  for stmt in stmts {
    guard stmt_can_reuse_block_env(stmt) else { return false }
  }
  true
}

///|
fn stmt_can_reuse_block_env(stmt : @ast.Stmt) -> Bool {
  match stmt {
    ExprStmt(_, _)
    | ReturnStmt(_, _)
    | BreakStmt(_, _)
    | ContinueStmt(_, _)
    | ThrowStmt(_, _) => true
    StmtList(stmts, _) => block_can_reuse_env(stmts)
    _ => false
  }
}

///|
fn compile_stmt(
  stmt : @ast.Stmt,
) -> (Interpreter, ExecContext, Environment) -> Signal raise Error {
  match stmt {
    ExprStmt(expr, _) => {
      let expr_fn = compile_expr_to_closure_inner(expr)
      fn(interp, ctx, env) raise { Signal::Normal(expr_fn(interp, ctx, env)) }
    }
    ReturnStmt(expr, _) => {
      let value_fn = match expr {
        Some(e) => compile_expr_to_closure_inner(e)
        None => fn(_, _, _) { Value::Undefined }
      }
      fn(interp, ctx, env) raise {
        Signal::ReturnSignal(value_fn(interp, ctx, env))
      }
    }
    VarDecl(kind, name, init, _) => {
      let init_fn = match init {
        Some(expr) => compile_expr_to_closure_inner(expr)
        None => fn(_, _, _) { Value::Undefined }
      }
      fn(interp, ctx, env) raise {
        let binding_kind = match kind {
          LetKind => BindingKind::LetBinding
          ConstKind => BindingKind::ConstBinding
          VarKind => BindingKind::VarBinding
        }
        let value = init_fn(interp, ctx, env)
        if binding_kind == BindingKind::VarBinding &&
          (env.bindings.contains(name) || env.has_var(name)) {
          if init is Some(_) {
            env.assign_var(name, value)
          }
        } else if (
            binding_kind == BindingKind::LetBinding ||
            binding_kind == BindingKind::ConstBinding
          ) &&
          env.bindings.contains(name) {
          env.initialize(name, value)
        } else {
          env.def(name, value, binding_kind)
        }
        Signal::Normal(Value::Undefined)
      }
    }
    IfStmt(cond, then_branch, else_branch, _) => {
      let cond_fn = compile_expr_to_closure_inner(cond)
      let then_fn = compile_stmt(then_branch)
      let else_fn = match else_branch {
        Some(stmt) => Some(compile_stmt(stmt))
        None => None
      }
      fn(interp, ctx, env) raise {
        if @runtime.is_truthy(cond_fn(interp, ctx, env)) {
          then_fn(interp, ctx, env)
        } else {
          match else_fn {
            Some(run) => run(interp, ctx, env)
            None => Signal::Normal(Value::Undefined)
          }
        }
      }
    }
    WhileStmt(cond, body, _) => {
      let cond_fn = compile_expr_to_closure_inner(cond)
      let body_fn = compile_stmt(body)
      fn(interp, ctx, env) raise {
        let mut completion = Value::Undefined
        while true {
          if !@runtime.is_truthy(cond_fn(interp, ctx, env)) {
            break
          }
          match body_fn(interp, ctx, env) {
            Signal::Normal(value) => completion = value
            Signal::ReturnSignal(_) as sig => return sig
            Signal::BreakSignal(value, None) => {
              completion = value.unwrap_or(completion)
              break
            }
            Signal::BreakSignal(_, Some(_)) as sig => return sig
            Signal::ContinueSignal(value, None) => {
              completion = value.unwrap_or(completion)
              continue
            }
            Signal::ContinueSignal(_, Some(_)) as sig => return sig
          }
        }
        Signal::Normal(completion)
      }
    }
    DoWhileStmt(body, cond, _) => {
      let body_fn = compile_stmt(body)
      let cond_fn = compile_expr_to_closure_inner(cond)
      fn(interp, ctx, env) raise {
        let mut completion = Value::Undefined
        while true {
          match body_fn(interp, ctx, env) {
            Signal::Normal(value) => completion = value
            Signal::ReturnSignal(_) as sig => return sig
            Signal::BreakSignal(value, None) => {
              completion = value.unwrap_or(completion)
              break
            }
            Signal::BreakSignal(_, Some(_)) as sig => return sig
            Signal::ContinueSignal(value, None) =>
              completion = value.unwrap_or(completion)
            Signal::ContinueSignal(_, Some(_)) as sig => return sig
          }
          if !@runtime.is_truthy(cond_fn(interp, ctx, env)) {
            break
          }
        }
        Signal::Normal(completion)
      }
    }
    BreakStmt(label, _) => fn(_, _, _) { Signal::BreakSignal(None, label) }
    ContinueStmt(label, _) =>
      fn(_, _, _) { Signal::ContinueSignal(None, label) }
    ThrowStmt(expr, _) => {
      let expr_fn = compile_expr_to_closure_inner(expr)
      fn(interp, ctx, env) raise {
        let value = expr_fn(interp, ctx, env)
        @runtime.raise_js_exception(value)
        Signal::Normal(Value::Undefined)
      }
    }
    Block(stmts, _) => {
      let body = compile_body(stmts)
      if block_can_reuse_env(stmts) {
        fn(interp, ctx, env) raise { (body.0)(interp, ctx, env) }
      } else {
        fn(interp, ctx, env) raise {
          let block_env = Environment::new(parent=Some(env))
          (body.0)(interp, ctx, block_env)
        }
      }
    }
    StmtList(stmts, _) => {
      let body = compile_body(stmts)
      fn(interp, ctx, env) raise { (body.0)(interp, ctx, env) }
    }
    FuncDecl(name, params, body, _) => {
      let compiled_body = compile_body(body)
      fn(_interp, ctx, env) raise {
        @runtime.validate_function_signature(
          ctx.strict,
          Some(name),
          params,
          body,
        )
        let func = make_compiled_func(
          Some(name),
          params,
          env,
          ctx.strict || @static_semantics.has_use_strict(body),
          body=Some(compiled_body),
        )
        if env.bindings.contains(name) || env.has_var(name) {
          env.assign_var(name, func)
        } else {
          env.def(name, func, BindingKind::VarBinding)
        }
        Signal::Normal(Value::Undefined)
      }
    }
    ForStmt(init, cond, update, body, _) => {
      let init_fn = match init {
        Some(stmt) => Some(compile_stmt(stmt))
        None => None
      }
      let cond_fn = match cond {
        Some(expr) => Some(compile_expr_to_closure_inner(expr))
        None => None
      }
      let update_fn = match update {
        Some(expr) => Some(compile_expr_to_closure_inner(expr))
        None => None
      }
      let body_fn = compile_stmt(body)
      fn(interp, ctx, env) raise {
        match init_fn {
          Some(run) =>
            match run(interp, ctx, env) {
              Signal::Normal(_) => ()
              sig => return sig
            }
          None => ()
        }
        let mut completion = Value::Undefined
        while true {
          match cond_fn {
            Some(run) => if !@runtime.is_truthy(run(interp, ctx, env)) { break }
            None => ()
          }
          match body_fn(interp, ctx, env) {
            Signal::Normal(value) => completion = value
            Signal::ReturnSignal(_) as sig => return sig
            Signal::BreakSignal(value, None) => {
              completion = value.unwrap_or(completion)
              break
            }
            Signal::ContinueSignal(value, None) =>
              completion = value.unwrap_or(completion)
            sig => return sig
          }
          match update_fn {
            Some(run) => {
              let _ = run(interp, ctx, env)
            }
            None => ()
          }
        }
        Signal::Normal(completion)
      }
    }
    _ => unsupported_stmt("statement kind")
  }
}

///|
fn eval_compiled_args(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  args : Array[CompiledArg],
) -> Array[Value] raise Error {
  let values : Array[Value] = []
  for arg in args {
    match arg {
      Plain(run) => values.push(run(interp, ctx, env))
      Spread(run, loc) => {
        let spread_values = interp.spread_iterable(run(interp, ctx, env), loc)
        for value in spread_values {
          values.push(value)
        }
      }
    }
  }
  values
}

///|
fn make_compiled_func(
  name : String?,
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body? : CompiledBody? = None,
  rest_param? : String? = None,
  constructable? : Bool = true,
  call_self_name? : Bool = false,
  define_arguments_object? : Bool = true,
  bytecode_func? : BytecodeFunction? = None,
) -> Value {
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  let proto = if constructable {
    Value::Object({
      bag: PropertyBag::PropertyBag(),
      prototype: @runtime.get_obj_proto(realm_state~),
      callable: None,
      class_name: "Object",
      extensible: true,
      arraybuffer_state: None,
    })
  } else {
    Value::Null
  }
  let func_name = match name {
    Some(n) => n
    None => ""
  }
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
  let func_props : Map[String, Value] = {}
  let func_descs : Map[String, PropDescriptor] = {}
  if constructable {
    func_props["prototype"] = proto
    func_descs["prototype"] = {
      writable: true,
      enumerable: false,
      configurable: false,
      getter: None,
      setter: None,
      is_accessor: false,
    }
  }
  func_props["length"] = Value::Number(params.length().to_double())
  func_props["name"] = Value::String_(func_name)
  func_descs["length"] = nf_desc
  func_descs["name"] = nf_desc
  let func_ref : Ref[Value?] = { val: None }
  let func_obj = @runtime.stamp_function_realm(
    Value::Object({
      bag: {
        properties: func_props,
        symbol_properties: {},
        descriptors: func_descs,
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: @runtime.get_func_proto(realm_state~),
      callable: Some(
        Callable::InterpreterCallableWithContext(func_name, fn(
          interp,
          context,
          this_val,
          args,
        ) raise {
          let callee = func_ref.val.unwrap_or(Value::Undefined)
          if constructable && context.is_constructing() {
            let new_target = context.new_target()
            let instance_proto = compiled_constructor_instance_proto(
              interp, callee, new_target,
            )
            let new_obj = make_compiled_constructor_instance(instance_proto)
            let result = call_compiled_func(
              interp,
              callee,
              new_obj,
              args,
              params,
              closure,
              strict,
              body~,
              rest_param~,
              new_target~,
              call_self_name~,
              define_arguments_object~,
              bytecode_func~,
            )
            if is_constructor_return_object(result) {
              result
            } else {
              new_obj
            }
          } else {
            call_compiled_func(
              interp,
              callee,
              this_val,
              args,
              params,
              closure,
              strict,
              body~,
              rest_param~,
              call_self_name~,
              define_arguments_object~,
              bytecode_func~,
            )
          }
        }),
      ),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state~,
  )
  func_ref.val = Some(func_obj)
  if constructable {
    match proto {
      Value::Object(proto_data) => {
        proto_data.bag.properties["constructor"] = func_obj
        proto_data.bag.descriptors["constructor"] = {
          writable: true,
          enumerable: false,
          configurable: true,
          getter: None,
          setter: None,
          is_accessor: false,
        }
      }
      _ => ()
    }
  }
  func_obj
}

///|
fn compiled_constructor_instance_proto(
  interp : Interpreter,
  callee : Value,
  new_target : Value?,
) -> Value raise Error {
  let target = new_target.unwrap_or(callee)
  interp.get_prototype_from_constructor(target, @token.Loc::default())
}

///|
fn make_compiled_constructor_instance(proto : Value) -> Value {
  Value::Object({
    bag: PropertyBag::PropertyBag(),
    prototype: proto,
    callable: None,
    class_name: "Object",
    extensible: true,
    arraybuffer_state: None,
  })
}

///|
fn is_constructor_return_object(value : Value) -> Bool {
  match value {
    Value::Object(_)
    | Value::Array(_)
    | Value::Map(_)
    | Value::Set(_)
    | Value::Promise(_)
    | Value::Proxy(_) => true
    _ => false
  }
}

///|
fn make_compiled_arrow_func(
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value {
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  @runtime.make_interp_method_func(
    name="",
    length=params.length(),
    realm_state~,
    fn(interp, _this_val, args) raise {
      call_compiled_arrow_func(interp, args, params, closure, strict, body)
    },
  )
}

///|
fn call_compiled_func(
  interp : Interpreter,
  callee : Value,
  this_val : Value,
  args : Array[Value],
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body? : CompiledBody? = None,
  rest_param? : String? = None,
  new_target? : Value? = None,
  call_self_name? : Bool = false,
  define_arguments_object? : Bool = true,
  bytecode_func? : BytecodeFunction? = None,
) -> Value raise Error {
  let saved_in_default = interp.in_nonarrow_param_default_eval
  interp.in_nonarrow_param_default_eval = false
  let result : Value = try {
    let func_ctx : ExecContext = { strict, current_generator: None }
    // Leaf-function fast path: skip Environment::new (2 HashMap allocs) and
    // this/new.target inserts. All params are local slots filled by direct_args.
    match bytecode_func {
      Some(bf) if !bf.needs_own_env =>
        match
          run_bytecode_function(
            interp,
            func_ctx,
            closure,
            bf,
            direct_args=Some(args),
          ) {
          BytecodeNormal(_) => Value::Undefined
          BytecodeReturn(value) => value
        }
      _ => {
        let func_env = Environment::new(parent=Some(closure))
        func_env.is_var_scope = true
        let effective_this = if strict {
          this_val
        } else {
          match this_val {
            Value::Undefined | Value::Null => interp.global_this
            _ => this_val
          }
        }
        func_env.def("this", effective_this, BindingKind::LetBinding)
        func_env.def(
          "<new.target>",
          new_target.unwrap_or(Value::Undefined),
          BindingKind::LetBinding,
        )
        // Bind positional params: fast path skips env for params in local_names;
        // slow path writes all params through the env HashMap.
        match bytecode_func {
          Some(bf) =>
            // Only bind params NOT in local_names to env (env_slot_names and
            // params in neither list still need env for bind_env_slots/LoadName).
            bind_params_to_env_skip_locals(
              func_env,
              params,
              args,
              bf.local_indices,
            )
          None => bind_simple_params(func_env, params, args)
        }
        bind_rest_param(func_env, params.length(), rest_param, args)
        if define_arguments_object {
          match rest_param {
            Some(_) =>
              if !compiled_params_include_arguments(params, rest_param) {
                interp.define_unmapped_arguments_object(
                  func_env, args, callee, strict,
                )
              }
            None =>
              interp.define_simple_arguments_object(
                func_env, args, callee, strict, params,
              )
          }
        }
        if call_self_name {
          func_env.def_builtin("[[BytecodeCallee]]", callee)
        }
        match bytecode_func {
          Some(bf) =>
            match
              run_bytecode_function(
                interp,
                func_ctx,
                func_env,
                bf,
                direct_args=Some(args),
              ) {
              BytecodeNormal(_) => Value::Undefined
              BytecodeReturn(value) => value
            }
          None =>
            match body {
              Some(b) => reduce_body_signal((b.0)(interp, func_ctx, func_env))
              None =>
                abort(
                  "call_compiled_func: body required when bytecode_func=None",
                )
            }
        }
      }
    }
  } catch {
    err => {
      interp.in_nonarrow_param_default_eval = saved_in_default
      raise err
    }
  }
  interp.in_nonarrow_param_default_eval = saved_in_default
  result
}

///|
fn call_compiled_arrow_func(
  interp : Interpreter,
  args : Array[Value],
  params : Array[String],
  closure : Environment,
  strict : Bool,
  body : CompiledBody,
) -> Value raise Error {
  let saved_in_default = interp.in_nonarrow_param_default_eval
  interp.in_nonarrow_param_default_eval = false
  let result : Value = try {
    let func_env = Environment::new(parent=Some(closure))
    func_env.is_var_scope = true
    let func_ctx : ExecContext = { strict, current_generator: None }
    bind_simple_params(func_env, params, args)
    reduce_body_signal((body.0)(interp, func_ctx, func_env))
  } catch {
    err => {
      interp.in_nonarrow_param_default_eval = saved_in_default
      raise err
    }
  }
  interp.in_nonarrow_param_default_eval = saved_in_default
  result
}

///|
fn compiled_params_include_arguments(
  params : Array[String],
  rest_param : String?,
) -> Bool {
  for param in params {
    if param == "arguments" {
      return true
    }
  }
  rest_param is Some("arguments")
}

///|
fn bind_rest_param(
  env : Environment,
  positional_count : Int,
  rest_param : String?,
  args : Array[Value],
) -> Unit raise Error {
  match rest_param {
    Some(name) => {
      let rest_elements : Array[Value] = []
      for i = positional_count; i < args.length(); i = i + 1 {
        rest_elements.push(args[i])
      }
      env.def_parameter(name, @runtime.make_array(rest_elements))
    }
    None => ()
  }
}

///|
fn bind_params_to_env_skip_locals(
  env : Environment,
  params : Array[String],
  args : Array[Value],
  local_indices : Map[String, Int],
) -> Unit raise Error {
  for i, param in params {
    if !local_indices.contains(param) {
      let value = args.get(i).unwrap_or(Value::Undefined)
      if env.bindings.contains(param) {
        env.assign(param, value)
      } else {
        env.def_parameter(param, value)
      }
    }
  }
}

///|
fn bind_simple_params(
  env : Environment,
  params : Array[String],
  args : Array[Value],
) -> Unit raise Error {
  for i = 0; i < params.length(); i = i + 1 {
    let value = if i < args.length() { args[i] } else { Value::Undefined }
    if env.bindings.contains(params[i]) {
      env.assign(params[i], value)
    } else {
      env.def_parameter(params[i], value)
    }
  }
}

///|
fn reduce_body_signal(signal : Signal) -> Value raise Error {
  match signal {
    Signal::Normal(_) => Value::Undefined
    Signal::ReturnSignal(value) => value
    Signal::BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    Signal::ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
  }
}

///|
fn reduce_program_signal(signal : Signal) -> Value raise Error {
  match signal {
    Signal::Normal(value) => value
    Signal::ReturnSignal(_) =>
      raise @errors.SyntaxError(message="return statement outside of function")
    Signal::BreakSignal(_, _) =>
      raise @errors.SyntaxError(message="break statement outside of loop")
    Signal::ContinueSignal(_, _) =>
      raise @errors.SyntaxError(message="continue statement outside of loop")
  }
}

///|
fn is_direct_eval_callee(expr : @ast.Expr) -> Bool {
  match expr {
    Ident("eval", _) => true
    Grouping(inner, _) => is_direct_eval_callee(inner)
    _ => false
  }
}

///|
fn eval_compiled_direct_eval(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  args : Array[CompiledArg],
  loc : @token.Loc,
) -> Value raise Error {
  let callee = env.get("eval") catch {
    _ => raise @errors.ReferenceError(message="eval is not defined")
  }
  let values = eval_compiled_args(interp, ctx, env, args)
  if is_global_eval_function(callee) {
    if values.length() == 0 {
      return Value::Undefined
    }
    match values[0] {
      Value::String_(code) =>
        interp.perform_eval(code, env, true, caller_strict=ctx.strict)
      other => other
    }
  } else {
    interp.call_value(callee, Value::Undefined, values, loc)
  }
}

///|
fn is_global_eval_function(value : Value) -> Bool {
  match value {
    Value::Object(data) =>
      match data.callable {
        Some(Callable::NonConstructableCallable("eval", _)) => true
        _ => false
      }
    _ => false
  }
}

///|
fn eval_compiled_binary(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  op : @ast.BinOp,
  left_fn : (Interpreter, ExecContext, Environment) -> Value raise Error,
  right_fn : (Interpreter, ExecContext, Environment) -> Value raise Error,
  loc : @token.Loc,
) -> Value raise Error {
  match op {
    And => {
      let left = left_fn(interp, ctx, env)
      if !@runtime.is_truthy(left) {
        left
      } else {
        right_fn(interp, ctx, env)
      }
    }
    Or => {
      let left = left_fn(interp, ctx, env)
      if @runtime.is_truthy(left) {
        left
      } else {
        right_fn(interp, ctx, env)
      }
    }
    NullishCoalesce => {
      let left = left_fn(interp, ctx, env)
      match left {
        Value::Null | Value::Undefined => right_fn(interp, ctx, env)
        _ => left
      }
    }
    In => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      if @runtime.is_object_value(right) {
        Value::Bool(
          interp.has_property_key(
            right,
            @runtime.to_property_key(left, interp=Some(interp)),
          ),
        )
      } else {
        raise @errors.TypeError(
          message="Cannot use 'in' operator to search for '\{left.to_string()}' in \{@runtime.type_of(right)}",
        )
      }
    }
    Instanceof => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      eval_compiled_instanceof(interp, left, right, loc)
    }
    _ => {
      let left = left_fn(interp, ctx, env)
      let right = right_fn(interp, ctx, env)
      @runtime.eval_binary_op(op, left, right, loc, interp=Some(interp))
    }
  }
}

///|
fn eval_compiled_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> Value raise Error {
  match right {
    Value::Object(_) => {
      let has_instance = interp.get_computed_property(
        right,
        Value::Symbol(interp.realm_state.well_known_symbols.has_instance),
        loc,
      )
      match has_instance {
        Value::Null | Value::Undefined =>
          ordinary_compiled_instanceof(interp, left, right, loc)
        _ => {
          if !@runtime.is_callable(has_instance) {
            raise @errors.TypeError(
              message="Symbol.hasInstance is not a function",
            )
          }
          Value::Bool(
            @runtime.is_truthy(
              interp.call_value(has_instance, right, [left], loc),
            ),
          )
        }
      }
    }
    Value::Proxy(proxy_data) =>
      eval_compiled_proxy_instanceof(interp, left, right, proxy_data, loc)
    _ =>
      raise @errors.TypeError(
        message="Right-hand side of 'instanceof' is not an object",
      )
  }
}

///|
fn eval_compiled_proxy_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  proxy_data : ProxyData,
  loc : @token.Loc,
) -> Value raise Error {
  let target = @runtime.get_proxy_target(proxy_data)
  let proto = interp.get_property(right, "prototype", loc)
  match proto {
    Value::Object(_) => @runtime.instanceof_prototype_chain(left, proto, interp)
    _ =>
      match target {
        Value::Object(target_data) =>
          match target_data.callable {
            Some(_) => Value::Bool(false)
            None =>
              raise @errors.TypeError(
                message="Right-hand side of 'instanceof' is not callable",
              )
          }
        _ => Value::Bool(false)
      }
  }
}

///|
fn ordinary_compiled_instanceof(
  interp : Interpreter,
  left : Value,
  right : Value,
  loc : @token.Loc,
) -> Value raise Error {
  if !@runtime.is_callable(right) {
    raise @errors.TypeError(
      message="Right-hand side of 'instanceof' is not callable",
    )
  }
  if !@runtime.is_object_value(left) {
    return Value::Bool(false)
  }
  match interp.get_property(right, "prototype", loc) {
    Value::Object(_) as proto =>
      @runtime.instanceof_prototype_chain(left, proto, interp)
    _ =>
      raise @errors.TypeError(
        message="Function has non-object prototype in instanceof check",
      )
  }
}

///|
fn make_arrow_func_ext(data : FuncDataExt, length : Int) -> Value {
  let nf_desc = non_writable_function_descriptor()
  let realm_state = match data.closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => data.closure.realm_state
  }
  @runtime.stamp_function_realm(
    Value::Object({
      bag: {
        properties: {
          "name": Value::String_(""),
          "length": Value::Number(length.to_double()),
        },
        symbol_properties: {},
        descriptors: { "name": nf_desc, "length": nf_desc },
        symbol_descriptors: {},
        internal_slots: {},
      },
      prototype: @runtime.get_func_proto(realm_state~),
      callable: Some(Callable::ArrowFuncExt(data)),
      class_name: "Function",
      extensible: true,
      arraybuffer_state: None,
    }),
    realm_state~,
  )
}

///|
fn non_writable_function_descriptor() -> PropDescriptor {
  {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
    is_accessor: false,
  }
}

///|
fn arrow_ext_length(params : Array[@ast.Param]) -> Int {
  let mut length = 0
  for param in params {
    if param.default_val is Some(_) {
      break
    }
    if param.is_rest_pattern {
      break
    }
    length += 1
  }
  length
}

///|
fn unsupported_expr(
  kind : String,
) -> (Interpreter, ExecContext, Environment) -> Value raise Error {
  fn(_, _, _) raise {
    raise @errors.InternalError(
      message="closure conversion prototype does not support \{kind}",
    )
  }
}

///|
fn unsupported_stmt(
  kind : String,
) -> (Interpreter, ExecContext, Environment) -> Signal raise Error {
  fn(_, _, _) raise {
    raise @errors.InternalError(
      message="closure conversion prototype does not support \{kind}",
    )
  }
}
