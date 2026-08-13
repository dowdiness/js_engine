import { expect, test } from "@playwright/test";

test("runs source and keeps output text-only", async ({ page }) => {
  await page.goto("./");
  await page.locator("#editor").fill("console.log('<img src=x>'); 6 * 7;");
  await page.getByRole("button", { name: /^Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Complete");
  await expect(page.locator("#console")).toHaveText("<img src=x>");
  await expect(page.locator("#result")).toHaveText("42");
  await expect(page.locator("#console img")).toHaveCount(0);
});

test("stops a runaway run and recovers", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor");
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
  const editor = page.locator("#editor");
  const run = page.getByRole("button", { name: /^Run/ });
  const status = page.locator("#status");

  await editor.fill("while (true) {};");
  await run.click();
  await expect(status).toHaveText("Execution terminated", {
    timeout: 5_000,
  });

  await editor.fill("41 + 1;");
  await run.click();
  await expect(status).toHaveText("Complete");
  await expect(page.locator("#result")).toHaveText("42");
});

test("starts each run in a fresh realm", async ({ page }) => {
  await page.goto("./");
  const editor = page.locator("#editor");
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
  await page.locator("#editor").fill("let =");
  await page.getByRole("button", { name: /^Run/ }).click();

  await expect(page.locator("#status")).toHaveText("Failed");
  await expect(page.locator("#diagnostics")).toContainText("parse-error");
});