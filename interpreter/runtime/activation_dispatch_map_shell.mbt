///|
// The Array.map continuation family is kept in its own shell module so the
// shared activation driver only owns dispatch wiring and cleanup boundaries.

///|
#warnings("-unused_value")
fn PrimitiveProgramDispatchShell::require_array_map_registry(
  self : PrimitiveProgramDispatchShell,
) -> TrustedArrayMapRecursionRegistry raise InvalidActivationDispatchShell {
  match self.array_map_registry {
    Some(registry) => registry
    None =>
      invalid_activation_dispatch_shell(
        "array map activation requires a sealed runtime registry",
      )
  }
}

///|
#warnings("-unused_value")
fn PrimitiveProgramDispatchShell::array_map_root_stmts_or_fail(
  self : PrimitiveProgramDispatchShell,
) -> Array[@ast.Stmt] raise InvalidActivationDispatchShell {
  match self.array_map_root_stmts {
    Some(stmts) => stmts
    None =>
      invalid_activation_dispatch_shell(
        "array map root statements were not retained by admission",
      )
  }
}

///|
#warnings("-unused_value")
fn PrimitiveProgramDispatchShell::current_array_map_state(
  self : PrimitiveProgramDispatchShell,
) -> MapState raise InvalidActivationDispatchShell {
  guard !self.array_map_states.is_empty() else {
    invalid_activation_dispatch_shell(
      "array map callback started without an active map state",
    )
  }
  self.array_map_states[self.array_map_states.length() - 1]
}

///|
fn PrimitiveProgramDispatchShell::expression_root_call_loc_matches(
  self : PrimitiveProgramDispatchShell,
  loc : @token.Loc,
) -> Bool {
  for expected in self.expression_root_call_locs {
    if expected == loc {
      return true
    }
  }
  false
}

///|
fn array_map_member_receiver_matches(
  receiver : Value,
  callee : Value,
  property : String,
) -> Bool {
  match receiver {
    Object(data) =>
      data.bag.properties.get(property) is Some(value) &&
      array_map_value_identity_matches(value, callee) &&
      !data.bag.descriptors.contains(property)
    _ => false
  }
}

