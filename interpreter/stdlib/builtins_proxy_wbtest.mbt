///| Whitebox tests for Proxy builtin setup.

///|
fn proxy_revocable_func(env : @runtime.Environment) -> Value {
  let proxy = env.get("Proxy") catch {
    err => fail("expected Proxy in env: " + err.to_string())
  }
  match proxy {
    Object(data) =>
      match data.bag.properties.get("revocable") {
        Some(f) => f
        None => fail("expected Proxy.revocable property")
      }
    _ => fail("expected Proxy to be an Object")
  }
}

///|
test "Proxy.revocable: throws TypeError with zero args" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  match @runtime.call_callable_direct(revocable, Undefined, []) {
    _ => fail("expected TypeError")
  } catch {
    err =>
      inspect(
        err.to_string(),
        content="TypeError: Cannot create proxy with a non-object as target or handler",
      )
  }
}

///|
test "Proxy.revocable: throws TypeError with one arg" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  let obj = @runtime.make_plain_object()
  match @runtime.call_callable_direct(revocable, Undefined, [obj]) {
    _ => fail("expected TypeError")
  } catch {
    err =>
      inspect(
        err.to_string(),
        content="TypeError: Cannot create proxy with a non-object as target or handler",
      )
  }
}

///|
test "Proxy.revocable: throws TypeError when target is a number" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  let obj = @runtime.make_plain_object()
  match
    @runtime.call_callable_direct(
      revocable,
      Undefined,
      [Value::Number(1.0), obj],
    ) {
    _ => fail("expected TypeError")
  } catch {
    err =>
      inspect(
        err.to_string(),
        content="TypeError: Cannot create proxy with a non-object as target or handler",
      )
  }
}

///|
test "Proxy.revocable: throws TypeError when handler is a string" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  let obj = @runtime.make_plain_object()
  match
    @runtime.call_callable_direct(
      revocable,
      Undefined,
      [obj, Value::String_("not an object")],
    ) {
    _ => fail("expected TypeError")
  } catch {
    err =>
      inspect(
        err.to_string(),
        content="TypeError: Cannot create proxy with a non-object as target or handler",
      )
  }
}

///|
test "Proxy.revocable: returns object with proxy and revoke properties" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  let target = @runtime.make_plain_object()
  let handler = @runtime.make_plain_object()
  let result = @runtime.call_callable_direct(
    revocable,
    Undefined,
    [target, handler],
  ) catch {
    err => fail("expected result object, got error: " + err.to_string())
  }
  match result {
    Object(data) => {
      match data.bag.properties.get("proxy") {
        Some(Proxy(_)) => ()
        Some(other) => fail("expected proxy property to be Proxy, got \{other}")
        None => fail("expected proxy property on result")
      }
      match data.bag.properties.get("revoke") {
        Some(Object(_)) => ()
        Some(other) => fail("expected revoke to be a function object, got \{other}")
        None => fail("expected revoke property on result")
      }
    }
    _ => fail("expected result to be an Object")
  }
}

///|
test "Proxy.revocable: revoke function nullifies the proxy" {
  let env = @runtime.Environment::new()
  setup_proxy_builtins(env)
  let revocable = proxy_revocable_func(env)
  let target = @runtime.make_plain_object()
  let handler = @runtime.make_plain_object()
  let result = @runtime.call_callable_direct(
    revocable,
    Undefined,
    [target, handler],
  ) catch {
    err => fail("setup failed: " + err.to_string())
  }
  let revoke_fn = match result {
    Object(data) =>
      match data.bag.properties.get("revoke") {
        Some(f) => f
        None => fail("expected revoke property")
      }
    _ => fail("expected Object result")
  }
  let proxy_val = match result {
    Object(data) =>
      match data.bag.properties.get("proxy") {
        Some(p) => p
        None => fail("expected proxy property")
      }
    _ => fail("expected Object result")
  }
  // Before revoke: proxy should have live target/handler
  match proxy_val {
    Proxy({ target: Some(_), handler: Some(_), .. }) => ()
    _ => fail("expected live proxy before revoke")
  }
  // Invoke revoke
  let _ = @runtime.call_callable_direct(revoke_fn, Undefined, []) catch {
    err => fail("revoke() failed: " + err.to_string())
  }
  // After revoke: target and handler should be None
  match proxy_val {
    Proxy({ target: None, handler: None, .. }) => ()
    Proxy({ target, handler, .. }) =>
      fail("expected revoked proxy, got target=\{target} handler=\{handler}")
    _ => fail("expected Proxy value")
  }
}
