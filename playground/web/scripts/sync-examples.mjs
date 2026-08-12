import { copyFile, mkdir, readdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const webDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceDirectory = resolve(webDirectory, "../../example");
const destinationDirectory = resolve(webDirectory, "generated/examples");

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
