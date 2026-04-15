///|
fn Interpreter::eval_update(
  self : Interpreter,
  ctx : ExecContext,
  op : @ast.UpdateOp,
  operand : @ast.Expr,
  prefix : Bool,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  match operand {
    Ident(name, _) => {
      // Strict mode: update of eval/arguments is a SyntaxError
      if ctx.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      if self.is_immutable_global(name) {
        if ctx.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
      } else {
        env.assign(name, new_val)
      }
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      let _ = self.set_property(obj, prop, new_val, loc, strict=ctx.strict)
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      // Convert key to property key once (ToPropertyKey)
      let prop_key : Value = match key {
        Symbol(_) => key
        _ => String_(to_js_string(key))
      }
      let current = self.get_computed_property(obj, prop_key, mloc)
      let num = to_number(current)
      let new_val : Value = match op {
        Increment => Number(num + 1.0)
        Decrement => Number(num - 1.0)
      }
      let _ = self.set_computed_property(
        obj,
        prop_key,
        new_val,
        loc,
        strict=ctx.strict,
      )
      if prefix {
        new_val
      } else {
        Number(num)
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid update target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_compound_assign(
  self : Interpreter,
  ctx : ExecContext,
  op : @ast.CompoundOp,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // Handle logical assignment operators with short-circuit semantics
  match op {
    LogicalAndAssign =>
      return self.eval_logical_assign_and(ctx, target, value_expr, env, loc)
    LogicalOrAssign =>
      return self.eval_logical_assign_or(ctx, target, value_expr, env, loc)
    NullishAssign =>
      return self.eval_nullish_assign(ctx, target, value_expr, env, loc)
    _ => ()
  }
  let bin_op : @ast.BinOp = match op {
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
    LogicalAndAssign | LogicalOrAssign | NullishAssign => Add // unreachable
  }
  match target {
    Ident(name, _) => {
      // Strict mode: compound assignment to eval/arguments is a SyntaxError
      if ctx.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      let rhs = self.eval_expr(ctx, value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      // Check if the target is a non-writable property on the global object
      if self.is_immutable_global(name) {
        if ctx.strict {
          raise @errors.TypeError(
            message="Cannot assign to read only property '\{name}' of object '[object global]'",
          )
        }
        return result
      }
      env.assign(name, result)
      result
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      let rhs = self.eval_expr(ctx, value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      let _ = self.set_property(obj, prop, result, loc, strict=ctx.strict)
      result
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      // Per ES5 11.2.1 step 5: CheckObjectCoercible(baseValue) before ToString
      if obj is Null {
        raise @errors.TypeError(message="Cannot read properties of null")
      }
      if obj is Undefined {
        raise @errors.TypeError(message="Cannot read properties of undefined")
      }
      // Convert key to property key once (ToPropertyKey), so toString/valueOf
      // is only called once per spec
      let prop_key : Value = match key {
        Symbol(_) => key
        _ => String_(to_js_string(key))
      }
      let current = self.get_computed_property(obj, prop_key, mloc)
      let rhs = self.eval_expr(ctx, value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc)
      let _ = self.set_computed_property(
        obj,
        prop_key,
        result,
        loc,
        strict=ctx.strict,
      )
      result
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid compound assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_logical_assign_and(
  self : Interpreter,
  ctx : ExecContext,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x &&= y: if x is truthy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if ctx.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      if is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        if self.is_immutable_global(name) {
          if ctx.strict {
            raise @errors.TypeError(
              message="Cannot assign to read only property '\{name}' of object '[object global]'",
            )
          }
          return rhs
        }
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        self.set_property(obj, prop, rhs, loc, strict=ctx.strict)
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      // Per ES5 11.2.1 step 5: CheckObjectCoercible(baseValue) before ToString
      if obj is Null {
        raise @errors.TypeError(message="Cannot read properties of null")
      }
      if obj is Undefined {
        raise @errors.TypeError(message="Cannot read properties of undefined")
      }
      let current = self.get_computed_property(obj, key, mloc)
      if is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        self.set_computed_property(obj, key, rhs, loc, strict=ctx.strict)
      } else {
        current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_logical_assign_or(
  self : Interpreter,
  ctx : ExecContext,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ||= y: if x is falsy, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if ctx.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      if !is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        if self.is_immutable_global(name) {
          if ctx.strict {
            raise @errors.TypeError(
              message="Cannot assign to read only property '\{name}' of object '[object global]'",
            )
          }
          return rhs
        }
        env.assign(name, rhs)
        rhs
      } else {
        current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      if !is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        self.set_property(obj, prop, rhs, loc, strict=ctx.strict)
      } else {
        current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      // Per ES5 11.2.1 step 5: CheckObjectCoercible(baseValue) before ToString
      if obj is Null {
        raise @errors.TypeError(message="Cannot read properties of null")
      }
      if obj is Undefined {
        raise @errors.TypeError(message="Cannot read properties of undefined")
      }
      let current = self.get_computed_property(obj, key, mloc)
      if !is_truthy(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        self.set_computed_property(obj, key, rhs, loc, strict=ctx.strict)
      } else {
        current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}

///|
fn Interpreter::eval_nullish_assign(
  self : Interpreter,
  ctx : ExecContext,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x ??= y: if x is null or undefined, assign y to x; return final value
  match target {
    Ident(name, _) => {
      if ctx.strict && (name == "eval" || name == "arguments") {
        raise @errors.SyntaxError(
          message="Unexpected eval or arguments in strict mode",
        )
      }
      let current = env.get(name)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(ctx, value_expr, env)
          if self.is_immutable_global(name) {
            if ctx.strict {
              raise @errors.TypeError(
                message="Cannot assign to read only property '\{name}' of object '[object global]'",
              )
            }
            return rhs
          }
          env.assign(name, rhs)
          rhs
        }
        _ => current
      }
    }
    Member(obj_expr, prop, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let current = self.get_property(obj, prop, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(ctx, value_expr, env)
          self.set_property(obj, prop, rhs, loc, strict=ctx.strict)
        }
        _ => current
      }
    }
    ComputedMember(obj_expr, key_expr, mloc) => {
      let obj = self.eval_expr(ctx, obj_expr, env)
      let key = self.eval_expr(ctx, key_expr, env)
      // Per ES5 11.2.1 step 5: CheckObjectCoercible(baseValue) before ToString
      if obj is Null {
        raise @errors.TypeError(message="Cannot read properties of null")
      }
      if obj is Undefined {
        raise @errors.TypeError(message="Cannot read properties of undefined")
      }
      let current = self.get_computed_property(obj, key, mloc)
      match current {
        Null | Undefined => {
          let rhs = self.eval_expr(ctx, value_expr, env)
          self.set_computed_property(obj, key, rhs, loc, strict=ctx.strict)
        }
        _ => current
      }
    }
    _ =>
      raise @errors.SyntaxError(
        message="Invalid assignment target at line \{loc.line}, col \{loc.col}",
      )
  }
}