///|
fn PrimitiveProgramDispatchShell::enter_array_map_call(
  self : PrimitiveProgramDispatchShell,
  request : DispatchCallRequest,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_array_map_registry()
  guard array_map_registry_is_stable(self.interp, registry) else {
    invalid_activation_dispatch_shell(
      "array map intrinsic identity drifted before managed call entry",
    )
  }
  let plan = registry.plan
  let is_step = array_map_value_identity_matches(
    registry.step_function,
    request.callee,
  )
  let is_forward = match registry.forward_function {
    Some(forward_function) =>
      array_map_value_identity_matches(forward_function, request.callee)
    None => false
  }
  let state : MapState? = if self.array_map_states.is_empty() {
    None
  } else {
    Some(self.current_array_map_state())
  }
  let is_callback = match state {
    Some(map_state) =>
      array_map_value_identity_matches(map_state.callback, request.callee)
    None => false
  }
  let is_member = match state {
    Some(_) if plan.callback_family is ArrayMapMemberCallback =>
      array_map_member_receiver_matches(
        request.this_value,
        request.callee,
        plan.member_property_name,
      )
    None => false
    _ => false
  }
  guard (is_step && !is_callback && !is_forward && !is_member) ||
    (!is_step && is_callback && !is_forward && !is_member) ||
    (!is_step && !is_callback && is_forward && !is_member) ||
    (!is_step && !is_callback && !is_forward && is_member) else {
    invalid_activation_dispatch_shell(
      "array map call identity is outside the sealed activation family",
    )
  }
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "array map activation lost its exact UserFunc provenance",
    )
  }
  guard function_source_identity(request.callee) ==
    registry.expected_source_identity else {
    invalid_activation_dispatch_shell(
      "array map activation source identity changed after sealing",
    )
  }
  if is_step {
    guard request.this_value is Undefined else {
      invalid_activation_dispatch_shell(
        "array map step activation requires an undefined receiver",
      )
    }
    match plan.callback_family {
      ArrayMapMemberCallback => {
        guard request.args.length() == 1 else {
          invalid_activation_dispatch_shell(
            "array map member step activation requires one argument",
          )
        }
        guard request.args[0] is Number(_) else {
          invalid_activation_dispatch_shell(
            "array map member step activation requires a numeric argument",
          )
        }
        guard data.body.length() == 3 && data.params.length() == 1 else {
          invalid_activation_dispatch_shell(
            "array map member step activation body changed after sealing",
          )
        }
      }
      ArrayMapDirectCallback => {
        guard request.args.length() == 3 else {
          invalid_activation_dispatch_shell(
            "array map direct step activation requires three arguments",
          )
        }
        guard request.args[0] is Number(_) &&
          request.args[1] is Number(_) &&
          request.args[2] is Bool(_) else {
          invalid_activation_dispatch_shell(
            "array map direct step activation argument types changed",
          )
        }
        guard data.body.length() == 2 &&
          data.params ==
          [
            plan.parameter_name,
            plan.value_parameter_name,
            plan.flag_parameter_name,
          ] &&
          array_map_direct_step_body_matches(data.body, plan) else {
          invalid_activation_dispatch_shell(
            "array map direct step activation body changed after sealing",
          )
        }
      }
      ArrayMapForwardingCallback => {
        guard request.args.length() == 1 && request.args[0] is Number(_) else {
          invalid_activation_dispatch_shell(
            "array map forwarding step activation requires one numeric argument",
          )
        }
        guard data.params == [plan.parameter_name] &&
          data.body.length() == 2 &&
          array_map_forwarding_step_body_matches(data.body, plan) else {
          invalid_activation_dispatch_shell(
            "array map forwarding step activation body changed after sealing",
          )
        }
      }
    }
    guard request.loc == plan.root_call_loc ||
      request.loc == plan.recursive_call_loc ||
      (is_step && self.expression_root_call_loc_matches(request.loc)) ||
      (
        plan.callback_family is ArrayMapForwardingCallback &&
        request.loc == plan.forward_call_loc
      ) else {
      invalid_activation_dispatch_shell(
        "array map step activation escaped its sealed source locations",
      )
    }
    guard data.name == Some(plan.function_name) &&
      !data.strict &&
      !data.has_name_binding &&
      !data.is_method &&
      physical_equal(data.closure, self.interp.global) else {
      invalid_activation_dispatch_shell(
        "array map step UserFunc provenance changed after sealing",
      )
    }
  } else if is_callback {
    guard request.this_value is Undefined &&
      request.args.length() == 3 &&
      request.loc == plan.callback_call_loc &&
      data.params.length() == 1 &&
      data.params[0] == plan.callback_parameter else {
      invalid_activation_dispatch_shell(
        "array map callback activation changed after sealing",
      )
    }
    match plan.callback_family {
      ArrayMapMemberCallback =>
        if !array_map_callback_body_matches(
            data.body,
            plan.callback_parameter,
            plan.member_property_name,
          ) {
          invalid_activation_dispatch_shell(
            "array map member callback body changed after sealing",
          )
        }
      ArrayMapDirectCallback =>
        if !array_map_direct_callback_body_matches(data.body, plan) {
          invalid_activation_dispatch_shell(
            "array map direct callback body changed after sealing",
          )
        }
      ArrayMapForwardingCallback => {
        if !array_map_forwarding_callback_body_matches(data.body, plan) {
          invalid_activation_dispatch_shell(
            "array map forwarding callback body changed after sealing",
          )
        }
        match state {
          Some(map_state) => {
            guard request.args[0] is Number(_) &&
              request.args[1] is Number(index) &&
              index == map_state.index.to_double() &&
              array_map_value_identity_matches(
                request.args[2],
                map_state.receiver,
              ) else {
              invalid_activation_dispatch_shell(
                "array map forwarding callback arguments changed after sealing",
              )
            }
          }
          None =>
            invalid_activation_dispatch_shell(
              "array map forwarding callback lost its map state",
            )
        }
      }
    }
  } else if is_forward {
    guard plan.callback_family is ArrayMapForwardingCallback &&
      request.this_value is Undefined &&
      request.args.length() == 1 &&
      request.args[0] is Number(_) &&
      request.loc == plan.forward_callback_call_loc &&
      data.name == Some(plan.forward_function_name) &&
      data.params == [plan.forward_parameter_name] &&
      data.body.length() == 2 &&
      array_map_forwarding_body_matches(data.body, plan) else {
      invalid_activation_dispatch_shell(
        "array map forwarding activation changed after sealing",
      )
    }
  } else {
    guard plan.callback_family is ArrayMapMemberCallback &&
      request.args.is_empty() &&
      request.loc == plan.member_call_loc &&
      data.params.is_empty() &&
      array_map_next_body_matches(
        data.body,
        plan.function_name,
        plan.parameter_name,
      ) else {
      invalid_activation_dispatch_shell(
        "array map member activation changed after sealing",
      )
    }
  }
  if is_forward {
    guard data.name == Some(plan.forward_function_name) &&
      !data.strict &&
      !data.has_name_binding &&
      !data.is_method &&
      physical_equal(data.closure, self.interp.global) else {
      invalid_activation_dispatch_shell(
        "array map forwarding UserFunc provenance changed after sealing",
      )
    }
  } else if !is_step {
    guard data.name is None &&
      !data.strict &&
      !data.has_name_binding &&
      !data.is_method &&
      !self.array_map_activation_envs.is_empty() else {
      invalid_activation_dispatch_shell(
        "array map callback or member UserFunc flags changed after sealing",
      )
    }
    let expected_enclosing_env = self.array_map_activation_envs[self.array_map_activation_envs.length() -
      1]
    if is_callback {
      guard physical_equal(data.closure, expected_enclosing_env) else {
        invalid_activation_dispatch_shell(
          "array map callback closure escaped its enclosing step",
        )
      }
    } else {
      guard data.closure.parent is Some(parent) &&
        physical_equal(parent, expected_enclosing_env) else {
        invalid_activation_dispatch_shell(
          "array map member closure escaped its enclosing step",
        )
      }
    }
  }
  let id = self.reserve_program_cleanup_id()
  let observation = match self.begin_managed_activation_observation() {
    Ok(attempt) => attempt
    Err(error) =>
      return self.reject_denied_managed_activation(
        id,
        RejectedArrayMapCall,
        error,
      )
  }
  let cleared_realm = begin_cleared_active_callee_realm(self.interp.realm_state)
  let active_realm = begin_active_callee_realm_value(
    self.interp.realm_state,
    request.callee,
  )
  let parameter_gate = self.interp.begin_simple_user_func_parameter_gate()
  let setup : Result[PreparedUserFuncActivation, Error] = Ok(
    self.interp.prepare_user_func_activation(
      request.callee,
      request.this_value,
      request.args,
      data,
      throw_type_error_source=UsePreResolvedThrowTypeError(
        registry.expected_throw_type_error,
      ),
    ),
  ) catch {
    error => Err(error)
  }
  let resources = DispatchReceiverCallRealmCleanup(
    cleared_realm~,
    active_realm~,
    parameter_gate~,
  )
  match setup {
    Ok(prepared) => {
      let token = accept_managed_activation_observation(observation)
      self.push_array_map_call_cleanup(
        id,
        AcceptedArrayMapCall,
        resources,
        Some(AcceptedActivationObservation(token)),
      )
      DispatchCallAccepted(
        DispatchActivationCleanup(id),
        DispatchCallBody(
          DispatchStatementCursor(
            ctx=prepared.ctx,
            stmts=data.body,
            env=prepared.env,
            production=true,
          ),
        ),
      )
    }
    Err(error) => {
      reject_managed_activation_observation(observation)
      self.push_array_map_call_cleanup(
        id,
        RejectedArrayMapCall,
        resources,
        Some(RejectedActivationObservation(observation)),
      )
      DispatchActivationRejected(
        DispatchRejectedEntryCleanup(id),
        dispatch_entry_rejection(error),
      )
    }
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_array_map_root_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  preflight : ArrayMapRecursionPreflight,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  guard physical_equal(step.env, self.interp.global) &&
    classify_array_map_recursion_program(self.array_map_root_stmts_or_fail())
    is Some(_) else {
    invalid_activation_dispatch_shell(
      "array map root statement lost its exact admission",
    )
  }
  match step.index {
    0 => {
      let result = self.execute_statement_with_legacy_adapter(step)
      match result {
        DispatchWorkCompleted(DispatchNormal(_)) =>
          if preflight.plan.callback_family is ArrayMapForwardingCallback {
            ()
          } else {
            let registry = self.interp.seal_array_map_recursion_registry(
              preflight,
              self.array_map_root_stmts_or_fail(),
            )
            self.array_map_registry = Some(registry)
          }
        _ => ()
      }
      result
    }
    1 => {
      if preflight.plan.callback_family is ArrayMapForwardingCallback {
        let result = self.execute_statement_with_legacy_adapter(step)
        match result {
          DispatchWorkCompleted(DispatchNormal(_)) => {
            let registry = self.interp.seal_array_map_recursion_registry(
              preflight,
              self.array_map_root_stmts_or_fail(),
            )
            self.array_map_registry = Some(registry)
          }
          _ => ()
        }
        return result
      }
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let registry = self.require_array_map_registry()
      let args = match preflight.plan.callback_family {
        ArrayMapMemberCallback => [Number(preflight.plan.initial_count)]
        ArrayMapDirectCallback =>
          [
            Number(preflight.plan.initial_count),
            Number(preflight.plan.initial_value),
            Bool(preflight.plan.initial_flag),
          ]
        ArrayMapForwardingCallback => [Number(preflight.plan.initial_count)]
      }
      let request = DispatchCallRequest(
        callee=registry.step_function,
        this_value=Undefined,
        args~,
        loc=preflight.plan.root_call_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendCall(request, DispatchDeliverCallResult),
      )
    }
    2 => {
      guard preflight.plan.callback_family is ArrayMapForwardingCallback else {
        invalid_activation_dispatch_shell(
          "array map root statement index 2 is outside exact admission",
        )
      }
      match self.observe_managed_execution_steps(3) {
        Some(completion) => return DispatchWorkCompleted(completion)
        None => ()
      }
      let registry = self.require_array_map_registry()
      let request = DispatchCallRequest(
        callee=registry.step_function,
        this_value=Undefined,
        args=[Number(preflight.plan.initial_count)],
        loc=preflight.plan.root_call_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendCall(request, DispatchDeliverCallResult),
      )
    }
    _ =>
      invalid_activation_dispatch_shell(
        "array map root statement index is outside exact admission",
      )
  }
}

