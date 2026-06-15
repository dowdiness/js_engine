///|
priv struct BytecodeForInState {
  keys : Array[String]
  mut index : Int
}

///|
priv struct BytecodeFrame {
  func_def : BytecodeFunction
  stack : Array[Value]
  arg_lists : Array[Array[Value]]
  for_in_iters : Array[BytecodeForInState]
  locals : Array[Value]
  env_slots : Array[Binding]
  env : Environment
  ctx : ExecContext
  mut ip : Int
  mut completion : Value
}

///|
fn BytecodeFrame::BytecodeFrame(
  func_def : BytecodeFunction,
  env : Environment,
  ctx : ExecContext,
  direct_args? : Array[Value]? = None,
) -> BytecodeFrame raise Error {
  let locals = Array::make(func_def.local_names.length(), Value::Undefined)
  match direct_args {
    Some(args) =>
      // Fast path: iterate params forward so last occurrence wins (duplicate params).
      for j, param in func_def.params {
        match func_def.local_indices.get(param) {
          Some(slot) => locals[slot] = args.get(j).unwrap_or(Value::Undefined)
          None => ()
        }
      }
    None =>
      for i, name in func_def.local_names {
        if string_array_contains(func_def.params, name) && env.has(name) {
          locals[i] = env.get(name)
        }
      }
  }
  let env_slots : Array[Binding] = if func_def.env_slot_names.length() == 0 {
    empty_bytecode_env_slots
  } else {
    let dummy_env_slot : Binding = {
      value: Value::Undefined,
      kind: BindingKind::VarBinding,
      initialized: true,
      annex_b_hoisted: false,
      is_parameter: false,
    }
    Array::make(func_def.env_slot_names.length(), dummy_env_slot)
  }
  {
    func_def,
    stack: [],
    arg_lists: [],
    for_in_iters: [],
    locals,
    env_slots,
    env,
    ctx,
    ip: 0,
    completion: Value::Undefined,
  }
}

///|
fn BytecodeFrame::bind_env_slots(self : BytecodeFrame) -> Unit raise Error {
  for i, name in self.func_def.env_slot_names {
    match self.env.bindings.get(name) {
      Some(binding) => self.env_slots[i] = binding
      None =>
        raise @errors.InternalError(
          message="bytecode env slot binding missing for '\{name}'",
        )
    }
  }
}

///|
fn BytecodeFrame::env_slot_name(self : BytecodeFrame, slot : Int) -> String {
  self.func_def.env_slot_names[slot]
}

///|
fn BytecodeFrame::read_env_slot(
  self : BytecodeFrame,
  slot : Int,
) -> Value raise Error {
  let binding = self.env_slots[slot]
  if !binding.initialized {
    let name = self.env_slot_name(slot)
    raise @errors.ReferenceError(
      message="Cannot access '\{name}' before initialization",
    )
  }
  binding.value
}

///|
fn BytecodeFrame::write_env_slot(
  self : BytecodeFrame,
  slot : Int,
  value : Value,
) -> Unit raise Error {
  let binding = self.env_slots[slot]
  if !binding.initialized {
    let name = self.env_slot_name(slot)
    raise @errors.ReferenceError(
      message="Cannot access '\{name}' before initialization",
    )
  } else if binding.kind == BindingKind::ConstBinding {
    let name = self.env_slot_name(slot)
    raise @errors.TypeError(message="Assignment to constant variable '\{name}'")
  } else {
    binding.value = value
  }
}

///|
fn BytecodeFrame::pop(self : BytecodeFrame) -> Value raise Error {
  match self.stack.pop() {
    Some(value) => value
    None => raise @errors.InternalError(message="bytecode stack underflow")
  }
}

///|
fn BytecodeFrame::peek(self : BytecodeFrame) -> Value raise Error {
  guard self.stack.length() > 0 else {
    raise @errors.InternalError(message="bytecode stack underflow")
  }
  self.stack[self.stack.length() - 1]
}

