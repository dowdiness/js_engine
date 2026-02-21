///|
/// Date built-in object implementation
/// Implements the ECMAScript Date object with constructor, prototype methods, and static methods.
/// Internal representation: [[DateValue]] property stores milliseconds since Unix epoch as Double.
/// NaN represents an invalid date.

// ============================================================
// Date utility constants and helpers
// ============================================================

///|
/// Milliseconds per time unit
let ms_per_second : Double = 1000.0

///|
let ms_per_minute : Double = 60000.0

///|
let ms_per_hour : Double = 3600000.0

///|
let ms_per_day : Double = 86400000.0

///|
/// Number of days from epoch (1970-01-01) to the given time value
fn day(t : Double) -> Double {
  (t / ms_per_day).floor()
}

///|
/// Milliseconds within the day
fn time_within_day(t : Double) -> Double {
  let r = t % ms_per_day
  if r < 0.0 {
    r + ms_per_day
  } else {
    r
  }
}

///|
/// Number of days in a year
fn days_in_year(y : Int) -> Int {
  if y % 4 != 0 {
    365
  } else if y % 100 != 0 {
    366
  } else if y % 400 != 0 {
    365
  } else {
    366
  }
}

///|
/// Day number of the first day of year y
fn day_from_year(y : Int) -> Double {
  // Division must use floor (not truncation) per ES spec, so compute in
  // floating-point where .floor() gives correct results for negative values.
  let yd = (y - 1970).to_double()
  365.0 * yd +
  ((y - 1969).to_double() / 4.0).floor() -
  ((y - 1901).to_double() / 100.0).floor() +
  ((y - 1601).to_double() / 400.0).floor()
}

///|
/// Year from time value
fn year_from_time(t : Double) -> Int {
  let d = day(t)
  // Approximate year from average days per year
  let mut y = (d / 365.2425 + 1970.0).to_int()
  // Adjust upward if needed
  while day_from_year(y + 1) <= d {
    y = y + 1
  }
  // Adjust downward if needed
  while day_from_year(y) > d {
    y = y - 1
  }
  y
}

///|
/// Whether a year is a leap year
fn is_leap_year(y : Int) -> Bool {
  days_in_year(y) == 366
}

///|
/// Day within the year (0-based)
fn day_within_year(t : Double) -> Int {
  let y = year_from_time(t)
  (day(t) - day_from_year(y)).to_int()
}

///|
/// Month from time (0-based: 0=Jan, 11=Dec)
fn month_from_time(t : Double) -> Int {
  let dwy = day_within_year(t)
  let y = year_from_time(t)
  let leap = if is_leap_year(y) { 1 } else { 0 }
  if dwy < 31 {
    0 // Jan
  } else if dwy < 59 + leap {
    1 // Feb
  } else if dwy < 90 + leap {
    2 // Mar
  } else if dwy < 120 + leap {
    3 // Apr
  } else if dwy < 151 + leap {
    4 // May
  } else if dwy < 181 + leap {
    5 // Jun
  } else if dwy < 212 + leap {
    6 // Jul
  } else if dwy < 243 + leap {
    7 // Aug
  } else if dwy < 273 + leap {
    8 // Sep
  } else if dwy < 304 + leap {
    9 // Oct
  } else if dwy < 334 + leap {
    10 // Nov
  } else {
    11 // Dec
  }
}

///|
/// Day of month from time (1-based)
fn date_from_time(t : Double) -> Int {
  let dwy = day_within_year(t)
  let y = year_from_time(t)
  let leap = if is_leap_year(y) { 1 } else { 0 }
  let m = month_from_time(t)
  match m {
    0 => dwy + 1
    1 => dwy - 30
    2 => dwy - 58 - leap
    3 => dwy - 89 - leap
    4 => dwy - 119 - leap
    5 => dwy - 150 - leap
    6 => dwy - 180 - leap
    7 => dwy - 211 - leap
    8 => dwy - 242 - leap
    9 => dwy - 272 - leap
    10 => dwy - 303 - leap
    _ => dwy - 333 - leap
  }
}

///|
/// Day of week (0=Sun, 6=Sat)
fn week_day(t : Double) -> Int {
  let r = (day(t) + 4.0) % 7.0
  let d = if r < 0.0 { r + 7.0 } else { r }
  d.to_int()
}

///|
/// Hours from time
fn hours_from_time(t : Double) -> Int {
  let r = (time_within_day(t) / ms_per_hour).floor()
  r.to_int()
}

///|
/// Minutes from time
fn minutes_from_time(t : Double) -> Int {
  let r = (time_within_day(t) / ms_per_minute).floor() % 60.0
  r.to_int()
}

///|
/// Seconds from time
fn seconds_from_time(t : Double) -> Int {
  let r = (time_within_day(t) / ms_per_second).floor() % 60.0
  r.to_int()
}

///|
/// Milliseconds from time
fn millis_from_time(t : Double) -> Int {
  let r = time_within_day(t) % ms_per_second
  r.to_int()
}

///|
/// Make a time value from components (all in UTC)
fn make_time(hour : Double, min : Double, sec : Double, ms : Double) -> Double {
  if hour.is_nan() || min.is_nan() || sec.is_nan() || ms.is_nan() {
    return 0.0 / 0.0
  }
  let h = hour.to_int().to_double()
  let m = min.to_int().to_double()
  let s = sec.to_int().to_double()
  let milli = ms.to_int().to_double()
  h * ms_per_hour + m * ms_per_minute + s * ms_per_second + milli
}