///|
fn array_map_step_statement_matches(
  plan : ArrayMapRecursionPlan,
  index : Int,
  stmt : @ast.Stmt,
) -> Bool {
  match plan.callback_family {
    ArrayMapMemberCallback =>
      match (index, stmt) {
        (0, @ast.IfStmt(_, @ast.ReturnStmt(Some(_), _), None, _)) => true
        (1, @ast.VarDecl(_, name, Some(@ast.ArrayLit(_, _)), _)) =>
          name == plan.items_name
        (
          2,
          @ast.ReturnStmt(
            Some(@ast.Binary(@ast.Add, _, @ast.ComputedMember(_, _, _), _)),
            _
          ),
        ) => true
        _ => false
      }
    ArrayMapDirectCallback =>
      match index {
        0 => array_map_direct_base_statement_matches(stmt, plan)
        1 => array_map_direct_step_statement_matches(stmt, plan)
        _ => false
      }
    ArrayMapForwardingCallback =>
      match index {
        0 => array_map_direct_base_statement_matches(stmt, plan)
        1 => array_map_forwarding_step_return_statement_matches(stmt, plan)
        _ => false
      }
  }
}

///|
fn array_map_single_callback_statement_matches(
  stmt : @ast.Stmt,
  parameter_name : String,
  member_property_name : String,
) -> Bool {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Call(
          @ast.Member(@ast.Ident(actual_parameter, _), actual_property, _),
          [],
          _
        )
      ),
      _
    ) =>
      actual_parameter == parameter_name &&
      actual_property == member_property_name
    _ => false
  }
}

