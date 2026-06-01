///|
extern "js" fn _builtin_setup_profile_now_ms() -> Double =
  #|() => performance.now()

///|
fn builtin_setup_profile_now_ms() -> Double {
  _builtin_setup_profile_now_ms()
}
