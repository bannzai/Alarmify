import type { NextFunction, Request, Response } from "express";
import type { z } from "zod";

/** API のエラー応答。body は { error: { code, message } } に揃える */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

export function badRequestFromZod(error: z.ZodError): ApiError {
  const detail = error.issues
    .map((issue) => `${issue.path.join(".") || "(root)"}: ${issue.message}`)
    .join(", ");
  return new ApiError(400, "invalid_argument", detail);
}

function isJsonParseFailure(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { type?: unknown }).type === "entity.parse.failed"
  );
}

/** Express のエラーハンドラ。ApiError 以外は 500 に丸め、詳細はログにだけ残す */
export function errorHandler(
  error: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
): void {
  if (error instanceof ApiError) {
    res.status(error.status).json({ error: { code: error.code, message: error.message } });
    return;
  }
  if (isJsonParseFailure(error)) {
    res.status(400).json({ error: { code: "invalid_argument", message: "JSON の形式が不正です" } });
    return;
  }
  console.error("unexpected error", error);
  res.status(500).json({ error: { code: "internal", message: "内部エラーが発生しました" } });
}

export function notFoundHandler(_req: Request, res: Response): void {
  res.status(404).json({ error: { code: "not_found", message: "エンドポイントが見つかりません" } });
}