///|
/// Cumulative days before month (0-based month, accounting for leap year)
fn day_of_month_start(month : Int, leap : Bool) -> Int {
  let leap_offset = if leap { 1 } else { 0 }
  match month {
    0 => 0
    1 => 31
    2 => 59 + leap_offset
    3 => 90 + leap_offset
    4 => 120 + leap_offset
    5 => 151 + leap_offset
    6 => 181 + leap_offset
    7 => 212 + leap_offset
    8 => 243 + leap_offset
    9 => 273 + leap_offset
    10 => 304 + leap_offset
    _ => 334 + leap_offset
  }
}

///|
/// Make a day value from year, month, date
fn make_day(year : Double, month : Double, date : Double) -> Double {
  if year.is_nan() || month.is_nan() || date.is_nan() {
    return 0.0 / 0.0
  }
  if year.is_inf() || month.is_inf() || date.is_inf() {
    return 0.0 / 0.0
  }
  let y = year.to_int()
  let m = month.to_int()
  // Adjust year and month for months outside 0-11
  let adj_year = y + m / 12
  let adj_month = m % 12
  let final_month = if adj_month < 0 { adj_month + 12 } else { adj_month }
  let final_year = if adj_month < 0 { adj_year - 1 } else { adj_year }
  let yd = day_from_year(final_year)
  let md = day_of_month_start(final_month, is_leap_year(final_year))
  yd + md.to_double() + date - 1.0
}

///|
/// Make a date value from day and time
fn make_date_value(day : Double, time : Double) -> Double {
  if day.is_nan() || time.is_nan() {
    return 0.0 / 0.0
  }
  day * ms_per_day + time
}

///|
/// Clamp time value to valid range per ES spec TimeClip
fn time_clip(time : Double) -> Double {
  if time.is_nan() || time.is_inf() {
    return 0.0 / 0.0
  }
  if time.abs() > 8640000000000000.0 {
    return 0.0 / 0.0
  }
  // Truncate toward zero (don't go through int which would overflow for large timestamps)
  if time >= 0.0 {
    time.floor()
  } else {
    time.ceil()
  }
}

///|
/// Zero-pad a number to specified width
fn pad_number(n : Int, width : Int) -> String {
  let s = n.abs().to_string()
  let buf = StringBuilder::new()
  if n < 0 {
    buf.write_string("-")
  }
  for _i = 0; _i < width - s.length(); _i = _i + 1 {
    buf.write_char('0')
  }
  buf.write_string(s)
  buf.to_string()
}

///|
/// Day-of-week name abbreviation
fn day_name(wd : Int) -> String {
  match wd {
    0 => "Sun"
    1 => "Mon"
    2 => "Tue"
    3 => "Wed"
    4 => "Thu"
    5 => "Fri"
    _ => "Sat"
  }
}

///|
/// Month name abbreviation
fn month_name(m : Int) -> String {
  match m {
    0 => "Jan"
    1 => "Feb"
    2 => "Mar"
    3 => "Apr"
    4 => "May"
    5 => "Jun"
    6 => "Jul"
    7 => "Aug"
    8 => "Sep"
    9 => "Oct"
    10 => "Nov"
    _ => "Dec"
  }
}

///|
/// Format date as toString() result: "Sat Jan 01 2000 00:00:00 GMT+0000"
fn date_to_string(t : Double) -> String {
  if t.is_nan() {
    return "Invalid Date"
  }
  let wd = week_day(t)
  let y = year_from_time(t)
  let m = month_from_time(t)
  let d = date_from_time(t)
  let h = hours_from_time(t)
  let min = minutes_from_time(t)
  let sec = seconds_from_time(t)
  let year_str = if y >= 0 && y <= 9999 {
    pad_number(y, 4)
  } else if y >= 0 {
    "+" + pad_number(y, 6)
  } else {
    "-" + pad_number(-y, 6)
  }
  day_name(wd) +
  " " +
  month_name(m) +
  " " +
  pad_number(d, 2) +
  " " +
  year_str +
  " " +
  pad_number(h, 2) +
  ":" +
  pad_number(min, 2) +
  ":" +
  pad_number(sec, 2) +
  " GMT+0000"
}

///|
/// Format as toDateString(): "Sat Jan 01 2000"
fn date_to_date_string(t : Double) -> String {
  if t.is_nan() {
    return "Invalid Date"
  }
  let wd = week_day(t)
  let y = year_from_time(t)
  let m = month_from_time(t)
  let d = date_from_time(t)
  let year_str = if y >= 0 && y <= 9999 {
    pad_number(y, 4)
  } else if y >= 0 {
    "+" + pad_number(y, 6)
  } else {
    "-" + pad_number(-y, 6)
  }
  day_name(wd) + " " + month_name(m) + " " + pad_number(d, 2) + " " + year_str
}

///|
/// Format as toTimeString(): "00:00:00 GMT+0000"
fn date_to_time_string(t : Double) -> String {
  if t.is_nan() {
    return "Invalid Date"
  }
  let h = hours_from_time(t)
  let min = minutes_from_time(t)
  let sec = seconds_from_time(t)
  pad_number(h, 2) +
  ":" +
  pad_number(min, 2) +
  ":" +
  pad_number(sec, 2) +
  " GMT+0000"
}

