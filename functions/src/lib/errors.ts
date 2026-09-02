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

/**
 * body-parser (express.json) が投げるエラー。
 * 大きすぎるボディの 413 など、クライアント側の誤りをサーバーエラーに丸めない
 */
function clientBodyFailure(error: unknown): ApiError | null {
  if (typeof error !== "object" || error === null) {
    return null;
  }
  const { status, type } = error as { status?: unknown; type?: unknown };
  if (typeof type !== "string" || !type.startsWith("entity.")) {
    return null;
  }
  if (typeof status !== "number" || status < 400 || status >= 500) {
    return null;
  }
  return type === "entity.too.large"
    ? new ApiError(status, "payload_too_large", "リクエストボディが大きすぎます")
    : new ApiError(status, "invalid_argument", "リクエストボディの形式が不正です");
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
  const bodyFailure = clientBodyFailure(error);
  if (bodyFailure) {
    res
      .status(bodyFailure.status)
      .json({ error: { code: bodyFailure.code, message: bodyFailure.message } });
    return;
  }
  console.error("unexpected error", error);
  res.status(500).json({ error: { code: "internal", message: "内部エラーが発生しました" } });
}

export function notFoundHandler(_req: Request, res: Response): void {
  res.status(404).json({ error: { code: "not_found", message: "エンドポイントが見つかりません" } });
}
