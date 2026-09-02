import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    // エミュレータの起動直後は Functions の読み込みに時間がかかるため、既定の 5 秒では足りない
    testTimeout: 60_000,
    hookTimeout: 60_000,
    // Firestore / Auth のエミュレータを共有するため、ファイル間の並列実行はしない
    fileParallelism: false,
  },
});