///|
fn array_map_single_direct_callback_statement_matches(
  stmt : @ast.Stmt,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Call(
          @ast.Ident(actual_name, _),
          [
            @ast.Binary(
              @ast.Sub,
              @ast.Ident(actual_parameter, _),
              decrement,
              subtract_loc
            ),
            @ast.Ident(actual_value_parameter, _),
            @ast.Unary(@ast.Not, @ast.Ident(actual_flag_parameter, _), not_loc),
          ],
          recursive_call_loc
        )
      ),
      _
    ) =>
      actual_name == plan.function_name &&
      actual_parameter == plan.parameter_name &&
      actual_value_parameter == plan.callback_parameter &&
      actual_flag_parameter == plan.flag_parameter_name &&
      recursive_call_loc == plan.recursive_call_loc &&
      subtract_loc == plan.recursive_subtract_loc &&
      not_loc == plan.recursive_not_loc &&
      array_map_number(decrement, 1.0)
    _ => false
  }
}

///|
fn array_map_direct_base_statement_matches(
  stmt : @ast.Stmt,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match stmt {
    @ast.IfStmt(
      @ast.Binary(
        @ast.EqEqEq,
        @ast.Ident(actual_parameter, _),
        base,
        condition_loc
      ),
      @ast.ReturnStmt(Some(base_result), _),
      None,
      _
    ) =>
      actual_parameter == plan.parameter_name &&
      condition_loc == plan.base_condition_loc &&
      array_map_number(base, 0.0) &&
      array_map_number(base_result, 0.0)
    _ => false
  }
}

///|
fn array_map_direct_callback_expr_matches(
  expr : @ast.Expr,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match
    classify_array_map_direct_callback(
      expr,
      plan.function_name,
      plan.parameter_name,
      plan.value_parameter_name,
      plan.flag_parameter_name,
    ) {
    Some((parameter, recursive_call_loc, subtract_loc, not_loc)) =>
      parameter == plan.callback_parameter &&
      recursive_call_loc == plan.recursive_call_loc &&
      subtract_loc == plan.recursive_subtract_loc &&
      not_loc == plan.recursive_not_loc
    None => false
  }
}

///|
fn array_map_direct_step_statement_matches(
  stmt : @ast.Stmt,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Binary(
          @ast.Add,
          increment,
          @ast.ComputedMember(
            @ast.Call(
              @ast.Member(
                @ast.ArrayLit([@ast.Ident(actual_value_parameter, _)], _),
                actual_map_property,
                map_call_loc
              ),
              [callback],
              callback_call_loc
            ),
            @ast.NumberLit(result_index, _, _),
            result_member_loc
          ),
          recursive_add_loc
        )
      ),
      _
    ) =>
      actual_value_parameter == plan.value_parameter_name &&
      actual_map_property == plan.map_property_name &&
      result_index == 0 &&
      map_call_loc == plan.map_call_loc &&
      callback_call_loc == plan.callback_call_loc &&
      result_member_loc == plan.result_member_loc &&
      recursive_add_loc == plan.recursive_add_loc &&
      array_map_number(increment, 1.0) &&
      array_map_direct_callback_expr_matches(callback, plan)
    _ => false
  }
}

///|
fn array_map_single_next_statement_matches(
  stmt : @ast.Stmt,
  function_name : String,
  parameter_name : String,
) -> Bool {
  match stmt {
    @ast.ReturnStmt(
      Some(
        @ast.Call(
          @ast.Ident(actual_name, _),
          [@ast.Binary(@ast.Sub, @ast.Ident(actual_parameter, _), decrement, _)],
          _
        )
      ),
      _
    ) =>
      actual_name == function_name &&
      actual_parameter == parameter_name &&
      array_map_number(decrement, 1.0)
    _ => false
  }
}

///|
fn array_map_receiver_is_exact(
  interp : Interpreter,
  value : Value,
  expected_array_prototype : Value,
) -> Bool {
  match value {
    Array(data) =>
      data.elements.length() == 1 &&
      data.holes.is_empty() &&
      data.bag.properties.length() == 0 &&
      data.bag.descriptors.length() == 0 &&
      get_array_prototype_override(data) is None &&
      array_map_value_identity_matches(
        get_array_prototype(interp.realm_state, data),
        expected_array_prototype,
      ) &&
      (match data.elements[0] {
        Object(item) =>
          item.class_name == "Object" &&
          item.callable is None &&
          item.bag.properties.length() == 1 &&
          item.bag.properties.get("next") is Some(Object(_)) &&
          !item.bag.descriptors.contains("next")
        _ => false
      })
    _ => false
  }
}

///|
fn array_map_direct_receiver_is_exact(
  interp : Interpreter,
  value : Value,
  expected_array_prototype : Value,
) -> Bool {
  match value {
    Array(data) =>
      data.elements.length() == 1 &&
      data.holes.is_empty() &&
      data.bag.properties.length() == 0 &&
      data.bag.descriptors.length() == 0 &&
      get_array_prototype_override(data) is None &&
      array_map_value_identity_matches(
        get_array_prototype(interp.realm_state, data),
        expected_array_prototype,
      ) &&
      data.elements[0] is Number(_)
    _ => false
  }
}

///|
fn array_map_forwarding_receiver_is_exact(
  interp : Interpreter,
  value : Value,
  expected_array_prototype : Value,
) -> Bool {
  match value {
    Array(data) =>
      data.elements.length() == 2 &&
      data.holes.is_empty() &&
      data.bag.properties.length() == 0 &&
      data.bag.descriptors.length() == 0 &&
      get_array_prototype_override(data) is None &&
      array_map_value_identity_matches(
        get_array_prototype(interp.realm_state, data),
        expected_array_prototype,
      ) &&
      data.elements[0] is Number(_) &&
      data.elements[1] is Number(_)
    _ => false
  }
}