///|
/// Format as toISOString(): "2000-01-01T00:00:00.000Z"
fn date_to_iso_string(t : Double) -> String raise Error {
  if t.is_nan() {
    raise @errors.RangeError(message="Invalid time value")
  }
  let y = year_from_time(t)
  let m = month_from_time(t)
  let d = date_from_time(t)
  let h = hours_from_time(t)
  let min = minutes_from_time(t)
  let sec = seconds_from_time(t)
  let ms = millis_from_time(t)
  let year_str = if y >= 0 && y <= 9999 {
    pad_number(y, 4)
  } else if y >= 0 {
    "+" + pad_number(y, 6)
  } else {
    "-" + pad_number(-y, 6)
  }
  year_str +
  "-" +
  pad_number(m + 1, 2) +
  "-" +
  pad_number(d, 2) +
  "T" +
  pad_number(h, 2) +
  ":" +
  pad_number(min, 2) +
  ":" +
  pad_number(sec, 2) +
  "." +
  pad_number(ms, 3) +
  "Z"
}

///|
/// Format as toUTCString(): "Sat, 01 Jan 2000 00:00:00 GMT"
fn date_to_utc_string(t : Double) -> String {
  if t.is_nan() {
    return "Invalid Date"
  }
  let wd = week_day(t)
  let y = year_from_time(t)
  let m = month_from_time(t)
  let d = date_from_time(t)
  let h = hours_from_time(t)
  let min = minutes_from_time(t)
  let sec = seconds_from_time(t)
  let year_str = if y >= 0 && y <= 9999 {
    pad_number(y, 4)
  } else if y >= 0 {
    "+" + pad_number(y, 6)
  } else {
    "-" + pad_number(-y, 6)
  }
  day_name(wd) +
  ", " +
  pad_number(d, 2) +
  " " +
  month_name(m) +
  " " +
  year_str +
  " " +
  pad_number(h, 2) +
  ":" +
  pad_number(min, 2) +
  ":" +
  pad_number(sec, 2) +
  " GMT"
}

///|
/// Parse an ISO 8601 date string (simplified for common formats)
/// Returns NaN for unparseable strings
fn parse_date_string(s : String) -> Double {
  // Trim whitespace from both ends
  let s_chars = s.to_array()
  let mut trim_start = 0
  while trim_start < s_chars.length() {
    let c = s_chars[trim_start]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      trim_start = trim_start + 1
    } else {
      break
    }
  }
  let mut trim_end = s_chars.length()
  while trim_end > trim_start {
    let c = s_chars[trim_end - 1]
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      trim_end = trim_end - 1
    } else {
      break
    }
  }
  let buf = StringBuilder::new()
  for i = trim_start; i < trim_end; i = i + 1 {
    buf.write_char(s_chars[i])
  }
  let trimmed = buf.to_string()
  if trimmed.length() == 0 {
    return 0.0 / 0.0
  }
  // Try ISO 8601 format: YYYY-MM-DDTHH:mm:ss.sssZ
  let chars = trimmed.to_array()
  let len = chars.length()

  // Try to parse as ISO format
  let result = parse_iso_date(chars, len)
  if not(result.is_nan()) {
    return result
  }
  // Unable to parse
  0.0 / 0.0
}

