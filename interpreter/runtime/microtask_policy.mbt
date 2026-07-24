// Private queue-policy core for at-most-once microtask dispatch.
// It consumes jobs by FIFO position before callback execution, but never
// inspects or invokes the JavaScript callback stored in a Microtask.

///|
priv enum MicrotaskQueuePolicyPhase {
  MicrotaskQueueReady
  MicrotaskQueueSelected
  MicrotaskQueueFailed
  MicrotaskQueueCompleted
}

///|
priv struct MicrotaskQueuePolicy {
  queue : Array[Microtask]
  mut next_index : Int
  mut phase : MicrotaskQueuePolicyPhase
}

///|
fn MicrotaskQueuePolicy::MicrotaskQueuePolicy(
  queue : Array[Microtask],
) -> MicrotaskQueuePolicy {
  { queue, next_index: 0, phase: MicrotaskQueueReady }
}

///|
fn microtask_policy_enqueue(queue : Array[Microtask], job : Microtask) -> Unit {
  queue.push(job)
}

///|
fn[T] invalid_microtask_policy_transition(operation : String) -> T raise {
  fail("invalid microtask policy transition: " + operation)
}

///|
fn MicrotaskQueuePolicy::select_next(
  self : MicrotaskQueuePolicy,
) -> Microtask? raise {
  match self.phase {
    MicrotaskQueueReady => {
      guard self.next_index < self.queue.length() else { return None }
      let task = self.queue[self.next_index]
      self.next_index = self.next_index + 1
      self.phase = MicrotaskQueueSelected
      Some(task)
    }
    MicrotaskQueueSelected | MicrotaskQueueFailed | MicrotaskQueueCompleted =>
      invalid_microtask_policy_transition("select_next requires Ready")
  }
}

///|
fn MicrotaskQueuePolicy::complete_selected(
  self : MicrotaskQueuePolicy,
) -> Unit raise {
  guard self.phase is MicrotaskQueueSelected else {
    invalid_microtask_policy_transition("complete_selected requires Selected")
  }
  self.phase = MicrotaskQueueReady
}

///|
fn MicrotaskQueuePolicy::fail_selected(
  self : MicrotaskQueuePolicy,
) -> Unit raise {
  guard self.phase is MicrotaskQueueSelected else {
    invalid_microtask_policy_transition("fail_selected requires Selected")
  }
  let remaining = self.queue.length() - self.next_index
  self.queue[self.next_index:].blit_to(self.queue)
  self.queue.truncate(remaining)
  self.phase = MicrotaskQueueFailed
}

///|
fn MicrotaskQueuePolicy::complete_drain(
  self : MicrotaskQueuePolicy,
) -> Unit raise {
  guard self.phase is MicrotaskQueueReady else {
    invalid_microtask_policy_transition("complete_drain requires Ready")
  }
  guard self.next_index >= self.queue.length() else {
    invalid_microtask_policy_transition(
      "complete_drain requires an exhausted queue",
    )
  }
  self.queue.clear()
  self.phase = MicrotaskQueueCompleted
}
