import { expect, test } from "@playwright/test";

test("runs source and keeps output text-only", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor .cm-content").fill("console.log('<img src=x>'); 6 * 7;");
  await page.getByRole("button", { name: /^Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#console")).toHaveText("<img src=x>");
  await expect(page.locator("#result")).toHaveText("42");
  await expect(page.locator("#console img")).toHaveCount(0);
});

test("accepts the selected completion with Tab", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");

  await editor.fill("");
  await editor.pressSequentially("tru");
  await expect(page.locator(".cm-tooltip-autocomplete")).toBeVisible();
  await expect(
    page.locator(".cm-tooltip-autocomplete .cm-completionLabel").first(),
  ).toHaveText("true");

  await editor.press("Tab");
  await expect(editor).toHaveText("true");
});

test("uses Tab for indentation when completion is closed", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const completion = page.locator(".cm-tooltip-autocomplete");

  await editor.fill("if (true) {\n");
  await expect(completion).toHaveCount(0);

  await editor.press("Tab");
  await expect
    .poll(() => editor.evaluate(element => element.textContent))
    .toBe("if (true) {  ");
});

test("stops a runaway run and recovers", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const run = page.getByRole("button", { name: /^Run/ });
  const status = page.locator("#status");

  await editor.fill("while (true) {};");
  await run.click();
  await expect(status).toHaveText("Running");

  await page.getByRole("button", { name: "Stop" }).click();
  await expect(status).toHaveText("Stopped");

  await editor.fill("41 + 1;");
  await run.click();
  await expect(status).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("42");
});

test("recovers after a timeout", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const run = page.getByRole("button", { name: /^Run/ });
  const status = page.locator("#status");

  await editor.fill("while (true) {};");
  await run.click();
  await expect(status).toHaveText("Execution terminated", {
    timeout: 5_000,
  });
  await expect(page.locator("#diagnostics")).toHaveText(
    "The worker exceeded the 3 second wall-clock limit and was replaced.",
  );

  await editor.fill("41 + 1;");
  await run.click();
  await expect(status).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("42");
});

test("starts each run in a fresh realm", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const run = page.getByRole("button", { name: /^Run/ });

  await editor.fill("globalThis.playgroundValue = 42; 'set';");
  await run.click();
  await expect(page.locator("#result")).toHaveText("set");

  await editor.fill("typeof globalThis.playgroundValue;");
  await run.click();
  await expect(page.locator("#result")).toHaveText("undefined");
});

test("shows parse diagnostics", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor .cm-content").fill("let =");
  await page.getByRole("button", { name: /^Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#diagnostics")).toContainText("parse-error");
});

 test("marks the failed source range inside CodeMirror", async ({ page }) => {
   await page.goto("./");
   await page.locator("#editor .cm-content").fill("let =");
   await page.getByRole("button", { name: /^Run/ }).click();

   await expect(page.locator(".cm-lintRange-error")).toHaveCount(1);
   await expect(page.locator(".cm-lint-marker-error")).toHaveCount(1);
 });

test("clears stale diagnostics after editing and completing a run", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const run = page.getByRole("button", { name: /^Run/ });

  await editor.fill("let =");
  await run.click();
  await expect(page.locator(".cm-lint-marker-error")).toHaveCount(1);

  await editor.fill("1 + 1;");
  await expect(page.locator(".cm-lint-marker-error")).toHaveCount(0);
  await expect(page.locator(".cm-lintRange-error")).toHaveCount(0);
  await run.click();
  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator(".cm-lint-marker-error")).toHaveCount(0);
  await expect(page.locator(".cm-lintRange-error")).toHaveCount(0);
});

 test("offers js_engine APIs in completion", async ({ page }) => {
   await page.goto("./");
   const editor = page.locator("#editor .cm-content");

   await editor.fill("");
   await editor.pressSequentially("setTi");
   await expect(page.locator(".cm-tooltip-autocomplete")).toBeVisible();
   await expect(
     page.locator(".cm-tooltip-autocomplete .cm-completionLabel").filter({
       hasText: "setTimeout",
     }),
   ).toHaveCount(1);
   await expect(
     page.locator(".cm-tooltip-autocomplete .cm-completionDetail").filter({
       hasText: "timer",
     }),
   ).toHaveCount(1);
 });

test("offers installed realm globals in completion", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor .cm-content");
  const requiredGlobals = [
    ["globalT", "globalThis"],
    ["unde", "undefined"],
    ["NaN", "NaN"],
    ["Inf", "Infinity"],
    ["Obj", "Object"],
    ["Arr", "Array"],
    ["Sym", "Symbol"],
    ["Uint8A", "Uint8Array"],
    ["BigInt6", "BigInt64Array"],
    ["BigUint", "BigUint64Array"],
  ] as const;

  for (const [prefix, label] of requiredGlobals) {
    await editor.fill("");
    await editor.pressSequentially(prefix);
    await expect(page.locator(".cm-tooltip-autocomplete")).toBeVisible();
    await expect(
      page.locator(".cm-tooltip-autocomplete .cm-completionLabel").filter({
        hasText: new RegExp(`^${label}$`),
      }),
    ).toHaveCount(1);
  }
});

 test("shows js_engine API documentation on hover", async ({ page }) => {
   await page.goto("./");
   const editor = page.locator("#editor .cm-content");

   await editor.fill("setTimeout");
   const line = page.locator("#editor .cm-line").first();
   await line.hover({ position: { x: 32, y: 8 } });

   await expect(page.locator(".cm-tooltip-hover")).toContainText(
     "Schedules a timer callback",
   );
 });

 test("shows cursor position and UTF-16 source length", async ({ page }) => {
   await page.goto("./");
   const editor = page.locator("#editor .cm-content");
   await expect(page.locator("#cursor-position")).toHaveText("Ln 1, Col 1");
   await expect(page.locator("#source-length")).toHaveText(
     /^\d+ \/ 100,000 UTF-16$/,
   );

   await editor.fill("foo\nbar");
   await editor.press("Control+End");
   await expect(page.locator("#cursor-position")).toHaveText("Ln 2, Col 4");
   await expect(page.locator("#source-length")).toHaveText(
     "7 / 100,000 UTF-16",
   );
 });