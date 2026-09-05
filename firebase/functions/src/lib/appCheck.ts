import type { NextFunction, Request, Response } from "express";
import { logger } from "firebase-functions";
import type { Deps } from "./deps.js";
import { ApiError } from "./errors.js";

/**
 * App Check の適用段階。強制適用は「監視のみ → 強制」の順で切り替える
 * - monitor: 未検証のリクエストを warn ログに残して通す
 * - enforce: 未検証のリクエストを 401 で拒否する
 */
export type AppCheckEnforcementMode = "monitor" | "enforce";

/**
 * 既定は監視のみ。アプリ側の App Attest を載せた版が行き渡る前に強制すると、
 * 更新前のアプリからの正当なリクエストまで落ちるため、段階適用の初期状態を既定にする
 */
export const defaultAppCheckEnforcementMode: AppCheckEnforcementMode = "monitor";

export function parseAppCheckEnforcementMode(value: string | undefined): AppCheckEnforcementMode {
  return value === "enforce" || value === "monitor" ? value : defaultAppCheckEnforcementMode;
}

/** App Check トークンを載せるヘッダー。Firebase の SDK と Callable が使う標準の名前に揃える */
export const APP_CHECK_HEADER = "X-Firebase-AppCheck";

/**
 * App Check トークンを検証する Express ミドルウェア。
 * monitor では拒否せず、未検証のリクエストを固定のメッセージでログに残す。
 * 強制適用へ切り替える前に、正当なクライアントからの未検証リクエストが残っていないかを
 * Cloud Logging で確認できるようにするため (トークンの値そのものは残さない)
 */
export function requireAppCheck(deps: Deps) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const enforcing = deps.appCheckEnforcementMode() === "enforce";
    const appCheckToken = req.header(APP_CHECK_HEADER);
    if (!appCheckToken) {
      if (enforcing) {
        next(
          new ApiError(
            401,
            "app_check_required",
            `${APP_CHECK_HEADER} ヘッダー (App Check トークン) が必要です`,
          ),
        );
        return;
      }
      logger.warn("app check token missing", { path: req.path });
      next();
      return;
    }
    try {
      res.locals.appId = (await deps.verifyAppCheckToken(appCheckToken)).appId;
    } catch (error) {
      if (enforcing) {
        next(new ApiError(401, "app_check_invalid", "App Check トークンを検証できませんでした"));
        return;
      }
      logger.warn("app check token invalid", { path: req.path, error: String(error) });
    }
    next();
  };
}