///|
fn array_map_receiver_is_exact_for_plan(
  interp : Interpreter,
  value : Value,
  expected_array_prototype : Value,
  plan : ArrayMapRecursionPlan,
) -> Bool {
  match plan.callback_family {
    ArrayMapMemberCallback =>
      array_map_receiver_is_exact(interp, value, expected_array_prototype)
    ArrayMapDirectCallback =>
      array_map_direct_receiver_is_exact(
        interp, value, expected_array_prototype,
      )
    ArrayMapForwardingCallback =>
      array_map_forwarding_receiver_is_exact(
        interp, value, expected_array_prototype,
      )
  }
}

///|
fn array_map_enclosing_number(
  env : Environment,
  name : String,
) -> Double raise InvalidActivationDispatchShell {
  match env.bindings.get(name) {
    Some(binding) if binding.initialized && binding.is_parameter =>
      match binding.value {
        Number(value) => value
        _ =>
          invalid_activation_dispatch_shell(
            "array map enclosing parameter is not numeric",
          )
      }
    _ =>
      match env.parent {
        Some(parent) => array_map_enclosing_number(parent, name)
        None =>
          invalid_activation_dispatch_shell(
            "array map enclosing step parameter was not retained",
          )
      }
  }
}

///|
fn array_map_enclosing_bool(
  env : Environment,
  name : String,
) -> Bool raise InvalidActivationDispatchShell {
  match env.bindings.get(name) {
    Some(binding) if binding.initialized && binding.is_parameter =>
      match binding.value {
        Bool(value) => value
        _ =>
          invalid_activation_dispatch_shell(
            "array map enclosing parameter is not boolean",
          )
      }
    _ =>
      match env.parent {
        Some(parent) => array_map_enclosing_bool(parent, name)
        None =>
          invalid_activation_dispatch_shell(
            "array map enclosing step flag was not retained",
          )
      }
  }
}

///|
priv struct ArrayMapDirectCallArguments {
  count : Double
  value : Value
  flag : Bool
}

///|
fn array_map_direct_call_arguments(
  env : Environment,
  plan : ArrayMapRecursionPlan,
) -> ArrayMapDirectCallArguments raise InvalidActivationDispatchShell {
  // Keep the source-order reads in one explicit data record.  The ordinary
  // activation request below owns the resulting values; no guest callback or
  // MoonBit closure is retained between argument evaluation and the call.
  let count = array_map_enclosing_number(env, plan.parameter_name)
  let value = Number(array_map_enclosing_number(env, plan.callback_parameter))
  let flag = array_map_enclosing_bool(env, plan.flag_parameter_name)
  { count, value, flag }
}

///|
fn array_map_direct_call_request_args(
  env : Environment,
  plan : ArrayMapRecursionPlan,
) -> Array[Value] raise InvalidActivationDispatchShell {
  let direct_args = array_map_direct_call_arguments(env, plan)
  [Number(direct_args.count - 1.0), direct_args.value, Bool(!direct_args.flag)]
}

///|
fn array_map_registry_is_stable(
  interp : Interpreter,
  registry : TrustedArrayMapRecursionRegistry,
) -> Bool {
  let step_binding_stable = match
    interp.global.bindings.get(registry.plan.function_name) {
    Some(binding) if binding.initialized =>
      array_map_value_identity_matches(binding.value, registry.step_function)
    _ => false
  }
  let forward_binding_stable = match registry.forward_function {
    None => true
    Some(forward_function) =>
      match interp.global.bindings.get(registry.plan.forward_function_name) {
        Some(binding) if binding.initialized =>
          array_map_value_identity_matches(binding.value, forward_function)
        _ => false
      }
  }
  match interp.numeric_recursion_canonical_global_object() {
    Some(global_object) if physical_equal(
        global_object,
        registry.expected_global_object,
      ) =>
      match array_map_intrinsic_values(interp) {
        Some(
          (array_constructor, array_prototype, map_method, map_method_descriptor
          )
        ) => {
          let species_stable = match
            array_map_species_snapshot(
              interp, array_prototype, array_constructor,
            ) {
            Some(actual_species) =>
              array_map_species_snapshot_matches(
                registry.expected_species,
                actual_species,
              )
            None => false
          }
          step_binding_stable &&
          forward_binding_stable &&
          array_map_value_identity_matches(
            array_constructor,
            registry.expected_array_constructor,
          ) &&
          array_map_value_identity_matches(
            array_prototype,
            registry.expected_array_prototype,
          ) &&
          array_map_value_identity_matches(
            map_method,
            registry.expected_map_method,
          ) &&
          array_map_species_descriptor_shape_matches(
            registry.expected_map_method_descriptor,
            map_method_descriptor,
          ) &&
          species_stable
        }
        None => false
      }
    _ => false
  }
}