///|
/// Parse ISO 8601 date format
fn parse_iso_date(chars : Array[Char], len : Int) -> Double {
  // Minimum: YYYY (4 chars)
  if len < 4 {
    return 0.0 / 0.0
  }
  let mut pos = 0
  let mut sign = 1

  // Check for leading sign (+/-)
  if chars[0] == '+' {
    pos = 1
  } else if chars[0] == '-' {
    sign = -1
    pos = 1
  }

  // Parse year
  let year_start = pos
  while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
    pos = pos + 1
  }
  if pos == year_start {
    return 0.0 / 0.0
  }
  let year = parse_int_from_chars(chars, year_start, pos) * sign
  let mut month = 1
  let mut day_val = 1
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  let mut ms = 0

  // Parse month
  if pos < len && chars[pos] == '-' {
    pos = pos + 1
    let start = pos
    while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
      pos = pos + 1
    }
    if pos > start {
      month = parse_int_from_chars(chars, start, pos)
    }
  }

  // Parse day
  if pos < len && chars[pos] == '-' {
    pos = pos + 1
    let start = pos
    while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
      pos = pos + 1
    }
    if pos > start {
      day_val = parse_int_from_chars(chars, start, pos)
    }
  }

  // Parse time part (after T or space)
  if pos < len && (chars[pos] == 'T' || chars[pos] == 't' || chars[pos] == ' ') {
    pos = pos + 1

    // Parse hours
    let start = pos
    while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
      pos = pos + 1
    }
    if pos > start {
      hour = parse_int_from_chars(chars, start, pos)
    }

    // Parse minutes
    if pos < len && chars[pos] == ':' {
      pos = pos + 1
      let min_start = pos
      while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
        pos = pos + 1
      }
      if pos > min_start {
        minute = parse_int_from_chars(chars, min_start, pos)
      }
    }

    // Parse seconds
    if pos < len && chars[pos] == ':' {
      pos = pos + 1
      let sec_start = pos
      while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
        pos = pos + 1
      }
      if pos > sec_start {
        second = parse_int_from_chars(chars, sec_start, pos)
      }
    }

    // Parse milliseconds
    if pos < len && chars[pos] == '.' {
      pos = pos + 1
      let ms_start = pos
      while pos < len && chars[pos] >= '0' && chars[pos] <= '9' {
        pos = pos + 1
      }
      if pos > ms_start {
        let ms_digits = pos - ms_start
        ms = parse_int_from_chars(chars, ms_start, pos)
        // Normalize to 3 digits
        if ms_digits == 1 {
          ms = ms * 100
        } else if ms_digits == 2 {
          ms = ms * 10
        } else if ms_digits > 3 {
          // Truncate extra digits
          let divisor_count = ms_digits - 3
          let mut divisor = 1
          for _i = 0; _i < divisor_count; _i = _i + 1 {
            divisor = divisor * 10
          }
          ms = ms / divisor
        }
      }
    }

    // Handle timezone: Z or +HH:MM or -HH:MM
    // (For simplicity, we treat everything as UTC in this engine)
    // Just skip over timezone designator
  }

  // Validate ranges
  if month < 1 ||
    month > 12 ||
    day_val < 1 ||
    day_val > 31 ||
    hour < 0 ||
    hour > 24 ||
    minute < 0 ||
    minute > 59 ||
    second < 0 ||
    second > 59 ||
    ms < 0 ||
    ms > 999 {
    return 0.0 / 0.0
  }

  // Handle year 0-99 mapping for ISO dates (no mapping, use as-is)
  // For two-digit years from other formats, we'd map 0-99 -> 1900-1999

  // Build the time value
  let d = make_day(
    year.to_double(),
    (month - 1).to_double(),
    day_val.to_double(),
  )
  let t = make_time(
    hour.to_double(),
    minute.to_double(),
    second.to_double(),
    ms.to_double(),
  )
  time_clip(make_date_value(d, t))
}

///|
/// Parse integer from char array slice
fn parse_int_from_chars(chars : Array[Char], start : Int, end : Int) -> Int {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    result = result * 10 + (chars[i].to_int() - '0'.to_int())
  }
  result
}

///|
/// Get the internal [[DateValue]] from a Date object, or raise TypeError
fn get_date_value(this_val : Value) -> Double raise Error {
  match this_val {
    Object(data) =>
      if data.class_name == "Date" {
        match data.properties.get("[[DateValue]]") {
          Some(Number(v)) => v
          _ => 0.0 / 0.0
        }
      } else {
        raise @errors.TypeError(message="this is not a Date object")
      }
    _ => raise @errors.TypeError(message="this is not a Date object")
  }
}

///|
/// Set the internal [[DateValue]] on a Date object
fn set_date_value(this_val : Value, v : Double) -> Unit raise Error {
  match this_val {
    Object(data) =>
      if data.class_name == "Date" {
        data.properties["[[DateValue]]"] = Number(v)
      } else {
        raise @errors.TypeError(message="this is not a Date object")
      }
    _ => raise @errors.TypeError(message="this is not a Date object")
  }
}

///|
/// Create a Date object with the given time value
fn make_date_object(t : Double, date_proto : Value) -> Value {
  let props : Map[String, Value] = {}
  props["[[DateValue]]"] = Number(t)
  let descs : Map[String, PropDescriptor] = {}
  descs["[[DateValue]]"] = {
    writable: true,
    enumerable: false,
    configurable: false,
    getter: None,
    setter: None,
  }
  Object({
    properties: props,
    symbol_properties: {},
    prototype: date_proto,
    callable: None,
    class_name: "Date",
    descriptors: descs,
    symbol_descriptors: {},
    extensible: true,
  })
}

///|
/// Get current time in milliseconds since epoch
fn current_time_ms() -> Double {
  @env.now().to_double()
}

// ============================================================
// Date builtins setup
// ============================================================

