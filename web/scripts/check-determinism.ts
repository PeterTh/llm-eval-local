import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { buildData } from "./build-data";

const webRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const outputRoots = [resolve(webRoot, "public", "data"), resolve(webRoot, "src", "generated")];

async function filesUnder(root: string): Promise<string[]> {
  const entries = await readdir(root, { withFileTypes: true });
  const files = await Promise.all(entries.map(async (entry) => {
    const path = resolve(root, entry.name);
    return entry.isDirectory() ? filesUnder(path) : [path];
  }));
  return files.flat().sort((left, right) => left.localeCompare(right, "en"));
}

async function outputDigest(): Promise<string> {
  const hash = createHash("sha256");
  for (const root of outputRoots) {
    for (const path of await filesUnder(root)) {
      hash.update(relative(webRoot, path).replaceAll("\\", "/"));
      hash.update("\0");
      hash.update(await readFile(path));
      hash.update("\0");
    }
  }
  return hash.digest("hex");
}

await buildData();
const first = await outputDigest();
await buildData();
const second = await outputDigest();
if (first !== second) throw new Error(`generated output is nondeterministic: ${first} != ${second}`);
console.log(`Deterministic generated output: ${first}`);