///|
fn PrimitiveProgramDispatchShell::execute_array_map_body_statement(
  self : PrimitiveProgramDispatchShell,
  step : DispatchStatementStep,
  registry : TrustedArrayMapRecursionRegistry,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let plan = registry.plan
  guard array_map_registry_is_stable(self.interp, registry) else {
    invalid_activation_dispatch_shell(
      "array map intrinsic identity drifted after sealing",
    )
  }
  guard step.env.parent is Some(_) &&
    step.env.with_object is None &&
    step.env.is_var_scope else {
    invalid_activation_dispatch_shell(
      "array map body activation lost its lexical environment",
    )
  }
  let is_step_body = match plan.callback_family {
    ArrayMapMemberCallback =>
      match step.stmt {
        @ast.IfStmt(_, _, _, _) if step.index == 0 => true
        @ast.VarDecl(_, name, _, _) if step.index == 1 &&
          name == plan.items_name => true
        @ast.ReturnStmt(
          Some(@ast.Binary(@ast.Add, _, @ast.ComputedMember(_, _, _), _)),
          _
        ) if step.index == 2 => true
        _ => false
      }
    ArrayMapDirectCallback =>
      match step.index {
        0 =>
          match step.stmt {
            @ast.IfStmt(_, _, _, _) => true
            _ => false
          }
        1 =>
          match step.stmt {
            @ast.ReturnStmt(Some(@ast.Binary(@ast.Add, _, _, _)), _) => true
            _ => false
          }
        _ => false
      }
    ArrayMapForwardingCallback =>
      step.env.bindings.get(plan.parameter_name) is Some(binding) &&
      binding.initialized &&
      binding.is_parameter &&
      (match step.index {
        0 =>
          match step.stmt {
            @ast.IfStmt(_, _, _, _) => true
            _ => false
          }
        1 =>
          match step.stmt {
            @ast.ReturnStmt(Some(@ast.Binary(@ast.Add, _, _, _)), _) => true
            _ => false
          }
        _ => false
      })
  }
  if is_step_body {
    guard step.env.bindings.get(plan.parameter_name) is Some(binding) &&
      binding.initialized &&
      binding.is_parameter else {
      invalid_activation_dispatch_shell(
        "array map step body lost its parameter binding",
      )
    }
    guard array_map_step_statement_matches(plan, step.index, step.stmt) else {
      invalid_activation_dispatch_shell(
        "array map step body changed after sealing",
      )
    }
    let managed_step_body = match plan.callback_family {
      ArrayMapMemberCallback => step.index == 2
      ArrayMapDirectCallback => step.index == 1
      ArrayMapForwardingCallback => step.index == 1
    }
    if !managed_step_body {
      return self.execute_statement_with_legacy_adapter(step)
    }
    match self.observe_managed_execution_steps(5) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let items = match plan.callback_family {
      ArrayMapMemberCallback =>
        match step.env.bindings.get(plan.items_name) {
          Some(binding) if binding.initialized => binding.value
          _ =>
            invalid_activation_dispatch_shell(
              "array map items binding was not initialized before map",
            )
        }
      ArrayMapDirectCallback =>
        make_array([
          Number(
            array_map_enclosing_number(step.env, plan.value_parameter_name),
          ),
        ])
      ArrayMapForwardingCallback =>
        make_array([
          Number(
            array_map_enclosing_number(step.env, plan.parameter_name) - 1.0,
          ),
          Number(0.0),
        ])
    }
    guard array_map_receiver_is_exact_for_plan(
      self.interp,
      items,
      registry.expected_array_prototype,
      plan,
    ) else {
      invalid_activation_dispatch_shell(
        "array map receiver drifted from the admitted ordinary one-element array",
      )
    }
    let callback_expr = match step.stmt {
      @ast.ReturnStmt(
        Some(
          @ast.Binary(
            @ast.Add,
            _,
            @ast.ComputedMember(
              @ast.Call(@ast.Member(_, _, _), [callback], _),
              _,
              _
            ),
            _
          )
        ),
        _
      ) => callback
      _ =>
        invalid_activation_dispatch_shell(
          "array map callback expression disappeared after admission",
        )
    }
    let callback_result : Result[Value, Error] = Ok(
      self.interp.eval_expr(step.ctx, callback_expr, step.env),
    ) catch {
      error => Err(error)
    }
    let callback = match callback_result {
      Ok(value) => value
      Err(error) =>
        return DispatchWorkCompleted(dispatch_work_error_completion(error))
    }
    let length_result : Result[Int64, Error] = Ok(
      to_array_like_length_interp(items, self.interp),
    ) catch {
      error => Err(error)
    }
    let length = match length_result {
      Ok(value) => value
      Err(error) =>
        return DispatchWorkCompleted(dispatch_work_error_completion(error))
    }
    let expected_length = match plan.callback_family {
      ArrayMapForwardingCallback => 2L
      _ => 1L
    }
    guard length == expected_length else {
      invalid_activation_dispatch_shell(
        "array map receiver length changed after admission",
      )
    }
    guard is_callable(callback) else {
      invalid_activation_dispatch_shell(
        "array map callback is not callable after exact admission",
      )
    }
    guard array_map_species_snapshot(
        self.interp,
        registry.expected_array_prototype,
        registry.expected_array_constructor,
      )
      is Some(actual_species) &&
      array_map_species_snapshot_matches(
        registry.expected_species,
        actual_species,
      ) else {
      invalid_activation_dispatch_shell(
        "array map species identity drifted before ArraySpeciesCreate",
      )
    }
    let result_result : Result[Value, Error] = Ok(
      array_species_create(self.interp, items, length),
    ) catch {
      error => Err(error)
    }
    let result = match result_result {
      Ok(value) => value
      Err(error) =>
        return DispatchWorkCompleted(dispatch_work_error_completion(error))
    }
    guard result is Array(_) else {
      invalid_activation_dispatch_shell(
        "array map species result changed from an ordinary Array",
      )
    }
    let binary = DispatchBinaryResume(
      op=@ast.Add,
      left=Number(1.0),
      loc=plan.recursive_add_loc,
    )
    let state = MapState(
      length~,
      receiver=items,
      result~,
      callback~,
      this_arg=Undefined,
      pending_result_consumer=DispatchApplyPropertyBinaryRight(binary),
    )
    self.array_map_activation_envs.push(step.env)
    return DispatchWorkSuspended(
      DispatchSuspendContinueProduction(
        DispatchCompleteReturn,
        DispatchMapStart(state),
      ),
    )
  }
  if array_map_single_callback_statement_matches(
      step.stmt,
      plan.callback_parameter,
      plan.member_property_name,
    ) {
    let parameter = match step.env.bindings.get(plan.callback_parameter) {
      Some(binding) if binding.initialized && binding.is_parameter =>
        binding.value
      _ =>
        invalid_activation_dispatch_shell(
          "array map callback parameter lost its activation binding",
        )
    }
    guard parameter is Object(_) else {
      invalid_activation_dispatch_shell(
        "array map callback parameter is not the admitted member receiver",
      )
    }
    let property = DispatchPropertyGetResume(
      target=parameter,
      property_key=String_(plan.member_property_name),
      receiver=parameter,
      loc=plan.member_call_loc,
    )
    return DispatchWorkSuspended(
      DispatchSuspendContinueProduction(
        DispatchCompleteReturn,
        DispatchPropertyStart(
          property,
          DispatchMapStartMemberCall(
            DispatchMapMemberCallResume(
              receiver=parameter,
              loc=plan.member_call_loc,
            ),
          ),
        ),
      ),
    )
  }
  if plan.callback_family is ArrayMapForwardingCallback &&
    array_map_forwarding_base_statement_matches(step.stmt, plan) &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, self.interp.global) {
    return self.execute_statement_with_legacy_adapter(step)
  }
  if plan.callback_family is ArrayMapForwardingCallback &&
    array_map_forwarding_function_statement_matches(step.stmt, plan) &&
    step.env.parent is Some(parent) &&
    physical_equal(parent, self.interp.global) {
    let parameter = match step.env.bindings.get(plan.forward_parameter_name) {
      Some(binding) if binding.initialized && binding.is_parameter =>
        binding.value
      _ =>
        invalid_activation_dispatch_shell(
          "array map forwarding function parameter lost its activation binding",
        )
    }
    guard parameter is Number(_) else {
      invalid_activation_dispatch_shell(
        "array map forwarding function parameter is not numeric",
      )
    }
    match self.observe_managed_execution_steps(5) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let request = DispatchCallRequest(
      callee=registry.step_function,
      this_value=Undefined,
      args=[parameter],
      loc=plan.forward_call_loc,
    )
    return DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchCompleteReturn),
    )
  }
  if plan.callback_family is ArrayMapDirectCallback &&
    array_map_single_direct_callback_statement_matches(step.stmt, plan) {
    let args = array_map_direct_call_request_args(step.env, plan)
    match self.observe_managed_execution_steps(5) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let request = DispatchCallRequest(
      callee=registry.step_function,
      this_value=Undefined,
      args~,
      loc=plan.recursive_call_loc,
    )
    return DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchCompleteReturn),
    )
  }
  if plan.callback_family is ArrayMapForwardingCallback &&
    array_map_forwarding_callback_statement_matches(step.stmt, plan) {
    let parameter = match step.env.bindings.get(plan.callback_parameter) {
      Some(binding) if binding.initialized && binding.is_parameter =>
        binding.value
      _ =>
        invalid_activation_dispatch_shell(
          "array map forwarding callback parameter lost its activation binding",
        )
    }
    guard parameter is Number(_) else {
      invalid_activation_dispatch_shell(
        "array map forwarding callback parameter is not numeric",
      )
    }
    let forward_function = match registry.forward_function {
      Some(value) => value
      None =>
        invalid_activation_dispatch_shell(
          "array map forwarding callback lost its retained function",
        )
    }
    match self.observe_managed_execution_steps(5) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let request = DispatchCallRequest(
      callee=forward_function,
      this_value=Undefined,
      args=[parameter],
      loc=plan.forward_callback_call_loc,
    )
    return DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchCompleteReturn),
    )
  }
  if array_map_single_next_statement_matches(
      step.stmt,
      plan.function_name,
      plan.parameter_name,
    ) {
    let argument = Number(
      array_map_enclosing_number(step.env, plan.parameter_name) - 1.0,
    )
    match self.observe_managed_execution_steps(5) {
      Some(completion) => return DispatchWorkCompleted(completion)
      None => ()
    }
    let request = DispatchCallRequest(
      callee=registry.step_function,
      this_value=Undefined,
      args=[argument],
      loc=plan.recursive_call_loc,
    )
    return DispatchWorkSuspended(
      DispatchSuspendCall(request, DispatchCompleteReturn),
    )
  }
  invalid_activation_dispatch_shell(
    "array map body statement is outside the sealed callback family",
  )
}