///|
fn pop_args(frame : BytecodeFrame, arg_count : Int) -> Array[Value] raise Error {
  let args = Array::make(arg_count, Value::Undefined)
  for i = arg_count - 1; i >= 0; i = i - 1 {
    args[i] = frame.pop()
  }
  args
}

///|
fn BytecodeFrame::current_arg_list(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  guard self.arg_lists.length() > 0 else {
    raise @errors.InternalError(message="bytecode argument list underflow")
  }
  self.arg_lists[self.arg_lists.length() - 1]
}

///|
fn BytecodeFrame::pop_dynamic_args(
  self : BytecodeFrame,
) -> Array[Value] raise Error {
  match self.arg_lists.pop() {
    Some(args) => args
    None =>
      raise @errors.InternalError(message="bytecode argument list underflow")
  }
}

///|
fn BytecodeFrame::hoist_env_var_bindings(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  // The env-hoist set (var-declared names that did not become local slots) is
  // precomputed at lowering on the IR (issue #325); iterate it instead of
  // re-walking source_body and re-filtering on every call.
  for name in self.func_def.env_var_hoist_names {
    interp.define_compiled_binding(
      self.env,
      VarKind,
      name,
      Value::Undefined,
      false,
    )
  }
}

///|
fn BytecodeFrame::hoist_lexical_bindings(
  self : BytecodeFrame,
) -> Unit raise Error {
  for stmt in self.func_def.source_body {
    self.hoist_lexical_bindings_from_stmt(stmt)
  }
}

///|
fn BytecodeFrame::hoist_lexical_bindings_from_stmt(
  self : BytecodeFrame,
  stmt : @ast.Stmt,
) -> Unit raise Error {
  match stmt {
    VarDecl(LetKind, name, _, _) =>
      if !self.env.bindings.contains(name) {
        self.env.def_tdz(name, BindingKind::LetBinding)
      }
    VarDecl(ConstKind, name, _, _) =>
      if !self.env.bindings.contains(name) {
        self.env.def_tdz(name, BindingKind::ConstBinding)
      }
    StmtList(stmts, _) =>
      for child in stmts {
        self.hoist_lexical_bindings_from_stmt(child)
      }
    _ => ()
  }
}

///|
fn BytecodeFrame::define_function_decl(
  self : BytecodeFrame,
  interp : Interpreter,
  name : String,
  child_index : Int,
) -> Unit raise Error {
  let child = self.func_def.children[child_index]
  let func = make_bytecode_func(child, self.env, self.ctx)
  match local_index_from_names(self.func_def.local_names, name) {
    Some(slot) => self.locals[slot] = func
    None => interp.define_compiled_binding(self.env, VarKind, name, func, true)
  }
}

///|
fn BytecodeFrame::hoist_function_decls(
  self : BytecodeFrame,
  interp : Interpreter,
) -> Unit raise Error {
  for instr in self.func_def.code {
    match instr {
      DeclareFunction(name, child_index) =>
        self.define_function_decl(interp, name, child_index)
      _ => ()
    }
  }
}

///|
fn make_bytecode_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  match func_def.rest_param {
    Some(rest_param) =>
      @runtime.validate_function_signature_ext(
        enclosing_ctx.strict,
        func_def.name,
        bytecode_ext_params_from_names(func_def.params),
        Some(rest_param),
        func_def.source_body,
      )
    None =>
      @runtime.validate_function_signature(
        enclosing_ctx.strict,
        func_def.name,
        func_def.params,
        func_def.source_body,
      )
  }
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  make_compiled_func(
    func_def.name,
    func_def.params,
    closure,
    strict,
    rest_param=func_def.rest_param,
    define_arguments_object=func_def.needs_arguments_object,
    bytecode_func=Some(func_def),
  )
}

///|
fn make_named_bytecode_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  name : String,
) -> Value raise Error {
  let self_name_env = Environment::new(parent=Some(closure))
  let func = make_bytecode_func(func_def, self_name_env, enclosing_ctx)
  self_name_env.def(name, func, LetBinding)
  func
}

