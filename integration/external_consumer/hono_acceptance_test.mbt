///|
const WEB_SHIM =
  #|globalThis.Headers = class Headers {
  #|  #values = new Map();
  #|  constructor(init) {
  #|    if (init instanceof Headers) {
  #|      init.forEach((value, name) => this.set(name, value));
  #|    } else if (Array.isArray(init)) {
  #|      for (const [name, value] of init) this.append(name, value);
  #|    } else if (init != null) {
  #|      for (const [name, value] of Object.entries(init)) this.set(name, value);
  #|    }
  #|  }
  #|  #name(name) { return String(name).toLowerCase(); }
  #|  append(name, value) {
  #|    const key = this.#name(name);
  #|    const text = String(value);
  #|    this.#values.set(key, this.#values.has(key) ? `${this.#values.get(key)}, ${text}` : text);
  #|  }
  #|  delete(name) { this.#values.delete(this.#name(name)); }
  #|  get(name) { return this.#values.get(this.#name(name)) ?? null; }
  #|  has(name) { return this.#values.has(this.#name(name)); }
  #|  set(name, value) { this.#values.set(this.#name(name), String(value)); }
  #|  entries() { return this.#values.entries(); }
  #|  forEach(callback, thisArg) {
  #|    this.#values.forEach((value, name) => callback.call(thisArg, value, name, this));
  #|  }
  #|  [Symbol.iterator]() { return this.entries(); }
  #|};
  #|globalThis.Request = class Request {
  #|  constructor(input, init = {}) {
  #|    const source = input instanceof Request ? input : null;
  #|    this.url = source ? source.url : String(input);
  #|    this.method = String(init.method ?? source?.method ?? "GET").toUpperCase();
  #|    this.headers = new Headers(init.headers ?? source?.headers);
  #|    this.body = init.body !== undefined ? init.body : source?.body ?? null;
  #|  }
  #|};
  #|globalThis.Response = class Response {
  #|  constructor(body = null, init = {}) {
  #|    this.body = body;
  #|    this.status = init.status ?? 200;
  #|    this.headers = new Headers(init.headers);
  #|  }
  #|  text() { return Promise.resolve(this.body == null ? "" : String(this.body)); }
  #|};

///|
const HONO_ACCEPTANCE_SCENARIO =
  #|const { Hono } = globalThis.__HonoAcceptance;
  #|const app = new Hono();
  #|app.onError((error) => { throw error; });
  #|const middlewareOrder = [];
  #|app.use("*", async (c, next) => {
  #|  middlewareOrder.push("before");
  #|  await next();
  #|  middlewareOrder.push("after");
  #|});
  #|app.get("/hello/:name", (c) => {
  #|  middlewareOrder.push("handler");
  #|  return c.json({
  #|    message: `Hello ${c.req.param("name")}`,
  #|    lang: c.req.query("lang"),
  #|  });
  #|});
  #|let honoAcceptanceResult = null;
  #|function readHonoAcceptanceResult() { return honoAcceptanceResult; }
  #|(async () => {
  #|  const response = await app.request("http://localhost/hello/Ada?lang=moon");
  #|  const headers = {};
  #|  response.headers.forEach((value, name) => { headers[name] = value; });
  #|  honoAcceptanceResult = {
  #|    status: response.status,
  #|    headers,
  #|    body: await response.text(),
  #|    order: middlewareOrder,
  #|  };
  #|})().catch((error) => {
  #|  honoAcceptanceResult = {
  #|    error: `${error.name}: ${error.message}`,
  #|    order: middlewareOrder,
  #|  };
  #|});

///|
test "stable facade runs default Hono core across targets" {
  let engine = @js_engine.Engine()
  engine.eval(WEB_SHIM)
  engine.eval(HONO_4_12_31_BUNDLE)
  engine.eval(HONO_ACCEPTANCE_SCENARIO)
  inspect(engine.run_microtask_checkpoint(), content="false")
  json_inspect(engine.call_json("readHonoAcceptanceResult", []), content={
    "status": 200,
    "headers": { "content-type": "application/json" },
    "body": "{\"message\":\"Hello Ada\",\"lang\":\"moon\"}",
    "order": ["before", "handler", "after"],
  })
}
