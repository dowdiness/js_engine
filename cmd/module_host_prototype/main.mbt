///|
// THROWAWAY design probe, not a proposed public API.
// Run: node scripts/module_host_prototype.cjs --all (or omit --all for menu).
// Questions: can a transformed source host be discarded before evaluation?
// Can one prepared AST graph serve independent realms? Which errors remain
// deferred to realm-dependent instantiation, and which locations survive?
// Assumptions: synchronous static ESM; host-owned opaque string keys; no eval,
// dynamic import, TLA, import attributes, timers, or bytecode claims.
// Missing source/export, cycles, alias identity, host release, and mapped-error
// scenarios are observations, not production test coverage or conformance.

///|
struct PrototypeInput {
  entry : String
  sources : Map[String, String]
  aliases : Map[String, String]
  call : String
  calls : Int
  prepare_only : Bool
} derive(FromJson)

///|
struct PrototypeProgram {
  entry : String
  plan : @plan.Plan
  modules : Array[(String, Array[@ast.Stmt])]
}

///|
fn PrototypeProgram::PrototypeProgram(
  entry : String,
  plan : @plan.Plan,
  modules : Array[(String, Array[@ast.Stmt])],
) -> PrototypeProgram {
  { entry, plan, modules, }
}

///|
struct PrototypeHost {
  sources : Map[String, String]
  aliases : Map[String, String]
  events : Array[Json]
}

///|
fn PrototypeHost::PrototypeHost(input : PrototypeInput) -> PrototypeHost {
  { sources: input.sources, aliases: input.aliases, events: [], }
}

///|
fn PrototypeHost::resolve(
  self : PrototypeHost,
  importer : String,
  request : String,
) -> String {
  // Deliberately NOT URL or import-map semantics: exact keys + host aliases.
  let key = self.aliases.get(request).unwrap_or(request)
  self.events.push({
    "operation": "resolve",
    "importer": importer,
    "request": request,
    "key": key,
  })
  key
}

///|
fn PrototypeHost::load(self : PrototypeHost, key : String) -> String raise {
  self.events.push({ "operation": "load", "key": key })
  guard self.sources.get(key) is Some(source) else {
    fail("missing source: " + key)
  }
  source
}

///|
fn prepare(
  entry : String,
  host : PrototypeHost,
  parses : Ref[Int],
  diagnostic : Ref[Json],
) -> PrototypeProgram raise {
  // Worklist admission happens before traversal, so cycles do not recurse.
  let pending = [entry]
  let admitted : Map[String, Bool] = Map([(entry, true)])
  let modules : Array[(String, Array[@ast.Stmt])] = []
  let mut cursor = 0
  while cursor < pending.length() {
    let key = pending[cursor]
    cursor += 1
    diagnostic.val = { "phase": "load", "identity": key }
    let source = host.load(key)
    parses.val += 1
    let parsed = match @parser.parse_diagnostic(source) {
      Ok(program) => program
      Err(error) => {
        let location : Json = match error.source_span() {
          Some(span) =>
            {
              "line": span.start().line,
              "column": span.start().col,
              "offset": span.start().offset,
            }
          None => Json::null()
        }
        diagnostic.val = {
          "phase": "parse",
          "identity": key,
          "location": location,
        }
        fail(error.message())
      }
    }
    let bind = (request : String) => {
      let target = host.resolve(key, request)
      if !admitted.contains(target) {
        admitted[target] = true
        pending.push(target)
      }
      target
    }
    // AST rewriting is confined to the probe. No text replacement, external
    // AST format, or mutable Realm object becomes a host-facing contract.
    let stmts = parsed.stmts.map(stmt => {
      match stmt {
        ImportDecl(default_name, names, namespace_name, request, form, loc) =>
          @ast.Stmt::ImportDecl(
            default_name,
            names,
            namespace_name,
            bind(request),
            form,
            loc,
          )
        ExportNamedDecl(decl, names, Some(request), form, loc) =>
          @ast.Stmt::ExportNamedDecl(
            decl,
            names,
            Some(bind(request)),
            form,
            loc,
          )
        ExportAllDecl(name, request, form, loc) =>
          @ast.Stmt::ExportAllDecl(name, bind(request), form, loc)
        _ => stmt
      }
    })
    modules.push((key, stmts))
  }
  let plan = @static_link.compile_plan(modules) catch {
    @static_link.LinkError(kind~, module_key~, export_name~, line~, column~) => {
      diagnostic.val = {
        "phase": "static-link",
        "kind": kind,
        "identity": module_key,
        "export_name": export_name,
        "line": line,
        "column": column,
      }
      fail(kind + ": " + module_key + " / " + export_name)
    }
  }
  // Poison source requests after compilation. Any accidental AST-based graph
  // resolution at Session startup now fails instead of masking duplicate work.
  let execution_modules = modules.map(pair => {
    let (key, stmts) = pair
    (
      key,
      stmts.map(stmt => {
        match stmt {
          ImportDecl(default_name, names, namespace_name, _, form, loc) =>
            @ast.Stmt::ImportDecl(
              default_name, names, namespace_name, "PROBE_INVALID_REQUEST", form,
              loc,
            )
          ExportNamedDecl(decl, names, Some(_), form, loc) =>
            @ast.Stmt::ExportNamedDecl(
              decl,
              names,
              Some("PROBE_INVALID_REQUEST"),
              form,
              loc,
            )
          ExportAllDecl(name, _, form, loc) =>
            @ast.Stmt::ExportAllDecl(name, "PROBE_INVALID_REQUEST", form, loc)
          _ => stmt
        }
      }),
    )
  })
  diagnostic.val = { "phase": "prepared" }
  PrototypeProgram(entry, plan, execution_modules)
}

