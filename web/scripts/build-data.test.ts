import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterEach, describe, expect, it } from "vitest";

import { readImplementationAnalyses } from "./build-data";

const temporaryDirectories: string[] = [];

async function analysisDirectory(): Promise<string> {
  const directory = await mkdtemp(join(tmpdir(), "llm-eval-analysis-"));
  temporaryDirectories.push(directory);
  return directory;
}

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) => rm(directory, { recursive: true, force: true })));
});

describe("implementation analysis data generation", () => {
  it("preserves valid Markdown under the filename run ID", async () => {
    const directory = await analysisDirectory();
    const markdown = "# `bench_model_backend_r1`\n\n## Scope\n\nVerified finding.\n";
    await writeFile(join(directory, "bench_model_backend_r1.md"), markdown, "utf8");

    const analyses = await readImplementationAnalyses(directory);

    expect([...analyses]).toEqual([["bench_model_backend_r1", markdown]]);
  });

  it.each([
    ["empty content", "", /is empty/],
    ["a mismatched title", "# `different_run`\n\nFinding.\n", /title does not match/],
    ["a missing body", "# `bench_model_backend_r1`\n", /has no body/],
  ])("rejects %s", async (_description, markdown, message) => {
    const directory = await analysisDirectory();
    await writeFile(join(directory, "bench_model_backend_r1.md"), markdown, "utf8");

    await expect(readImplementationAnalyses(directory)).rejects.toThrow(message);
  });
});
