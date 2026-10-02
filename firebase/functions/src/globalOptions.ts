import { setGlobalOptions } from "firebase-functions";

/**
 * 全関数を実行専用サービスアカウントで動かす。既定の Compute Engine サービスアカウントはプロジェクトの Editor を持つため、
 * Firestore / FCM / Auth / Secret の読み取りに絞った SA へ分離する (SA の作成と付与は documents/functions-deploy.md)。
 * 本番プロジェクトは alarmify-prod だけなのでメールアドレスを固定する。`functions-runtime@` の省略記法は firebase-tools が
 * Functions API 向けにだけ展開し、Secret のアクセス権付与と Cloud Scheduler の OIDC には未展開のまま渡すため使わない。
 * エミュレータ (demo-alarmify) はこの値を使わない。
 *
 * index.ts の本文ではなく、index.ts が最初に import する独立したモジュールにしているのは、関数を定義する他のモジュール
 * (lib/crashlyticsAlert など、index.ts から再 export するもの) より先に必ず評価させるため。firebase-functions v2 は
 * 関数を定義した時点の global options を端点の定義 (__endpoint) に写すので、ESM のように import を本文より先に評価する
 * 読み込み方 (vitest) では、本文の setGlobalOptions が再 export 先の関数定義に間に合わず serviceAccount が抜ける
 */
setGlobalOptions({
  region: "asia-northeast1",
  maxInstances: 10,
  serviceAccount: "functions-runtime@alarmify-prod.iam.gserviceaccount.com",
});