///|
fn make_bytecode_method_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
  home_object : Value,
) -> Value raise Error {
  match func_def.rest_param {
    Some(rest_param) =>
      @runtime.validate_function_signature_ext(
        enclosing_ctx.strict,
        None,
        bytecode_ext_params_from_names(func_def.params),
        Some(rest_param),
        func_def.source_body,
      )
    None =>
      @runtime.validate_function_signature(
        enclosing_ctx.strict,
        None,
        func_def.params,
        func_def.source_body,
      )
  }
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  let method_env = Environment::new(parent=Some(closure))
  method_env.def_builtin("[[HomeObject]]", home_object)
  make_compiled_func(
    func_def.name,
    func_def.params,
    method_env,
    strict,
    rest_param=func_def.rest_param,
    constructable=false,
    call_self_name=func_def.call_self_name,
    define_arguments_object=func_def.needs_arguments_object,
    bytecode_func=Some(func_def),
  )
}

///|
fn BytecodeFrame::bind_call_self_name(self : BytecodeFrame) -> Unit raise Error {
  if self.func_def.call_self_name {
    match self.func_def.name {
      Some(name) =>
        if !self.env.bindings.contains(name) {
          self.env.def(name, self.env.get("[[BytecodeCallee]]"), LetBinding)
        }
      None => ()
    }
  }
}

///|
fn bytecode_ext_params_from_names(params : Array[String]) -> Array[@ast.Param] {
  let ext_params : Array[@ast.Param] = []
  for name in params {
    ext_params.push({
      name,
      default_val: None,
      pattern: None,
      is_rest_pattern: false,
    })
  }
  ext_params
}

///|
fn bind_bytecode_arrow_params(
  env : Environment,
  params : Array[String],
  rest_param : String?,
  args : Array[Value],
) -> Unit raise Error {
  bind_simple_params(env, params, args)
  match rest_param {
    Some(name) => {
      let rest_elements : Array[Value] = []
      for i = params.length(); i < args.length(); i = i + 1 {
        rest_elements.push(args[i])
      }
      env.def_parameter(name, @runtime.make_array(rest_elements))
    }
    None => ()
  }
}

