///|
priv enum OwnedReceiverCall {
  OwnedFixedReceiverCall(TrustedReceiverRecursionRegistry)
  OwnedChangingReceiverCall(TrustedChangingReceiverRegistry)
  OwnedMutualReceiverCall(TrustedMutualReceiverRecursionRegistry)
}

///|
priv struct OwnedReceiverCallValidation {
  data : FuncData
  throw_type_error : Value?
}

///|
fn owned_fixed_receiver_call(
  registry : TrustedReceiverRecursionRegistry,
) -> OwnedReceiverCall {
  OwnedFixedReceiverCall(registry)
}

///|
fn owned_changing_receiver_call(
  registry : TrustedChangingReceiverRegistry,
) -> OwnedReceiverCall {
  OwnedChangingReceiverCall(registry)
}

///|
fn owned_mutual_receiver_call(
  registry : TrustedMutualReceiverRecursionRegistry,
) -> OwnedReceiverCall {
  OwnedMutualReceiverCall(registry)
}

///|
fn OwnedReceiverCall::validate_call(
  self : OwnedReceiverCall,
  interp : Interpreter,
  request : DispatchCallRequest,
) -> OwnedReceiverCallValidation raise InvalidActivationDispatchShell {
  let throw_type_error = match self {
    OwnedFixedReceiverCall(registry) => {
      guard request.loc == registry.plan.recipe.root_member_loc ||
        request.loc == registry.plan.recipe.recursive_call_loc else {
        invalid_activation_dispatch_shell(
          "receiver activation call location escaped the sealed syntax recipe",
        )
      }
      let _ = registry.require_call(
        interp,
        request.callee,
        request.this_value,
        request.args,
      )
      guard request.args.length() == 1 else {
        invalid_activation_dispatch_shell(
          "receiver activation requires exactly one argument",
        )
      }
      registry.throw_type_error
    }
    OwnedChangingReceiverCall(registry) => {
      guard request.loc == registry.root_call_loc ||
        request.loc == registry.function.plan.recursive_call_loc else {
        invalid_activation_dispatch_shell(
          "changing-receiver call location escaped the lowered plan",
        )
      }
      let _ = registry.require_call(
        interp,
        request.callee,
        request.this_value,
        request.args,
      )
      guard request.args.length() == 1 else {
        invalid_activation_dispatch_shell(
          "receiver activation requires exactly one argument",
        )
      }
      registry.throw_type_error
    }
    OwnedMutualReceiverCall(registry) => {
      let _ = registry.require_call(
        interp,
        request.callee,
        request.this_value,
        request.args,
        request.loc,
      )
      guard request.args.length() == 1 else {
        invalid_activation_dispatch_shell(
          "mutual receiver activation requires exactly one argument",
        )
      }
      registry.throw_type_error
    }
  }
  guard request.callee is Object(callee_object) &&
    callee_object.callable is Some(UserFunc(data)) else {
    invalid_activation_dispatch_shell(
      "receiver activation lost its exact UserFunc provenance",
    )
  }
  { data, throw_type_error }
}
