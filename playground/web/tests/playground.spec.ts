import { readdir, readFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";

async function readGeneratedExamples(): Promise<Record<string, string>> {
  const directory = fileURLToPath(
    new URL("../generated/examples/", import.meta.url),
  );
  const fileNames = (await readdir(directory))
    .filter(fileName => fileName.endsWith(".js"))
    .sort();
  const entries = await Promise.all(
    fileNames.map(async fileName => [
      basename(fileName, ".js"),
      await readFile(join(directory, fileName), "utf8"),
    ] as const),
  );
  return Object.fromEntries(entries);
}


test("runs source and keeps output text-only", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor").fill("console.log('<img src=x>'); 6 * 7;");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#console")).toHaveText("<img src=x>");
  await expect(page.locator("#result")).toHaveText("42");
  await expect(page.locator("#console img")).toHaveCount(0);
});

test("links to the repository", async ({ page }) => {
  await page.goto("./");

  const repositoryLink = page.getByRole("link", {
    name: "Open js_engine on GitHub",
  });
  await expect(repositoryLink).toHaveAttribute(
    "href",
    "https://github.com/dowdiness/js_engine",
  );
  await expect(repositoryLink).toHaveAttribute("target", "_blank");
  await expect(repositoryLink).toHaveAttribute("rel", /noopener/);
});

test("recovers after timeout and stop", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor");
  const run = page.getByRole("button", { name: /Run/ });
  const stop = page.getByRole("button", { name: "Stop" });

  await editor.fill("while (true) {};");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Execution terminated", {
    timeout: 5_000,
  });

  await editor.fill("41 + 1;");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("42");

  await editor.fill("while (true) {};");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Running");
  await stop.click();
  await expect(page.locator("#status")).toHaveText("Stopped");

  await editor.fill("20 + 22;");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("42");
});

test("ignores a stale response after Run starts again", async ({ page }) => {
  await page.addInitScript(() => {
    const workers: ControlledWorker[] = [];

    class ControlledWorker {
      request: { requestId: string } | undefined;
      listeners = new Map<string, EventListener[]>();

      constructor() {
        workers.push(this);
      }

      postMessage(message: { requestId: string }): void {
        this.request = message;
      }

      terminate(): void {}

      addEventListener(type: string, listener: EventListener): void {
        const current = this.listeners.get(type) ?? [];
        current.push(listener);
        this.listeners.set(type, current);
      }

      dispatchResponse(response: unknown): void {
        const event = new MessageEvent("message", { data: response });
        for (const listener of this.listeners.get("message") ?? []) {
          listener(event);
        }
      }
    }

    Object.defineProperty(window, "__playgroundWorkers", {
      configurable: true,
      value: workers,
    });
    Object.defineProperty(window, "Worker", {
      configurable: true,
      value: ControlledWorker,
    });
  });

  await page.goto("./");
  const editor = page.locator("#editor");
  const run = page.getByRole("button", { name: /Run/ });

  await editor.fill("'old';");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Running");

  await editor.fill("'new';");
  await run.click();
  await expect(page.locator("#status")).toHaveText("Running");

  await page.evaluate(() => {
    const workers = (window as unknown as {
      __playgroundWorkers: Array<{
        request: { requestId: string } | undefined;
        dispatchResponse(response: unknown): void;
      }>;
    }).__playgroundWorkers;
    const oldRequestId = workers[0]?.request?.requestId;
    if (!oldRequestId) throw new Error("first worker did not receive a request");
    workers[0]?.dispatchResponse({
      protocolVersion: 1,
      requestId: oldRequestId,
      kind: "completed",
      output: ["old"],
      result: "old",
    });
  });
  await expect(page.locator("#status")).toHaveText("Running");

  await page.evaluate(() => {
    const workers = (window as unknown as {
      __playgroundWorkers: Array<{
        request: { requestId: string } | undefined;
        dispatchResponse(response: unknown): void;
      }>;
    }).__playgroundWorkers;
    const newRequestId = workers[1]?.request?.requestId;
    if (!newRequestId) throw new Error("second worker did not receive a request");
    workers[1]?.dispatchResponse({
      protocolVersion: 1,
      requestId: newRequestId,
      kind: "completed",
      output: [],
      result: "new",
    });
  });
  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("new");
  await expect(page.locator("#console")).toHaveText("");
});

