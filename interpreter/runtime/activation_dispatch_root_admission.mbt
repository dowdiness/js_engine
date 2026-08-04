// Closed, effect-free root admission for the exact #630 production slices.
// Recipe-specific plans remain private to the runtime package.

///|
#warnings("-unused_constructor-unused_field")
priv enum ActivationDispatchManagedRoot {
  ActivationDispatchLeafRoot
  ActivationDispatchControlRoot(ControlLifecyclePreflight)
  ActivationDispatchConstructorRoot(ConstructorRecursionPreflight)
  ActivationDispatchArrayMapRoot(ArrayMapRecursionPreflight)
  ActivationDispatchNumericRoot(NumericRecursionPreflight)
  ActivationDispatchGetterRoot(GetterRecursionPreflight)
  ActivationDispatchProxyRoot(ProxyGetRecursionPreflight)
  ActivationDispatchReceiverRoot(ReceiverRecursionPreflight)
  ActivationDispatchMutualReceiverRoot(MutualReceiverRecursionPreflight)
}

///|
priv enum ActivationDispatchRootAdmission {
  ActivationDispatchManagedRoot(ActivationDispatchManagedRoot)
  ActivationDispatchLegacyRoot
}

///|
fn Interpreter::classify_activation_dispatch_root_program(
  self : Interpreter,
  stmts : Array[@ast.Stmt],
) -> ActivationDispatchRootAdmission {
  if activation_dispatch_leaf_program_is_admissible(stmts) {
    ActivationDispatchManagedRoot(ActivationDispatchLeafRoot)
  } else {
    match preflight_control_lifecycle_program(stmts) {
      Some(preflight) =>
        ActivationDispatchManagedRoot(ActivationDispatchControlRoot(preflight))
      None =>
        match self.preflight_dispatchable_constructor_recursion_program(stmts) {
          Some(preflight) =>
            ActivationDispatchManagedRoot(
              ActivationDispatchConstructorRoot(preflight),
            )
          None =>
            match
              self.preflight_dispatchable_array_map_recursion_program(stmts) {
              Some(preflight) =>
                ActivationDispatchManagedRoot(
                  ActivationDispatchArrayMapRoot(preflight),
                )
              None =>
                match
                  self.preflight_dispatchable_numeric_recursion_program(stmts) {
                  Some(preflight) =>
                    ActivationDispatchManagedRoot(
                      ActivationDispatchNumericRoot(preflight),
                    )
                  None =>
                    match
                      self.preflight_dispatchable_getter_recursion_program(
                        stmts,
                      ) {
                      Some(preflight) =>
                        ActivationDispatchManagedRoot(
                          ActivationDispatchGetterRoot(preflight),
                        )
                      None =>
                        match
                          self.preflight_dispatchable_proxy_get_recursion_program(
                            stmts,
                          ) {
                          Some(preflight) =>
                            ActivationDispatchManagedRoot(
                              ActivationDispatchProxyRoot(preflight),
                            )
                          None =>
                            match
                              self.preflight_dispatchable_mutual_receiver_recursion_program(
                                stmts,
                              ) {
                              Some(preflight) =>
                                ActivationDispatchManagedRoot(
                                  ActivationDispatchMutualReceiverRoot(
                                    preflight,
                                  ),
                                )
                              None =>
                                match
                                  self.preflight_dispatchable_receiver_recursion_program(
                                    stmts,
                                  ) {
                                  Some(preflight) =>
                                    ActivationDispatchManagedRoot(
                                      ActivationDispatchReceiverRoot(preflight),
                                    )
                                  None => ActivationDispatchLegacyRoot
                                }
                            }
                        }
                    }
                }
            }
        }
    }
  }
}
