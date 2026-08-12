/// <reference types="vite/client" />

const exampleSources = import.meta.glob("../generated/examples/*.js", {
  eager: true,
  import: "default",
  query: "?raw",
}) as Record<string, string>;

function exampleName(path: string): string {
  const fileName = path.split("/").pop();
  if (!fileName || !fileName.endsWith(".js")) {
    throw new Error(`Invalid example path: ${path}`);
  }
  return fileName.slice(0, -".js".length);
}

export const examples: Record<string, string> = Object.fromEntries(
  Object.entries(exampleSources).map(([path, source]) => [
    exampleName(path),
    source,
  ]),
);
