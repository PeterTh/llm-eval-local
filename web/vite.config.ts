import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const repositoryName = process.env.GITHUB_REPOSITORY?.split("/")[1];
const base = process.env.GITHUB_ACTIONS === "true" && repositoryName
  ? `/${repositoryName}/`
  : "/";

export default defineConfig({
  base,
  plugins: [react()],
  define: {
    __SITE_BUILD_COMMIT__: JSON.stringify(process.env.GITHUB_SHA ?? "local-working-tree"),
  },
  build: {
    sourcemap: true,
  },
  server: {
    host: "127.0.0.1",
  },
});
