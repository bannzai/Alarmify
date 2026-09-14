import { describe, expect, it } from "vitest";

/** firebase-functions がデプロイ用のマニフェストに載せる端点の定義を持つ値か */
function hasEndpoint(value: unknown): value is { __endpoint: { serviceAccountEmail?: string | null } } {
  return typeof value === "function" && "__endpoint" in value;
}

describe("Functions の実行サービスアカウント", () => {
  it("公開する全関数が実行専用サービスアカウントで実行される", async () => {
    const exported: unknown[] = Object.values(await import("../src/index.js"));
    const endpoints = exported.filter(hasEndpoint);
    expect(endpoints.length).toBe(7);
    for (const endpoint of endpoints) {
      expect(endpoint.__endpoint.serviceAccountEmail).toBe(
        "functions-runtime@alarmify-prod.iam.gserviceaccount.com",
      );
    }
  });
});
