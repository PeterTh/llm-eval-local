import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  define: {
    __SITE_BUILD_COMMIT__: JSON.stringify("test-build"),
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    exclude: ["e2e/**", "node_modules/**", "dist/**"],
    restoreMocks: true,
    coverage: { reporter: ["text", "html"] },
  },
});
