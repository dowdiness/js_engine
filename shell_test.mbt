///|
test "Shell keeps host capabilities outside the JavaScript core" {
  let load_source = fn(request, referrer) raise {
    match (request, referrer) {
      ("entry.js", None) =>
        @js_engine.LoadedScript(
          identity="/fixtures/entry.js",
          source=(
            #|load("nested.js");
            #|console.log(arguments.join("|"));
            #|console.log(scriptArgs.length, scriptArgs[1]);
            #|let bytes = new Uint8Array(read("data.bin", "binary"));
            #|console.log(bytes.length, bytes[0], bytes[1]);
            #|console.log(typeof performance.now());
          ),
        )
      ("nested.js", Some("/fixtures/entry.js")) =>
        @js_engine.LoadedScript(
          identity="/fixtures/nested.js",
          source="console.log(40 + 2);",
        )
      _ => fail("unexpected script request")
    }
  }
  let read_bytes = fn(request, referrer) raise {
    guard request == "data.bin" && referrer == Some("/fixtures/entry.js") else {
      fail("unexpected binary request")
    }
    Bytes::from_array([b'\x01', b'\xFF'])
  }
  let shell = @js_engine.Shell(
    load_source~,
    read_bytes=Some(read_bytes),
    now_millis=Some(() => 1.25),
  )
  shell.set_arguments("entry.js", ["alpha"])
  shell.run_file("entry.js")
  shell.drain_jobs()
  json_inspect(shell.take_output(), content=[
    "42", "alpha", "2 alpha", "2 1 255", "number",
  ])
}
