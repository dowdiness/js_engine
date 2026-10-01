///|
/// Number::exponentiate keeps ECMAScript's historical NaN results where
/// IEEE 754 pow (and @math.pow) returns 1 for unit bases.
pub fn number_exponentiate(base : Double, exponent : Double) -> Double {
  if exponent.is_nan() || (base.abs() == 1.0 && exponent.is_inf()) {
    0.0 / 0.0
  } else {
    @math.pow(base, exponent)
  }
}