///|
pub fn setup_date_builtins(env : Environment) -> Unit {
  let nf_desc : PropDescriptor = {
    writable: false,
    enumerable: false,
    configurable: true,
    getter: None,
    setter: None,
  }
  let date_proto_props : Map[String, Value] = {}

  // Date.prototype.getTime()
  date_proto_props["getTime"] = make_method_func("getTime", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        Number(t)
      })

  // Date.prototype.getFullYear()
  date_proto_props["getFullYear"] = make_method_func("getFullYear", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(year_from_time(t).to_double())
      })

  // Date.prototype.getUTCFullYear()
  date_proto_props["getUTCFullYear"] = make_method_func("getUTCFullYear", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(year_from_time(t).to_double())
      })

  // Date.prototype.getMonth()
  date_proto_props["getMonth"] = make_method_func("getMonth", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(month_from_time(t).to_double())
      })

  // Date.prototype.getUTCMonth()
  date_proto_props["getUTCMonth"] = make_method_func("getUTCMonth", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(month_from_time(t).to_double())
      })

  // Date.prototype.getDate()
  date_proto_props["getDate"] = make_method_func("getDate", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(date_from_time(t).to_double())
      })

  // Date.prototype.getUTCDate()
  date_proto_props["getUTCDate"] = make_method_func("getUTCDate", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(date_from_time(t).to_double())
      })

  // Date.prototype.getDay()
  date_proto_props["getDay"] = make_method_func("getDay", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(week_day(t).to_double())
      })

  // Date.prototype.getUTCDay()
  date_proto_props["getUTCDay"] = make_method_func("getUTCDay", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(week_day(t).to_double())
      })

  // Date.prototype.getHours()
  date_proto_props["getHours"] = make_method_func("getHours", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(hours_from_time(t).to_double())
      })

  // Date.prototype.getUTCHours()
  date_proto_props["getUTCHours"] = make_method_func("getUTCHours", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(hours_from_time(t).to_double())
      })

  // Date.prototype.getMinutes()
  date_proto_props["getMinutes"] = make_method_func("getMinutes", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(minutes_from_time(t).to_double())
      })

  // Date.prototype.getUTCMinutes()
  date_proto_props["getUTCMinutes"] = make_method_func("getUTCMinutes", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(minutes_from_time(t).to_double())
      })

  // Date.prototype.getSeconds()
  date_proto_props["getSeconds"] = make_method_func("getSeconds", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(seconds_from_time(t).to_double())
      })

  // Date.prototype.getUTCSeconds()
  date_proto_props["getUTCSeconds"] = make_method_func("getUTCSeconds", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(seconds_from_time(t).to_double())
      })

  // Date.prototype.getMilliseconds()
  date_proto_props["getMilliseconds"] = make_method_func("getMilliseconds", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(millis_from_time(t).to_double())
      })

  // Date.prototype.getUTCMilliseconds()
  date_proto_props["getUTCMilliseconds"] = make_method_func("getUTCMilliseconds", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(millis_from_time(t).to_double())
      })

  // Date.prototype.getTimezoneOffset() - always 0 (UTC)
  date_proto_props["getTimezoneOffset"] = make_method_func("getTimezoneOffset", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number(0.0) // UTC timezone, offset is 0
      })

  // Date.prototype.getYear() (deprecated, but still in spec Annex B)
  date_proto_props["getYear"] = make_method_func("getYear", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() {
          return Number(0.0 / 0.0)
        }
        Number((year_from_time(t) - 1900).to_double())
      })

  // Date.prototype.setTime(time)
  date_proto_props["setTime"] = make_method_func("setTime", 1, fn(this_val, args) raise {
        let _ = get_date_value(this_val) // validate this is Date
        let v = if args.length() > 0 {
          time_clip(to_number(args[0]))
        } else {
          0.0 / 0.0
        }
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setMilliseconds(ms)
  date_proto_props["setMilliseconds"] = make_method_func("setMilliseconds", 1, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let ms = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let new_time = make_time(
          hours_from_time(t).to_double(),
          minutes_from_time(t).to_double(),
          seconds_from_time(t).to_double(),
          ms,
        )
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCMilliseconds(ms)
  date_proto_props["setUTCMilliseconds"] = make_method_func("setUTCMilliseconds", 1, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let ms = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let new_time = make_time(hours_from_time(t).to_double(), minutes_from_time(t).to_double(), seconds_from_time(t).to_double(), ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setSeconds(sec [, ms])
  date_proto_props["setSeconds"] = make_method_func("setSeconds", 2, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let sec = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let ms = if args.length() > 1 {
          to_number(args[1])
        } else {
          millis_from_time(t).to_double()
        }
        let new_time = make_time(
          hours_from_time(t).to_double(),
          minutes_from_time(t).to_double(),
          sec,
          ms,
        )
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCSeconds(sec [, ms])
  date_proto_props["setUTCSeconds"] = make_method_func("setUTCSeconds", 2, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let sec = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let ms = if args.length() > 1 { to_number(args[1]) } else { millis_from_time(t).to_double() }
        let new_time = make_time(hours_from_time(t).to_double(), minutes_from_time(t).to_double(), sec, ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setMinutes(min [, sec [, ms]])
  date_proto_props["setMinutes"] = make_method_func("setMinutes", 3, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let min = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let sec = if args.length() > 1 {
          to_number(args[1])
        } else {
          seconds_from_time(t).to_double()
        }
        let ms = if args.length() > 2 {
          to_number(args[2])
        } else {
          millis_from_time(t).to_double()
        }
        let new_time = make_time(hours_from_time(t).to_double(), min, sec, ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCMinutes(min [, sec [, ms]])
  date_proto_props["setUTCMinutes"] = make_method_func("setUTCMinutes", 3, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let min = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let sec = if args.length() > 1 { to_number(args[1]) } else { seconds_from_time(t).to_double() }
        let ms = if args.length() > 2 { to_number(args[2]) } else { millis_from_time(t).to_double() }
        let new_time = make_time(hours_from_time(t).to_double(), min, sec, ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setHours(hour [, min [, sec [, ms]]])
  date_proto_props["setHours"] = make_method_func("setHours", 4, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let hour = if args.length() > 0 {
          to_number(args[0])
        } else {
          0.0 / 0.0
        }
        let min = if args.length() > 1 {
          to_number(args[1])
        } else {
          minutes_from_time(t).to_double()
        }
        let sec = if args.length() > 2 {
          to_number(args[2])
        } else {
          seconds_from_time(t).to_double()
        }
        let ms = if args.length() > 3 {
          to_number(args[3])
        } else {
          millis_from_time(t).to_double()
        }
        let new_time = make_time(hour, min, sec, ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCHours(hour [, min [, sec [, ms]]])
  date_proto_props["setUTCHours"] = make_method_func("setUTCHours", 4, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let hour = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let min = if args.length() > 1 { to_number(args[1]) } else { minutes_from_time(t).to_double() }
        let sec = if args.length() > 2 { to_number(args[2]) } else { seconds_from_time(t).to_double() }
        let ms = if args.length() > 3 { to_number(args[3]) } else { millis_from_time(t).to_double() }
        let new_time = make_time(hour, min, sec, ms)
        let v = time_clip(make_date_value(day(t), new_time))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setDate(date)
  date_proto_props["setDate"] = make_method_func("setDate", 1, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let dt = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let new_day = make_day(
          year_from_time(t).to_double(),
          month_from_time(t).to_double(),
          dt,
        )
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCDate(date)
  date_proto_props["setUTCDate"] = make_method_func("setUTCDate", 1, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let dt = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let new_day = make_day(year_from_time(t).to_double(), month_from_time(t).to_double(), dt)
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setMonth(month [, date])
  date_proto_props["setMonth"] = make_method_func("setMonth", 2, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let month = if args.length() > 0 {
          to_number(args[0])
        } else {
          0.0 / 0.0
        }
        let dt = if args.length() > 1 {
          to_number(args[1])
        } else {
          date_from_time(t).to_double()
        }
        let new_day = make_day(year_from_time(t).to_double(), month, dt)
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCMonth(month [, date])
  date_proto_props["setUTCMonth"] = make_method_func("setUTCMonth", 2, fn(this_val, args) raise {
        let t = get_date_value(this_val)
        let month = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let dt = if args.length() > 1 { to_number(args[1]) } else { date_from_time(t).to_double() }
        let new_day = make_day(year_from_time(t).to_double(), month, dt)
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setFullYear(year [, month [, date]])
  date_proto_props["setFullYear"] = make_method_func("setFullYear", 3, fn(this_val, args) raise {
        let mut t = get_date_value(this_val)
        if t.is_nan() {
          t = 0.0 // Use +0 if current value is NaN per spec
        }
        let year = if args.length() > 0 {
          to_number(args[0])
        } else {
          0.0 / 0.0
        }
        let month = if args.length() > 1 {
          to_number(args[1])
        } else {
          month_from_time(t).to_double()
        }
        let dt = if args.length() > 2 {
          to_number(args[2])
        } else {
          date_from_time(t).to_double()
        }
        let new_day = make_day(year, month, dt)
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setUTCFullYear(year [, month [, date]])
  date_proto_props["setUTCFullYear"] = make_method_func("setUTCFullYear", 3, fn(this_val, args) raise {
        let mut t = get_date_value(this_val)
        if t.is_nan() { t = 0.0 }
        let year = if args.length() > 0 { to_number(args[0]) } else { 0.0 / 0.0 }
        let month = if args.length() > 1 { to_number(args[1]) } else { month_from_time(t).to_double() }
        let dt = if args.length() > 2 { to_number(args[2]) } else { date_from_time(t).to_double() }
        let new_day = make_day(year, month, dt)
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.setYear(year) - deprecated Annex B
  date_proto_props["setYear"] = make_method_func("setYear", 1, fn(this_val, args) raise {
        let mut t = get_date_value(this_val)
        if t.is_nan() {
          t = 0.0
        }
        let year_arg = if args.length() > 0 {
          to_number(args[0])
        } else {
          0.0 / 0.0
        }
        if year_arg.is_nan() {
          set_date_value(this_val, 0.0 / 0.0)
          return Number(0.0 / 0.0)
        }
        let yr = year_arg.to_int()
        let year = if yr >= 0 && yr <= 99 {
          (1900 + yr).to_double()
        } else {
          year_arg
        }
        let new_day = make_day(
          year,
          month_from_time(t).to_double(),
          date_from_time(t).to_double(),
        )
        let v = time_clip(make_date_value(new_day, time_within_day(t)))
        set_date_value(this_val, v)
        Number(v)
      })

  // Date.prototype.toString()
  date_proto_props["toString"] = make_method_func("toString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_string(t))
      })

  // Date.prototype.toDateString()
  date_proto_props["toDateString"] = make_method_func("toDateString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_date_string(t))
      })

  // Date.prototype.toTimeString()
  date_proto_props["toTimeString"] = make_method_func("toTimeString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_time_string(t))
      })

  // Date.prototype.toISOString()
  date_proto_props["toISOString"] = make_method_func("toISOString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_iso_string(t))
      })

  // Date.prototype.toUTCString()
  date_proto_props["toUTCString"] = make_method_func("toUTCString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_utc_string(t))
      })

  // Date.prototype.toGMTString() - alias for toUTCString
  date_proto_props["toGMTString"] = date_proto_props["toUTCString"]

  // Date.prototype.toJSON()
  date_proto_props["toJSON"] = make_method_func("toJSON", 1, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        if t.is_nan() || t.is_inf() {
          Null
        } else {
          String_(date_to_iso_string(t))
        }
      })

  // Date.prototype.valueOf()
  date_proto_props["valueOf"] = make_method_func("valueOf", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        Number(t)
      })

  // Date.prototype.toLocaleDateString() - simplified, same as toDateString
  date_proto_props["toLocaleDateString"] = make_method_func("toLocaleDateString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_date_string(t))
      })

  // Date.prototype.toLocaleTimeString() - simplified, same as toTimeString
  date_proto_props["toLocaleTimeString"] = make_method_func("toLocaleTimeString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_time_string(t))
      })

  // Date.prototype.toLocaleString() - simplified, same as toString
  date_proto_props["toLocaleString"] = make_method_func("toLocaleString", 0, fn(this_val, _args) raise {
        let t = get_date_value(this_val)
        String_(date_to_string(t))
      })

  // Date.prototype[Symbol.toPrimitive]
  let to_primitive_method = make_interp_method_func("[Symbol.toPrimitive]", 1, fn(interp, this_val, args) raise {
        // Step 1: If Type(O) is not Object, throw a TypeError exception
        match this_val {
          Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
          _ => raise @errors.TypeError(message="Date.prototype[Symbol.toPrimitive] requires that 'this' be an Object")
        }
        let hint = if args.length() > 0 {
          args[0].to_string()
        } else {
          "default"
        }
        let try_first = match hint {
          "string" | "default" => "string"
          "number" => "number"
          _ => raise @errors.TypeError(message="Invalid hint: " + hint)
        }
        let loc = @token.Loc::default()
        // OrdinaryToPrimitive: try toString/valueOf based on hint
        if try_first == "string" {
          // Try toString first
          let to_string_val = interp.get_property(this_val, "toString", loc)
          if is_callable(to_string_val) {
            let result = interp.call_value(to_string_val, this_val, [], loc)
            match result {
              Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
              _ => return result
            }
          }
          // Then try valueOf
          let value_of_val = interp.get_property(this_val, "valueOf", loc)
          if is_callable(value_of_val) {
            let result = interp.call_value(value_of_val, this_val, [], loc)
            match result {
              Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
              _ => return result
            }
          }
          raise @errors.TypeError(message="Cannot convert object to primitive value")
        } else {
          // Try valueOf first
          let value_of_val = interp.get_property(this_val, "valueOf", loc)
          if is_callable(value_of_val) {
            let result = interp.call_value(value_of_val, this_val, [], loc)
            match result {
              Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
              _ => return result
            }
          }
          // Then try toString
          let to_string_val = interp.get_property(this_val, "toString", loc)
          if is_callable(to_string_val) {
            let result = interp.call_value(to_string_val, this_val, [], loc)
            match result {
              Object(_) | Array(_) | Map(_) | Set(_) | Promise(_) | Proxy(_) => ()
              _ => return result
            }
          }
          raise @errors.TypeError(message="Cannot convert object to primitive value")
        }
      })

  // Create descriptor map for Date.prototype methods (non-enumerable, writable, configurable)
  let method_desc : PropDescriptor = { writable: true, enumerable: false, configurable: true, getter: None, setter: None }
  let date_proto_descs : Map[String, PropDescriptor] = {}
  date_proto_descs["getTime"] = method_desc
  date_proto_descs["getFullYear"] = method_desc
  date_proto_descs["getUTCFullYear"] = method_desc
  date_proto_descs["getMonth"] = method_desc
  date_proto_descs["getUTCMonth"] = method_desc
  date_proto_descs["getDate"] = method_desc
  date_proto_descs["getUTCDate"] = method_desc
  date_proto_descs["getDay"] = method_desc
  date_proto_descs["getUTCDay"] = method_desc
  date_proto_descs["getHours"] = method_desc
  date_proto_descs["getUTCHours"] = method_desc
  date_proto_descs["getMinutes"] = method_desc
  date_proto_descs["getUTCMinutes"] = method_desc
  date_proto_descs["getSeconds"] = method_desc
  date_proto_descs["getUTCSeconds"] = method_desc
  date_proto_descs["getMilliseconds"] = method_desc
  date_proto_descs["getUTCMilliseconds"] = method_desc
  date_proto_descs["getTimezoneOffset"] = method_desc
  date_proto_descs["getYear"] = method_desc
  date_proto_descs["setTime"] = method_desc
  date_proto_descs["setMilliseconds"] = method_desc
  date_proto_descs["setUTCMilliseconds"] = method_desc
  date_proto_descs["setSeconds"] = method_desc
  date_proto_descs["setUTCSeconds"] = method_desc
  date_proto_descs["setMinutes"] = method_desc
  date_proto_descs["setUTCMinutes"] = method_desc
  date_proto_descs["setHours"] = method_desc
  date_proto_descs["setUTCHours"] = method_desc
  date_proto_descs["setDate"] = method_desc
  date_proto_descs["setUTCDate"] = method_desc
  date_proto_descs["setMonth"] = method_desc
  date_proto_descs["setUTCMonth"] = method_desc
  date_proto_descs["setFullYear"] = method_desc
  date_proto_descs["setUTCFullYear"] = method_desc
  date_proto_descs["setYear"] = method_desc
  date_proto_descs["toString"] = method_desc
  date_proto_descs["toDateString"] = method_desc
  date_proto_descs["toTimeString"] = method_desc
  date_proto_descs["toISOString"] = method_desc
  date_proto_descs["toUTCString"] = method_desc
  date_proto_descs["toGMTString"] = method_desc
  date_proto_descs["toJSON"] = method_desc
  date_proto_descs["valueOf"] = method_desc
  date_proto_descs["toLocaleDateString"] = method_desc
  date_proto_descs["toLocaleTimeString"] = method_desc
  date_proto_descs["toLocaleString"] = method_desc

  // Create the Date prototype object
  let date_proto : Value = Object({
    properties: date_proto_props,
    symbol_properties: {},
    prototype: Null,
    callable: None,
    class_name: "Date",
    descriptors: date_proto_descs,
    symbol_descriptors: {},
    extensible: true,
  })

  // Set Symbol.toPrimitive on prototype
  match date_proto {
    Object(data) => {
      let to_prim_sym = get_toprimitive_symbol()
      data.symbol_properties[to_prim_sym.id] = to_primitive_method
      // Also store [[DateValue]] on proto for "Invalid Date" default
      data.properties["[[DateValue]]"] = Number(0.0 / 0.0)
    }
    _ => ()
  }

  // Static methods
  let date_props : Map[String, Value] = {}
  date_props["prototype"] = date_proto
  date_props["name"] = String_("Date")
  date_props["length"] = Number(7.0)

  // Date.now()
  date_props["now"] = make_static_func_with_length("now", 0, fn(_args) {
    Number(current_time_ms().floor())
  })

  // Date.parse(string)
  date_props["parse"] = make_static_func_with_length("parse", 1, fn(args) {
    let s = if args.length() > 0 { args[0].to_string() } else { "" }
    Number(parse_date_string(s))
  })

  // Date.UTC(year, month [, date [, hours [, minutes [, seconds [, ms]]]]])
  date_props["UTC"] = make_static_func_with_length("UTC", 7, fn(args) raise {
    let year_arg = if args.length() > 0 {
      to_number(args[0])
    } else {
      0.0 / 0.0
    }
    if year_arg.is_nan() {
      return Number(0.0 / 0.0)
    }
    let yr = year_arg.to_int()
    let year = if yr >= 0 && yr <= 99 {
      (1900 + yr).to_double()
    } else {
      year_arg
    }
    let month = if args.length() > 1 { to_number(args[1]) } else { 0.0 }
    let date_arg = if args.length() > 2 { to_number(args[2]) } else { 1.0 }
    let hour = if args.length() > 3 { to_number(args[3]) } else { 0.0 }
    let min = if args.length() > 4 { to_number(args[4]) } else { 0.0 }
    let sec = if args.length() > 5 { to_number(args[5]) } else { 0.0 }
    let ms = if args.length() > 6 { to_number(args[6]) } else { 0.0 }
    let d = make_day(year, month, date_arg)
    let t = make_time(hour, min, sec, ms)
    Number(time_clip(make_date_value(d, t)))
  })

  // Date constructor
  // When called with new: creates a Date object
  // When called without new: returns a string representation of current date/time
  let date_proto_ref = date_proto
  env.def_builtin(
    "Date",
    Object({
      properties: date_props,
      symbol_properties: {},
      prototype: Null,
      callable: Some(
        NativeCallable("Date", fn(args) raise {
          // Date() without new returns a string of the current date/time
          // new Date(...) returns a Date object
          if not(is_constructing.val) {
            return String_(date_to_string(current_time_ms().floor()))
          }
          let t = if args.length() == 0 {
            // new Date() - current time
            current_time_ms().floor()
          } else if args.length() == 1 {
            // new Date(value)
            let val = args[0]
            match val {
              String_(s) => parse_date_string(s)
              _ => {
                let n = to_number(val)
                time_clip(n)
              }
            }
          } else {
            // new Date(year, month [, date [, hours [, minutes [, seconds [, ms]]]]])
            let year_arg = to_number(args[0])
            if year_arg.is_nan() {
              0.0 / 0.0
            } else {
              let yr = year_arg.to_int()
              let year = if yr >= 0 && yr <= 99 {
                (1900 + yr).to_double()
              } else {
                year_arg
              }
              let month = if args.length() > 1 {
                to_number(args[1])
              } else {
                0.0
              }
              let date_arg = if args.length() > 2 {
                to_number(args[2])
              } else {
                1.0
              }
              let hour = if args.length() > 3 {
                to_number(args[3])
              } else {
                0.0
              }
              let min = if args.length() > 4 { to_number(args[4]) } else { 0.0 }
              let sec = if args.length() > 5 { to_number(args[5]) } else { 0.0 }
              let ms = if args.length() > 6 { to_number(args[6]) } else { 0.0 }
              let d = make_day(year, month, date_arg)
              let time = make_time(hour, min, sec, ms)
              time_clip(make_date_value(d, time))
            }
          }
          make_date_object(t, date_proto_ref)
        }),
      ),
      class_name: "Function",
      descriptors: { "name": nf_desc, "length": nf_desc },
      symbol_descriptors: {},
      extensible: true,
    }),
  )

  // Set Date.prototype.constructor = Date
  match date_proto {
    Object(data) => {
      let ctor = env.get("Date") catch { _ => Undefined }
      data.properties["constructor"] = ctor
      data.descriptors["constructor"] = {
        writable: true,
        enumerable: false,
        configurable: true,
        getter: None,
        setter: None,
      }
    }
    _ => ()
  }
}