///|
fn PrimitiveProgramDispatchShell::replace_array_map_state(
  self : PrimitiveProgramDispatchShell,
  state : MapState,
) -> Unit raise InvalidActivationDispatchShell {
  guard !self.array_map_states.is_empty() else {
    invalid_activation_dispatch_shell(
      "array map state update has no active map operation",
    )
  }
  let top = self.array_map_states[self.array_map_states.length() - 1]
  guard array_map_value_identity_matches(top.receiver, state.receiver) else {
    invalid_activation_dispatch_shell(
      "array map state receiver identity changed",
    )
  }
  guard array_map_value_identity_matches(top.result, state.result) else {
    invalid_activation_dispatch_shell("array map state result identity changed")
  }
  guard array_map_value_identity_matches(top.callback, state.callback) else {
    invalid_activation_dispatch_shell(
      "array map state callback identity changed",
    )
  }
  self.array_map_states[self.array_map_states.length() - 1] = state
}

///|
fn PrimitiveProgramDispatchShell::array_map_resume_event(
  self : PrimitiveProgramDispatchShell,
  state : MapState,
  value : Value,
) -> MapEvent raise InvalidActivationDispatchShell {
  ignore(self)
  match state.phase {
    MapAwaitingHasProperty =>
      match value {
        Bool(present) => MapHasProperty(present)
        _ =>
          invalid_activation_dispatch_shell(
            "array map HasProperty effect returned a non-boolean",
          )
      }
    MapAwaitingGet => MapGotValue(value)
    MapAwaitingCallback => MapCallbackReturned(value)
    MapAwaitingDefine => MapPropertyDefined
    _ =>
      invalid_activation_dispatch_shell(
        "array map completion arrived outside an awaiting effect",
      )
  }
}