///|
fn call_bytecode_arrow_func(
  interp : Interpreter,
  args : Array[Value],
  func_def : BytecodeFunction,
  closure : Environment,
  strict : Bool,
) -> Value raise Error {
  let saved_in_default = interp.in_nonarrow_param_default_eval
  interp.in_nonarrow_param_default_eval = false
  let result : Value = try {
    let func_env = Environment::new(parent=Some(closure))
    func_env.is_var_scope = true
    let func_ctx : ExecContext = { strict, current_generator: None }
    bind_bytecode_arrow_params(
      func_env,
      func_def.params,
      func_def.rest_param,
      args,
    )
    match run_bytecode_function(interp, func_ctx, func_env, func_def) {
      BytecodeNormal(value) | BytecodeReturn(value) => value
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
fn make_bytecode_arrow_func(
  func_def : BytecodeFunction,
  closure : Environment,
  enclosing_ctx : ExecContext,
) -> Value raise Error {
  match func_def.rest_param {
    Some(_) =>
      @runtime.validate_function_signature_ext(
        enclosing_ctx.strict,
        None,
        bytecode_ext_params_from_names(func_def.params),
        func_def.rest_param,
        func_def.source_body,
      )
    None =>
      @runtime.validate_function_signature(
        enclosing_ctx.strict,
        None,
        func_def.params,
        func_def.source_body,
      )
  }
  let strict = enclosing_ctx.strict || func_def.body_has_use_strict
  let realm_state = match closure.interpreter_context {
    Some(interp) => Some(interp.realm_state)
    None => closure.realm_state
  }
  @runtime.make_interp_method_func(
    name="",
    length=func_def.params.length(),
    realm_state~,
    fn(interp, _this_val, args) raise {
      call_bytecode_arrow_func(interp, args, func_def, closure, strict)
    },
  )
}

///|
fn run_bytecode_function(
  interp : Interpreter,
  ctx : ExecContext,
  env : Environment,
  func_def : BytecodeFunction,
  direct_args? : Array[Value]? = None,
) -> BytecodeRunResult raise Error {
  let frame = BytecodeFrame(func_def, env, ctx, direct_args~)
  frame.hoist_env_var_bindings(interp)
  frame.hoist_lexical_bindings()
  if frame.func_def.env_slot_names.length() > 0 {
    frame.bind_env_slots()
  }
  frame.hoist_function_decls(interp)
  frame.bind_call_self_name()
  let code = frame.func_def.code
  let code_len = code.length()
  let stack = frame.stack
  let locals = frame.locals
  let mut ip = frame.ip
  let mut completion = frame.completion
  while ip < code_len {
    let instr = code[ip]
    ip += 1
    match instr {
      LoadConst(value) => stack.push(value)
      LoadUndefined => stack.push(Value::Undefined)
      LoadThis => stack.push(@runtime.eval_this_value(env))
      LoadNewTarget => stack.push(@runtime.eval_new_target_value(env))
      LoadSuperProperty(prop, loc) =>
        stack.push(interp.eval_super_property(env, prop, loc))
      LoadSuperComputed(loc) => {
        let key = frame.pop()
        stack.push(interp.eval_super_computed_property(env, key, loc))
      }
      LoadConsoleMember(prop) => stack.push(interp.get_console_member(prop))
      LoadDirectEvalCallee => stack.push(@runtime.load_direct_eval_callee(env))
      LoadName(name) => stack.push(interp.get_compiled_name(env, name))
      LoadAssignmentName(name) =>
        stack.push(@runtime.get_assignment_name_value(ctx, env, name))
      StoreName(name) => {
        let value = frame.pop()
        stack.push(interp.assign_compiled_name(ctx, env, name, value))
      }
      LoadLocal(slot) => stack.push(locals[slot])
      StoreLocal(slot) => {
        let value = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        locals[slot] = value
        stack.push(value)
      }
      LoadEnvSlot(slot) => stack.push(frame.read_env_slot(slot))
      StoreEnvSlot(slot) => {
        let value = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        frame.write_env_slot(slot, value)
        stack.push(value)
      }
      DefineBinding(kind, name, has_initializer) => {
        let value = frame.pop()
        interp.define_compiled_binding(env, kind, name, value, has_initializer)
      }
      DefineLocal(slot, has_initializer) => {
        let value = frame.pop()
        if has_initializer {
          locals[slot] = value
        }
      }
      DefineEnvSlot(slot, has_initializer) => {
        let value = frame.pop()
        if has_initializer {
          frame.write_env_slot(slot, value)
        }
      }
      SetCompletion =>
        match stack.pop() {
          Some(value) => completion = value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
      SetCompletionValue(value) => completion = value
      Pop =>
        match stack.pop() {
          Some(_) => ()
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
      Dup => stack.push(frame.peek())
      BinaryOp(op, loc) => {
        let right = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        let left = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        stack.push(
          @runtime.eval_binary_op(op, left, right, loc, interp=Some(interp)),
        )
      }
      UnaryValueOp(op, loc) => {
        let value = frame.pop()
        stack.push(@runtime.eval_unary_value_op(op, value, loc))
      }
      TypeofName(name) =>
        stack.push(interp.typeof_compiled_name(ctx, env, name))
      DeleteName(name) =>
        stack.push(@runtime.eval_delete_identifier(interp, ctx, env, name))
      DeleteProperty(prop) => {
        let obj = frame.pop()
        stack.push(@runtime.eval_delete_property(interp, obj, prop, ctx.strict))
      }
      DeleteComputed => {
        let key = frame.pop()
        let obj = frame.pop()
        stack.push(
          @runtime.eval_delete_computed_property(interp, obj, key, ctx.strict),
        )
      }
      AppendTemplate(tail) => {
        let value = frame.pop()
        let acc = frame.pop()
        match acc {
          String_(prefix) =>
            stack.push(
              Value::String_(
                prefix +
                @runtime.to_js_string(value, interp=Some(interp)) +
                tail,
              ),
            )
          _ =>
            raise @errors.InternalError(
              message="bytecode template accumulator was not a string",
            )
        }
      }
      MakeTemplateObject(strings) => {
        let site_key = frame.func_def.template_cache_key_prefix +
          ":" +
          (ip - 1).to_string()
        stack.push(interp.get_cached_tagged_template_object(site_key, strings))
      }
      MakeRegExp(pattern, flags) =>
        stack.push(
          (interp.stdlib_hooks.make_regexp_object)(
            interp.realm_state,
            pattern,
            flags,
          ),
        )
      SetFunctionName(name) => {
        let value = frame.pop()
        @runtime.set_function_name(value, name)
        stack.push(value)
      }
      UpdateName(name, op, prefix, loc) =>
        stack.push(interp.update_compiled_name(ctx, env, name, op, prefix, loc))
      UpdateLocal(slot, op, prefix) => {
        let old_number = @runtime.to_number(locals[slot], interp=Some(interp))
        let next_value = match op {
          Increment => Value::Number(old_number + 1.0)
          Decrement => Value::Number(old_number - 1.0)
        }
        locals[slot] = next_value
        stack.push(if prefix { next_value } else { Value::Number(old_number) })
      }
      UpdateEnvSlot(slot, op, prefix) => {
        let old_number = @runtime.to_number(
          frame.read_env_slot(slot),
          interp=Some(interp),
        )
        let next_value = match op {
          Increment => Value::Number(old_number + 1.0)
          Decrement => Value::Number(old_number - 1.0)
        }
        frame.write_env_slot(slot, next_value)
        stack.push(if prefix { next_value } else { Value::Number(old_number) })
      }
      UpdateProperty(prop, op, prefix, member_loc, loc) => {
        let obj = frame.pop()
        stack.push(
          interp.eval_update_property(
            ctx, obj, prop, op, prefix, member_loc, loc,
          ),
        )
      }
      UpdateComputed(op, prefix, member_loc, loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        stack.push(
          interp.eval_update_computed_property(
            ctx, obj, key, op, prefix, member_loc, loc,
          ),
        )
      }
      Jump(target) => ip = target
      JumpIfFalse(target) => {
        let cond = match stack.pop() {
          Some(value) => value
          None =>
            raise @errors.InternalError(message="bytecode stack underflow")
        }
        if !@runtime.is_truthy(cond) {
          ip = target
        }
      }
      JumpIfFalseKeep(target) => {
        let cond = frame.peek()
        if !@runtime.is_truthy(cond) {
          ip = target
        }
      }
      JumpIfTrueKeep(target) => {
        let cond = frame.peek()
        if @runtime.is_truthy(cond) {
          ip = target
        }
      }
      JumpIfNotNullishKeep(target) =>
        match frame.peek() {
          Null | Undefined => ()
          _ => ip = target
        }
      StartForIn => {
        let obj = frame.pop()
        frame.for_in_iters.push({
          keys: @runtime.collect_for_in_keys(obj, interp),
          index: 0,
        })
      }
      ForInNext(target) => {
        guard frame.for_in_iters.length() > 0 else {
          raise @errors.InternalError(
            message="bytecode for-in iterator underflow",
          )
        }
        let state = frame.for_in_iters[frame.for_in_iters.length() - 1]
        if state.index >= state.keys.length() {
          let _ = frame.for_in_iters.pop()
          ip = target
        } else {
          let key = state.keys[state.index]
          state.index += 1
          stack.push(Value::String_(key))
        }
      }
      EndForIn =>
        match frame.for_in_iters.pop() {
          Some(_) => ()
          None =>
            raise @errors.InternalError(
              message="bytecode for-in iterator underflow",
            )
        }
      MakeArray(count) => {
        let elements = pop_args(frame, count)
        stack.push(@runtime.make_array(elements))
      }
      MakeArrayWithHoles(count, hole_idxs) => {
        let elements = pop_args(frame, count)
        stack.push(@runtime.make_array_with_holes(elements, hole_idxs))
      }
      StartArray => stack.push(@runtime.make_array([]))
      ArrayPushValue => {
        let value = frame.pop()
        @runtime.apply_array_literal_element(frame.peek(), value)
      }
      ArrayPushSpread(loc) => {
        let value = frame.pop()
        let spread_values = interp.spread_iterable(value, loc)
        @runtime.apply_array_literal_spread(frame.peek(), spread_values)
      }
      ArrayPushHole => @runtime.apply_array_literal_hole(frame.peek())
      StartArgs => frame.arg_lists.push([])
      ArgPushValue => {
        let value = frame.pop()
        let args = frame.current_arg_list()
        args.push(value)
      }
      ArgPushSpread(loc) => {
        let value = frame.pop()
        let spread_values = interp.spread_iterable(value, loc)
        let args = frame.current_arg_list()
        for spread_value in spread_values {
          args.push(spread_value)
        }
      }
      MakeObject(keys) => {
        let values = pop_args(frame, keys.length())
        let properties : Map[String, Value] = {}
        for i, key in keys {
          properties[key] = values[i]
        }
        let prototype = env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        stack.push(
          @runtime.make_object(properties, prototype, None, "Object", {}, true),
        )
      }
      StartObject => {
        let prototype = env.get("[[ObjectPrototype]]") catch {
          _ => Value::Null
        }
        stack.push(
          @runtime.make_object({}, prototype, None, "Object", {}, true),
        )
      }
      ObjectSetStatic(key) => {
        let value = frame.pop()
        @runtime.apply_object_literal_static_data_property(
          frame.peek(),
          key,
          value,
        )
      }
      ObjectSetStaticGetter(key) => {
        let getter = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          Value::String_(key),
          getter,
          true,
        )
      }
      ObjectSetStaticSetter(key) => {
        let setter = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          Value::String_(key),
          setter,
          false,
        )
      }
      ObjectSetComputedGetter => {
        let getter = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          key,
          getter,
          true,
        )
      }
      ObjectSetComputedSetter => {
        let setter = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_accessor_property(
          frame.peek(),
          key,
          setter,
          false,
        )
      }
      ToObjectLiteralPropertyKey => {
        let key = frame.pop()
        stack.push(interp.to_object_literal_property_key(key))
      }
      ObjectSetComputed => {
        let value = frame.pop()
        let key = frame.pop()
        @runtime.apply_object_literal_data_property(frame.peek(), key, value)
      }
      ObjectSpread(loc) => {
        let source = frame.pop()
        interp.copy_object_spread_properties(frame.peek(), source, loc)
      }
      ObjectSetProto => {
        let value = frame.pop()
        @runtime.apply_object_literal_proto_property(frame.peek(), value)
      }
      MakeFunction(index) => {
        let child = frame.func_def.children[index]
        stack.push(make_bytecode_func(child, env, ctx))
      }
      MakeNamedFunction(index, name) => {
        let child = frame.func_def.children[index]
        stack.push(make_named_bytecode_func(child, env, ctx, name))
      }
      MakeMethodFunction(index) => {
        let child = frame.func_def.children[index]
        let home_object = frame.peek()
        stack.push(make_bytecode_method_func(child, env, ctx, home_object))
      }
      MakeComputedMethodFunction(index) => {
        let child = frame.func_def.children[index]
        guard stack.length() >= 2 else {
          raise @errors.InternalError(
            message="bytecode computed method missing home object",
          )
        }
        let home_object = stack[stack.length() - 2]
        stack.push(make_bytecode_method_func(child, env, ctx, home_object))
      }
      MakeArrowFunction(index) => {
        let child = frame.func_def.children[index]
        stack.push(make_bytecode_arrow_func(child, env, ctx))
      }
      DeclareFunction(_, _) => ()
      GetProperty(prop, loc) => {
        let obj = frame.pop()
        stack.push(interp.get_property(obj, prop, loc))
      }
      GetComputed(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        stack.push(interp.get_computed_property(obj, key, loc))
      }
      ReadPropertyForAssign(prop, loc) => {
        let obj = frame.peek()
        stack.push(interp.get_property(obj, prop, loc))
      }
      ReadComputedForAssign(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        if obj is Null {
          raise @errors.TypeError(message="Cannot read properties of null")
        }
        if obj is Undefined {
          raise @errors.TypeError(message="Cannot read properties of undefined")
        }
        let prop_key = @runtime.to_property_key(key, interp=Some(interp))
        let current = interp.get_computed_property(obj, prop_key, loc)
        stack.push(obj)
        stack.push(prop_key)
        stack.push(current)
      }
      DropPropertyAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        stack.push(current)
      }
      DropComputedAssignReference => {
        let current = frame.pop()
        let _ = frame.pop()
        let _ = frame.pop()
        stack.push(current)
      }
      SetProperty(prop, loc) => {
        let value = frame.pop()
        let obj = frame.pop()
        stack.push(
          interp.set_property(obj, prop, value, loc, strict=ctx.strict),
        )
      }
      SetComputed(loc) => {
        let value = frame.pop()
        let key = frame.pop()
        let obj = frame.pop()
        stack.push(
          interp.set_computed_property(obj, key, value, loc, strict=ctx.strict),
        )
      }
      SetForInProperty(prop, loc) => {
        let obj = frame.pop()
        let value = frame.pop()
        stack.push(
          interp.set_property(obj, prop, value, loc, strict=ctx.strict),
        )
      }
      SetForInComputed(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        let value = frame.pop()
        stack.push(
          interp.set_computed_property(obj, key, value, loc, strict=ctx.strict),
        )
      }
      AssignPattern(pattern) => {
        let value = frame.pop()
        stack.push(interp.eval_destructure_assign(ctx, pattern, value, env))
      }
      PreparePropertyCall(prop, loc) => {
        let obj = frame.pop()
        let callee = interp.get_property(obj, prop, loc)
        stack.push(obj)
        stack.push(callee)
      }
      PrepareComputedCall(loc) => {
        let key = frame.pop()
        let obj = frame.pop()
        let callee = interp.get_computed_property(obj, key, loc)
        stack.push(obj)
        stack.push(callee)
      }
      PrepareSuperPropertyCall(prop, loc) => {
        let (receiver, callee) = interp.eval_super_property_call_reference(
          env, prop, loc,
        )
        stack.push(receiver)
        stack.push(callee)
      }
      PrepareSuperComputedCall(loc) => {
        let key = frame.pop()
        let (receiver, callee) = interp.eval_super_computed_call_reference(
          env, key, loc,
        )
        stack.push(receiver)
        stack.push(callee)
      }
      CallDirectEval(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        stack.push(
          interp.call_direct_eval_or_shadowed(
            callee,
            args,
            env,
            loc,
            caller_strict=ctx.strict,
          ),
        )
      }
      Call(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        stack.push(interp.call_value(callee, Value::Undefined, args, loc))
      }
      CallWithReceiver(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let callee = frame.pop()
        let receiver = frame.pop()
        stack.push(interp.call_value(callee, receiver, args, loc))
      }
      CallSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        stack.push(interp.call_value(callee, Value::Undefined, args, loc))
      }
      CallSpreadWithReceiver(loc) => {
        let args = frame.pop_dynamic_args()
        let callee = frame.pop()
        let receiver = frame.pop()
        stack.push(interp.call_value(callee, receiver, args, loc))
      }
      Construct(arg_count, loc) => {
        let args = pop_args(frame, arg_count)
        let ctor = frame.pop()
        stack.push(interp.construct_value(ctor, args, loc))
      }
      ConstructSpread(loc) => {
        let args = frame.pop_dynamic_args()
        let ctor = frame.pop()
        stack.push(interp.construct_value(ctor, args, loc))
      }
      Return => return BytecodeReturn(frame.pop())
      Throw => {
        let value = frame.pop()
        @runtime.raise_js_exception(value)
      }
    }
  }
  frame.ip = ip
  frame.completion = completion
  BytecodeNormal(completion)
}
