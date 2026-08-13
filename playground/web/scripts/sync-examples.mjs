import {
  copyFile,
  mkdir,
  readFile,
  readdir,
  rm,
} from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compareExampleSources } from "../src/playground-contracts.ts";

const webDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceDirectory = resolve(webDirectory, "../../example");
const destinationDirectory = resolve(webDirectory, "generated/examples");

async function readExampleSources(directory) {
  const fileNames = (await readdir(directory, { withFileTypes: true }))
    .filter(entry => entry.isFile() && entry.name.endsWith(".js"))
    .map(entry => entry.name)
    .sort();
  const entries = await Promise.all(
    fileNames.map(async fileName => [
      fileName.slice(0, -".js".length),
      await readFile(resolve(directory, fileName), "utf8"),
    ]),
  );
  return Object.fromEntries(entries);
}

await rm(destinationDirectory, { recursive: true, force: true });
await mkdir(destinationDirectory, { recursive: true });

const entries = await readdir(sourceDirectory, { withFileTypes: true });
for (const entry of entries) {
  if (!entry.isFile() || !entry.name.endsWith(".js")) continue;
  await copyFile(
    resolve(sourceDirectory, entry.name),
    resolve(destinationDirectory, entry.name),
  );
}

const comparison = compareExampleSources(
  await readExampleSources(sourceDirectory),
  await readExampleSources(destinationDirectory),
);
if (
  comparison.missing.length > 0 ||
  comparison.unexpected.length > 0 ||
  comparison.changed.length > 0
) {
  throw new Error(`Example synchronization failed: ${JSON.stringify(comparison)}`);
}
