import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // Firestore エミュレータの同一ドキュメントを複数ファイルが同時に触らないよう直列実行する
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
