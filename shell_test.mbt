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

///|
test "Shell host functions are ordinary global object properties" {
  let shell = @js_engine.Shell(
    load_source=fn(_, _) raise { fail("load is not expected") },
    read_bytes=Some(fn(_, _) raise { fail("read is not expected") }),
    now_millis=Some(() => 1.25),
  )
  let source =
    #|console.log(globalThis.load === load);
    #|console.log(globalThis.read === read);
    #|console.log(globalThis.readFile === readFile);
    #|console.log(globalThis.runString === runString);
    #|console.log(globalThis.performance === performance);
  shell.eval(source)
  json_inspect(shell.take_output(), content=[
    "true", "true", "true", "true", "true",
  ])
}

///|
test "Shell preserves empty Console messages" {
  let shell = @js_engine.Shell(load_source=fn(_, _) raise {
    fail("load is not expected")
  })
  shell.eval("console.log(); console.info();")
  json_inspect(shell.take_output(), content=["", ""])
}

///|
test "runString child Realm shares its Shell Console destination" {
  let shell = @js_engine.Shell(load_source=fn(_, _) raise {
    fail("load is not expected")
  })
  let source =
    #|runString('console.log("child")');
    #|console.log("parent");
  shell.eval(source)
  json_inspect(shell.take_output(), content=["child", "parent"])
}

///|
test "runString reads child resources into the child Realm" {
  let load_source = fn(request, referrer) raise {
    match (request, referrer) {
      ("entry.js", None) =>
        @js_engine.LoadedScript(
          identity="/fixtures/entry.js",
          source=(
            #|let child = runString('load("child.js")');
            #|console.log(child.binaryIsLocal);
          ),
        )
      ("child.js", Some("/fixtures/entry.js")) =>
        @js_engine.LoadedScript(
          identity="/fixtures/sub/child.js",
          source=(
            #|globalThis.binaryIsLocal =
            #|  read("data.bin", "binary") instanceof ArrayBuffer;
          ),
        )
      _ => fail("unexpected script request")
    }
  }
  let read_bytes = fn(request, referrer) raise {
    guard request == "data.bin" && referrer == Some("/fixtures/sub/child.js") else {
      fail("binary request did not use the child referrer")
    }
    Bytes::from_array([b'\x2A'])
  }
  let shell = @js_engine.Shell(load_source~, read_bytes=Some(read_bytes))
  shell.run_file("entry.js")
  json_inspect(shell.take_output(), content=["true"])
}