test("does not share globals between runs", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor");
  const run = page.getByRole("button", { name: /Run/ });

  await editor.fill("globalThis.playgroundValue = 42; 'set';");
  await run.click();
  await expect(page.locator("#result")).toHaveText("set");

  await editor.fill("typeof globalThis.playgroundValue;");
  await run.click();
  await expect(page.locator("#result")).toHaveText("undefined");
});

test("reports parse locations in diagnostics", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor").fill("let =");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#diagnostics")).toContainText("parse-error");
  await expect(page.locator("#diagnostics")).toContainText("line 1, column 5");
});

test("documents the current lack of partial output after exceptions", async ({
  page,
}) => {
  await page.goto("./");
  await page
    .locator("#editor")
    .fill("console.log('before'); throw new Error('boom');");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#console")).toHaveText("");
  await expect(page.locator("#diagnostics")).toContainText(
    "javascript-exception",
  );
});

test("drains microtasks before completing a run", async ({ page }) => {
  await page.goto("./");
  await page
    .locator("#editor")
    .fill("Promise.resolve().then(() => console.log('microtask')); 'main';");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#console")).toHaveText("microtask");
  await expect(page.locator("#result")).toHaveText("main");
});

test("handles an unbounded interval without hanging", async ({ page }) => {
  await page.goto("./");
  await page
    .locator("#editor")
    .fill("setInterval(() => console.log('tick'), 0);");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Complete", {
    timeout: 5_000,
  });
  await expect(page.locator("#console")).toContainText("tick");
});

test("rejects source above the worker input limit", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor").fill("x".repeat(100_001));
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#diagnostics")).toContainText("source-too-large");
});

test("rejects oversized source at the worker boundary", async ({ page }) => {
  await page.addInitScript(() => {
    const NativeWorker = window.Worker;
    class OversizedRequestWorker {
      private readonly inner: Worker;

      constructor(url: string | URL, options?: WorkerOptions) {
        this.inner = new NativeWorker(url, options);
      }

      postMessage(message: unknown): void {
        this.inner.postMessage({
          ...(message as Record<string, unknown>),
          source: "x".repeat(100_001),
        });
      }

      terminate(): void {
        this.inner.terminate();
      }

      addEventListener(type: string, listener: EventListener): void {
        this.inner.addEventListener(type, listener);
      }
    }

    Object.defineProperty(window, "Worker", {
      configurable: true,
      value: OversizedRequestWorker,
    });
  });

  await page.goto("./");
  await page.locator("#editor").fill("1;");
  await page.getByRole("button", { name: /Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed", {
    timeout: 5_000,
  });
  await expect(page.locator("#diagnostics")).toContainText("source-too-large");
});


test("lists and loads every generated repository example", async ({ page }) => {
  const generatedExamples = await readGeneratedExamples();
  const expectedValues = Object.keys(generatedExamples);
  const firstValue = expectedValues[0];
  if (firstValue === undefined) {
    throw new Error("Generated repository examples are empty");
  }
  const firstSource = generatedExamples[firstValue];
  if (firstSource === undefined) {
    throw new Error(`Missing generated source for ${firstValue}`);
  }

  await page.goto("./");
  const editor = page.locator("#editor");
  await expect(editor).toHaveValue(firstSource);

  const examplePicker = page.locator("#example");
  const actualValues = await examplePicker.locator("option").evaluateAll(
    options => options.map(option => (option as HTMLOptionElement).value),
  );

  expect(actualValues).toEqual(expectedValues);
  for (const value of expectedValues) {
    await examplePicker.selectOption(value);
    const source = generatedExamples[value];
    if (source === undefined) {
      throw new Error(`Missing generated source for ${value}`);
    }
    await expect(editor).toHaveValue(source);
  }
});