///|
test "normalize omitted form defaults to NFC" {
  let source =
    #|"e\u0301".normalize()
  let (_, result) = @js_engine.run(source)
  expect_string(result, "é", "NFC default")
}

///|
test "normalize explicit undefined defaults to NFC" {
  let source =
    #|"e\u0301".normalize(undefined)
  let (_, result) = @js_engine.run(source)
  expect_string(result, "é", "undefined default")
}

///|
test "normalize NFC form" {
  let source =
    #|"e\u0301".normalize("NFC")
  let (_, result) = @js_engine.run(source)
  expect_string(result, "é", "NFC")
}

///|
test "normalize NFD form" {
  let source =
    #|"é".normalize("NFD")
  let (_, result) = @js_engine.run(source)
  expect_string(result, "e\u{301}", "NFD")
}

///|
test "normalize NFKC form" {
  let source =
    #|"\uFB01".normalize("NFKC")
  let (_, result) = @js_engine.run(source)
  expect_string(result, "fi", "NFKC")
}

///|
test "normalize NFKD form" {
  let source =
    #|"\uFB01".normalize("NFKD")
  let (_, result) = @js_engine.run(source)
  expect_string(result, "fi", "NFKD")
}

///|
test "normalize coerces receiver and form objects" {
  let source =
    #|String.prototype.normalize.call({ toString() { return "\uFB01"; } }, { toString() { return "NFKC"; } })
  let (_, result) = @js_engine.run(source)
  expect_string(result, "fi", "object coercion")
}

///|
test "normalize coerces receiver before form" {
  let source =
    #|let receiver_sentinel = {};
    #|let form_sentinel = {};
    #|let receiver = { toString() { throw receiver_sentinel; } };
    #|let form = { toString() { throw form_sentinel; } };
    #|try { String.prototype.normalize.call(receiver, form); false; } catch (e) { e === receiver_sentinel; }
  let (_, result) = @js_engine.run(source)
  expect_string(result, "true", "coercion order and identity")
}

///|
test "normalize null receiver throws TypeError" {
  let source =
    #|try { String.prototype.normalize.call(null); false; } catch (e) { e instanceof TypeError; }
  let (_, result) = @js_engine.run(source)
  expect_string(result, "true", "null receiver")
}

///|
test "normalize undefined receiver throws TypeError" {
  let source =
    #|try { String.prototype.normalize.call(undefined); false; } catch (e) { e instanceof TypeError; }
  let (_, result) = @js_engine.run(source)
  expect_string(result, "true", "undefined receiver")
}

///|
test "normalize invalid form throws RangeError" {
  let source =
    #|try { "x".normalize("BAD"); false; } catch (e) { e instanceof RangeError; }
  let (_, result) = @js_engine.run(source)
  expect_string(result, "true", "invalid form")
}

///|
test "normalize preserves lone surrogates" {
  let source =
    #|"\uD800".normalize() === "\uD800"
  let (_, result) = @js_engine.run(source)
  expect_string(result, "true", "surrogate retention")
}
