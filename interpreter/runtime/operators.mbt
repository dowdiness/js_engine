///|
pub fn compound_assign_binary_op(op : @ast.CompoundOp) -> @ast.BinOp? {
  match op {
    AddAssign => Some(Add)
    SubAssign => Some(Sub)
    MulAssign => Some(Mul)
    ExpAssign => Some(Exp)
    DivAssign => Some(Div)
    ModAssign => Some(Mod)
    BitAndAssign => Some(BitAnd)
    BitOrAssign => Some(BitOr)
    BitXorAssign => Some(BitXor)
    LShiftAssign => Some(LShift)
    RShiftAssign => Some(RShift)
    URShiftAssign => Some(URShift)
    LogicalAndAssign | LogicalOrAssign | NullishAssign => None
  }
}

///|
pub fn get_assignment_name_value(
  ctx : ExecContext,
  env : Environment,
  name : String,
) -> Value raise Error {
  validate_strict_assignment_target_name(ctx.strict, name)
  env.get(name)
}

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
      let current = get_assignment_name_value(ctx, env, name)
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
      let prop_key = to_property_key(key, interp=Some(self))
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
  let bin_op : @ast.BinOp = match compound_assign_binary_op(op) {
    Some(bin_op) => bin_op
    None =>
      raise @errors.InternalError(
        message="unexpected logical compound assignment mapping",
      )
  }
  match target {
    Ident(name, _) => {
      let current = get_assignment_name_value(ctx, env, name)
      let rhs = self.eval_expr(ctx, value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc, interp=Some(self))
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
      let result = eval_binary_op(bin_op, current, rhs, loc, interp=Some(self))
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
      let prop_key = to_property_key(key, interp=Some(self))
      let current = self.get_computed_property(obj, prop_key, mloc)
      let rhs = self.eval_expr(ctx, value_expr, env)
      let result = eval_binary_op(bin_op, current, rhs, loc, interp=Some(self))
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
/// Shared skeleton for `&&=`, `||=`, and `??=`.
/// `should_assign(current)` returns true when the operator requires a write.
fn Interpreter::eval_logical_assign(
  self : Interpreter,
  ctx : ExecContext,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
  should_assign : (Value) -> Bool,
) -> Value raise Error {
  match target {
    Ident(name, _) => {
      let current = get_assignment_name_value(ctx, env, name)
      if should_assign(current) {
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
      if should_assign(current) {
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
      let prop_key = to_property_key(key, interp=Some(self))
      let current = self.get_computed_property(obj, prop_key, mloc)
      if should_assign(current) {
        let rhs = self.eval_expr(ctx, value_expr, env)
        self.set_computed_property(obj, prop_key, rhs, loc, strict=ctx.strict)
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
fn Interpreter::eval_logical_assign_and(
  self : Interpreter,
  ctx : ExecContext,
  target : @ast.Expr,
  value_expr : @ast.Expr,
  env : Environment,
  loc : @token.Loc,
) -> Value raise Error {
  // x &&= y: assign y when x is truthy
  self.eval_logical_assign(ctx, target, value_expr, env, loc, is_truthy)
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
  // x ||= y: assign y when x is falsy
  self.eval_logical_assign(ctx, target, value_expr, env, loc, v => !is_truthy(v))
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
  // x ??= y: assign y when x is null or undefined
  self.eval_logical_assign(ctx, target, value_expr, env, loc, v => {
    v is Null || v is Undefined
  })
}
