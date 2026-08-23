import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import { createServer } from "node:http";
import { extname, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const webRoot = resolve(fileURLToPath(new URL("..", import.meta.url)));
const distRoot = resolve(webRoot, "dist");
const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const basePath = process.env.GITHUB_ACTIONS === "true" && repositoryName ? `/${repositoryName}/` : "/";
const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"], [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"], [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"], [".png", "image/png"], [".map", "application/json; charset=utf-8"],
]);

export function createPreviewServer() {
  return createServer(async (request, response) => {
    try {
      const pathname = decodeURIComponent(new URL(request.url ?? "/", "http://localhost").pathname);
      if (!pathname.startsWith(basePath)) {
        response.writeHead(404).end("Not found");
        return;
      }
      let relativePath = pathname.slice(basePath.length);
      if (!relativePath || relativePath.endsWith("/")) relativePath += "index.html";
      const target = resolve(distRoot, relativePath);
      if (target !== distRoot && !target.startsWith(`${distRoot}${sep}`)) {
        response.writeHead(403).end("Forbidden");
        return;
      }
      const metadata = await stat(target);
      if (!metadata.isFile()) throw new Error("not a file");
      response.writeHead(200, {
        "Content-Type": mimeTypes.get(extname(target)) ?? "application/octet-stream",
        "Content-Length": metadata.size,
        "Cache-Control": /\.[0-9a-zA-Z_-]{8,}\./.test(relativePath) ? "public, max-age=31536000, immutable" : "no-store",
      });
      if (request.method === "HEAD") response.end();
      else createReadStream(target).pipe(response);
    } catch {
      response.writeHead(404).end("Not found");
    }
  });
}

export const previewBasePath = basePath;

if (resolve(process.argv[1] ?? "") === fileURLToPath(import.meta.url)) {
  const server = createPreviewServer();
  const shutdown = () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1_000).unref();
  };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
  server.listen(4173, "127.0.0.1", () => console.log(`Preview: http://127.0.0.1:4173${basePath}`));
}
