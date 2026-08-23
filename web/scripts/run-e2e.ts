import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { createPreviewServer, previewBasePath } from "./serve-dist.ts";

const webRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const playwrightCli = resolve(webRoot, "node_modules", "@playwright", "test", "cli.js");
const server = createPreviewServer();

await new Promise<void>((resolveListen, reject) => {
  server.once("error", reject);
  server.listen(4173, "127.0.0.1", () => {
    console.log(`Test preview: http://127.0.0.1:4173${previewBasePath}`);
    resolveListen();
  });
});

const exitCode = await new Promise<number>((resolveExit, reject) => {
  const child = spawn(process.execPath, [playwrightCli, "test"], {
    cwd: webRoot,
    stdio: "inherit",
    env: { ...process.env, PLAYWRIGHT_EXTERNAL_SERVER: "true" },
  });
  child.once("error", reject);
  child.once("exit", (code) => resolveExit(code ?? 1));
});

await new Promise<void>((resolveClose) => server.close(() => resolveClose()));
process.exitCode = exitCode;
