// Private queue-policy core for timer and interval dispatch.
// It owns queue selection and bookkeeping transitions, but never invokes the
// JavaScript callback stored in a TimerTask.

///|
const TIMER_SAFETY_LIMIT = 10000

///|
priv enum TimerQueuePolicyPhase {
  TimerQueueReady
  TimerQueueSelected(TimerTask)
  TimerQueueCallbackSucceeded(TimerTask)
  TimerQueueFailed
  TimerQueueCompleted
}

///|
priv struct TimerQueuePolicy {
  queue : @priority_queue.PriorityQueue[TimerTask]
  cancelled_timer_ids : Map[Int, Bool]
  insertion_counter : Ref[Int]
  safety_limit : Int
  mut iterations : Int
  mut phase : TimerQueuePolicyPhase
}

///|
fn TimerQueuePolicy::TimerQueuePolicy(
  queue : @priority_queue.PriorityQueue[TimerTask],
  cancelled_timer_ids : Map[Int, Bool],
  insertion_counter : Ref[Int],
  safety_limit : Int,
) -> TimerQueuePolicy {
  {
    queue,
    cancelled_timer_ids,
    insertion_counter,
    safety_limit,
    iterations: 0,
    phase: TimerQueueReady,
  }
}

///|
fn[T] invalid_timer_queue_policy_transition(operation : String) -> T raise {
  fail("invalid timer queue policy transition: " + operation)
}

///|
fn TimerQueuePolicy::select_next(self : TimerQueuePolicy) -> TimerTask? raise {
  match self.phase {
    TimerQueueReady => ()
    TimerQueueSelected(_)
    | TimerQueueCallbackSucceeded(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition("select_next requires Ready")
  }
  while self.iterations < self.safety_limit && !self.queue.is_empty() {
    self.iterations = self.iterations + 1
    let timer = match self.queue.pop() {
      Some(timer) => timer
      None =>
        invalid_timer_queue_policy_transition(
          "select_next requires a non-empty queue",
        )
    }
    if self.cancelled_timer_ids.contains(timer.id) {
      continue
    }
    self.phase = TimerQueueSelected(timer)
    return Some(timer)
  }
  None
}

///|
fn TimerQueuePolicy::callback_succeeded(self : TimerQueuePolicy) -> Unit raise {
  match self.phase {
    TimerQueueSelected(timer) => self.phase = TimerQueueCallbackSucceeded(timer)
    TimerQueueReady
    | TimerQueueCallbackSucceeded(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition(
        "callback_succeeded requires Selected",
      )
  }
}

///|
fn TimerQueuePolicy::callback_failed(self : TimerQueuePolicy) -> Unit raise {
  match self.phase {
    TimerQueueSelected(_) => self.phase = TimerQueueFailed
    TimerQueueReady
    | TimerQueueCallbackSucceeded(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition("callback_failed requires Selected")
  }
}

///|
fn TimerQueuePolicy::checkpoint_succeeded(
  self : TimerQueuePolicy,
) -> Unit raise {
  let timer = match self.phase {
    TimerQueueCallbackSucceeded(timer) => timer
    TimerQueueReady
    | TimerQueueSelected(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition(
        "checkpoint_succeeded requires CallbackSucceeded",
      )
  }
  if timer.is_interval && !self.cancelled_timer_ids.contains(timer.id) {
    let order = self.insertion_counter.val
    self.insertion_counter.val = order + 1
    self.queue.push({
      id: timer.id,
      callback: timer.callback,
      args: timer.args,
      delay: timer.delay + timer.period,
      period: timer.period,
      is_interval: true,
      insertion_order: order,
    })
  }
  self.phase = TimerQueueReady
}

///|
fn TimerQueuePolicy::checkpoint_failed(self : TimerQueuePolicy) -> Unit raise {
  match self.phase {
    TimerQueueCallbackSucceeded(_) => self.phase = TimerQueueFailed
    TimerQueueReady
    | TimerQueueSelected(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition(
        "checkpoint_failed requires CallbackSucceeded",
      )
  }
}

///|
fn TimerQueuePolicy::complete_run(self : TimerQueuePolicy) -> Unit raise {
  match self.phase {
    TimerQueueReady => ()
    TimerQueueSelected(_)
    | TimerQueueCallbackSucceeded(_)
    | TimerQueueFailed
    | TimerQueueCompleted =>
      invalid_timer_queue_policy_transition("complete_run requires Ready")
  }
  if self.queue.is_empty() {
    self.cancelled_timer_ids.clear()
  }
  self.phase = TimerQueueCompleted
}
