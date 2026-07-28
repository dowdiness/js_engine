///|
/// PROTOTYPE fake external adapter record retained across Engine crashes only.
priv struct CachedAdapterResult {
  idempotency_key_ : String
  value_ : Json
  write_committed_ : Bool
}

///|
fn CachedAdapterResult::CachedAdapterResult(
  idempotency_key : String,
  value : Json,
  write_committed : Bool,
) -> CachedAdapterResult {
  {
    idempotency_key_: idempotency_key,
    value_: value,
    write_committed_: write_committed,
  }
}

///|
priv struct AdapterOutcome {
  value_ : Json
  write_committed_ : Bool
  cache_hit_ : Bool
}

///|
fn AdapterOutcome::AdapterOutcome(
  value : Json,
  write_committed : Bool,
  cache_hit : Bool,
) -> AdapterOutcome {
  { value_: value, write_committed_: write_committed, cache_hit_: cache_hit }
}

///|
fn AdapterOutcome::tagged_result(self : AdapterOutcome) -> Json {
  Json::object({ "tag": Json::string("ok"), "value": self.value_ })
}

///|
fn AdapterOutcome::write_committed(self : AdapterOutcome) -> Bool {
  self.write_committed_
}

///|
fn AdapterOutcome::cache_hit(self : AdapterOutcome) -> Bool {
  self.cache_hit_
}

///|
priv struct FakeAdapter {
  cache_ : Array[CachedAdapterResult]
  mut attempts_ : Int
  mut write_attempts_ : Int
  mut external_write_commits_ : Int
  mut cache_hits_ : Int
  mut reconciliation_attempts_ : Int
  mut replay_invocations_ : Int
}

///|
fn FakeAdapter::FakeAdapter() -> FakeAdapter {
  {
    cache_: [],
    attempts_: 0,
    write_attempts_: 0,
    external_write_commits_: 0,
    cache_hits_: 0,
    reconciliation_attempts_: 0,
    replay_invocations_: 0,
  }
}

///|
fn invocation_user_id(invocation : @broker.AdapterInvocation) -> String {
  match invocation.arguments() {
    Json::Object(fields) =>
      match fields.get("user_id") {
        Some(Json::String(user_id)) => user_id
        _ => abort("PROTOTYPE invariant: validated invocation lacks user_id")
      }
    _ => abort("PROTOTYPE invariant: validated invocation lacks arguments")
  }
}

///|
fn FakeAdapter::execute(
  self : FakeAdapter,
  invocation : @broker.AdapterInvocation,
  mode : String,
) -> AdapterOutcome {
  guard mode == "live" || mode == "reconcile" || mode == "replay" else {
    abort("PROTOTYPE invariant: unknown adapter execution mode")
  }
  self.attempts_ += 1
  if invocation.effect_class() == "Write" {
    self.write_attempts_ += 1
  }
  if mode == "reconcile" {
    self.reconciliation_attempts_ += 1
  } else if mode == "replay" {
    self.replay_invocations_ += 1
  }
  for cached in self.cache_ {
    if cached.idempotency_key_ == invocation.idempotency_key() {
      self.cache_hits_ += 1
      return AdapterOutcome(cached.value_, cached.write_committed_, true)
    }
  }
  let user_id = invocation_user_id(invocation)
  let value = match invocation.tool() {
    "get_user" =>
      Json::object({
        "user_id": Json::string(user_id),
        "status": Json::string(
          if user_id == "user-active" {
            "active"
          } else {
            "inactive"
          },
        ),
      })
    "update_user_status" =>
      Json::object({
        "user_id": Json::string(user_id),
        "status": Json::string("active"),
      })
    _ => abort("PROTOTYPE invariant: fake adapter received unknown tool")
  }
  let write_committed = invocation.effect_class() == "Write"
  if write_committed {
    self.external_write_commits_ += 1
  }
  self.cache_.push(
    CachedAdapterResult(invocation.idempotency_key(), value, write_committed),
  )
  AdapterOutcome(value, write_committed, false)
}

///|
fn FakeAdapter::render(self : FakeAdapter) -> Json {
  Json::object({
    "adapter_attempts": Json::number(
      self.attempts_.to_double(),
      repr=self.attempts_.to_string(),
    ),
    "write_attempts": Json::number(
      self.write_attempts_.to_double(),
      repr=self.write_attempts_.to_string(),
    ),
    "fake_external_write_commits": Json::number(
      self.external_write_commits_.to_double(),
      repr=self.external_write_commits_.to_string(),
    ),
    "idempotency_cache_hits": Json::number(
      self.cache_hits_.to_double(),
      repr=self.cache_hits_.to_string(),
    ),
    "reconciliation_attempts": Json::number(
      self.reconciliation_attempts_.to_double(),
      repr=self.reconciliation_attempts_.to_string(),
    ),
    "replay_adapter_invocations": Json::number(
      self.replay_invocations_.to_double(),
      repr=self.replay_invocations_.to_string(),
    ),
    "idempotency_records": Json::number(
      self.cache_.length().to_double(),
      repr=self.cache_.length().to_string(),
    ),
  })
}

///|
fn FakeAdapter::external_write_commits(self : FakeAdapter) -> Int {
  self.external_write_commits_
}

///|
fn FakeAdapter::replay_invocations(self : FakeAdapter) -> Int {
  self.replay_invocations_
}