///|
fn start(program : PrototypeProgram, call : String) -> (Int) -> Json {
  let interp = @interpreter.new_interpreter()
  let phase = Ref("created")
  let startup : Result[(String) -> @runtime.Value raise, Error] = Ok(
    interp.prototype_instantiate_plan(
      program.entry,
      program.modules,
      program.plan,
      phase,
    ),
  ) catch {
    error => Err(error)
  }
  calls => {
    let values : Array[String] = []
    let outcome : Result[Unit, Error] = Ok(
      {
        let lookup = match startup {
          Ok(lookup) => lookup
          Err(error) => raise error
        }
        if call != "" {
          phase.val = "call"
          for _ in 0..<calls {
            let function = lookup(call)
            values.push(
              interp
              .call_value(
                function,
                @runtime.Value::Undefined,
                [],
                @token.Loc::default(),
              )
              .to_string(),
            )
          }
        }
      },
    ) catch {
      error => Err(error)
    }
    match outcome {
      Ok(_) =>
        {
          "status": "ok",
          "phase": phase.val,
          "calls": values,
          "output": interp.host.output,
        }
      Err(error) =>
        {
          // Do not invent a location: this direct path returns only Error.
          "status": "error",
          "phase": phase.val,
          "message": error.to_string(),
          "source_location": Json::null(),
          "calls": values,
          "output": interp.host.output,
        }
    }
  }
}

///|
fn probe(input : PrototypeInput) -> Json {
  let host = PrototypeHost(input)
  let parses = Ref(0)
  let diagnostic : Ref[Json] = Ref(Json::null())
  let preparation : Result[PrototypeProgram, Error] = Ok(
    prepare(input.entry, host, parses, diagnostic),
  ) catch {
    error => Err(error)
  }
  match preparation {
    Err(error) =>
      {
        "preparation": "error",
        "message": error.to_string(),
        "diagnostic": diagnostic.val,
        "host_events": host.events,
        "parse_calls": parses.val,
      }
    Ok(program) => {
      let keys = program.modules.map(pair => pair.0)
      // Revoke host access AND destroy source inputs. Retain only the event
      // log for observation, not a loader closure in PrototypeProgram.
      host.sources.clear()
      host.aliases.clear()
      guard !input.prepare_only else {
        return {
          "preparation": "ok",
          "modules": keys,
          "parse_calls": parses.val,
          "host_sources_after_release": host.sources.length(),
          "host_events": host.events,
          "execution": "not-started",
        }
      }
      let events_before = host.events.length()
      let first_session = start(program, input.call)
      let first = first_session(input.calls)
      // Same Program data and bindings, opposite record/plan storage order.
      let reversed = PrototypeProgram(
        program.entry,
        @plan.Plan(program.plan.modules.rev()),
        program.modules.rev(),
      )
      let second_session = start(reversed, input.call)
      let second = second_session(input.calls)
      let resumed_first = first_session(1)
      {
        "preparation": "ok",
        "modules": keys,
        "parse_calls": parses.val,
        "binding_plan": program.plan,
        "runtime_requests_poisoned": true,
        "second_session_modules": reversed.modules.map(pair => pair.0),
        "host_sources_after_release": host.sources.length(),
        "host_calls_during_sessions": host.events.length() - events_before,
        "host_events": host.events,
        "sessions": [first, second],
        "resumed_first": resumed_first,
      }
    }
  }
}

///|
fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    println(
      "Usage: moon run --target native cmd/module_host_prototype -- input.json",
    )
    @sys.exit(1)
  }
  try {
    let input : PrototypeInput = @json.from_json(
      @json.parse(@fs.read_file_to_string(args[1])),
    )
    println(probe(input).stringify(indent=2))
  } catch {
    error => {
      let report : Json = { "runner_error": error.to_string() }
      println(report.stringify())
      @sys.exit(1)
    }
  }
}