///|
fn PrimitiveProgramDispatchShell::perform_array_map_event(
  self : PrimitiveProgramDispatchShell,
  state : MapState,
  event : MapEvent,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let reduced : Result[(MapState, MapDecision), InvalidMapTransition] = Ok(
    reduce_array_map(state, event),
  ) catch {
    error => Err(error)
  }
  let (next_state, decision) = match reduced {
    Ok(result) => result
    Err(_) =>
      invalid_activation_dispatch_shell(
        "array map reducer rejected an admitted effect acknowledgement",
      )
  }
  self.replace_array_map_state(next_state)
  self.perform_array_map_decision(next_state, decision)
}

///|
fn PrimitiveProgramDispatchShell::perform_array_map_decision(
  self : PrimitiveProgramDispatchShell,
  state : MapState,
  decision : MapDecision,
) -> DispatchEffectResult raise InvalidActivationDispatchShell {
  let registry = self.require_array_map_registry()
  match decision {
    MapRequestHasProperty(index) => {
      guard state.phase is MapAwaitingHasProperty && index == state.index else {
        invalid_activation_dispatch_shell(
          "array map HasProperty decision is not exactly once",
        )
      }
      guard array_map_receiver_is_exact_for_plan(
        self.interp,
        state.receiver,
        registry.expected_array_prototype,
        registry.plan,
      ) else {
        invalid_activation_dispatch_shell(
          "array map receiver drifted before HasProperty",
        )
      }
      let present : Result[Bool, Error] = Ok(
        has_array_like_element(self.interp, state.receiver, index),
      ) catch {
        error => Err(error)
      }
      match present {
        Ok(value) => self.perform_array_map_event(
          state,
          MapHasProperty(value),
        )
        Err(error) => self.perform_array_map_event(state, MapAbrupt(error))
      }
    }
    MapRequestGet(index) => {
      guard state.phase is MapAwaitingGet && index == state.index else {
        invalid_activation_dispatch_shell(
          "array map Get decision is not exactly once",
        )
      }
      guard array_map_receiver_is_exact_for_plan(
        self.interp,
        state.receiver,
        registry.expected_array_prototype,
        registry.plan,
      ) else {
        invalid_activation_dispatch_shell(
          "array map receiver drifted before Get",
        )
      }
      let value : Result[Value, Error] = Ok(
        get_array_like_element_interp(self.interp, state.receiver, index),
      ) catch {
        error => Err(error)
      }
      match value {
        Ok(element) => self.perform_array_map_event(state, MapGotValue(element))
        Err(error) => self.perform_array_map_event(state, MapAbrupt(error))
      }
    }
    MapRequestCallback(callback, this_arg, index, receiver, element) => {
      guard state.phase is MapAwaitingCallback &&
        index == state.index &&
        array_map_value_identity_matches(state.callback, callback) &&
        array_map_value_identity_matches(state.receiver, receiver) else {
        invalid_activation_dispatch_shell(
          "array map callback decision crossed its sealed state",
        )
      }
      let request = DispatchCallRequest(
        callee=callback,
        this_value=this_arg,
        args=[element, Number(index.to_double()), receiver],
        loc=registry.plan.callback_call_loc,
      )
      DispatchWorkSuspended(
        DispatchSuspendCall(request, DispatchContinueMap(state)),
      )
    }
    MapRequestDefine(index, value) => {
      guard state.phase is MapAwaitingDefine && index == state.index else {
        invalid_activation_dispatch_shell(
          "array map CreateDataProperty decision is not exactly once",
        )
      }
      let defined : Result[Unit, Error] = Ok(
        create_data_property_or_throw(self.interp, state.result, index, value),
      ) catch {
        error => Err(error)
      }
      match defined {
        Ok(_) => self.perform_array_map_event(state, MapPropertyDefined)
        Err(error) => self.perform_array_map_event(state, MapAbrupt(error))
      }
    }
    MapComplete(result, consumer) => {
      guard state.phase is MapCompleted &&
        array_map_value_identity_matches(state.result, result) else {
        invalid_activation_dispatch_shell(
          "array map completion was consumed more than once",
        )
      }
      set_array_like_length(result, state.length)
      let _ = self.array_map_states.pop()
      let _ = self.array_map_activation_envs.pop()
      DispatchWorkSuspended(
        DispatchSuspendContinueProduction(
          consumer,
          DispatchPropertyStart(
            DispatchPropertyGetResume(
              target=result,
              property_key=String_("0"),
              receiver=result,
              loc=registry.plan.result_member_loc,
            ),
            DispatchDeliverCallResult,
          ),
        ),
      )
    }
    MapAbort(error) => {
      guard state.phase is MapFailed else {
        invalid_activation_dispatch_shell(
          "array map abrupt completion was consumed more than once",
        )
      }
      let _ = self.array_map_states.pop()
      let _ = self.array_map_activation_envs.pop()
      DispatchWorkCompleted(dispatch_work_error_completion(error))
    }
  }
}
