/**
 * api.signalarm.app に届いた要求を、外部サービス向け API の実体 (Cloud Functions gen2 `alarmsApi` の Cloud Run URL) へ
 * そのまま中継する Cloudflare Worker。方式の選定は documents/adr/0006-api-domain-via-cloudflare-worker.md。
 * パス・クエリ・メソッド・ヘッダー・ボディを変えずに転送し、応答もそのまま返す (認証・レート制限は Functions 側が行う)。
 */

/**
 * 受信した要求を、ホスト名だけを転送先に差し替えた Request にする。
 * `new Request(url, request)` でメソッド・ヘッダー・ボディを引き継ぐ (Host ヘッダーは fetch が転送先に合わせて付け直す)
 */
export function buildOriginRequest(request, originURL) {
  const url = new URL(request.url);
  const origin = new URL(originURL);
  url.protocol = origin.protocol;
  url.host = origin.host;
  return new Request(url, request);
}

export default {
  /** 環境変数 ORIGIN_URL (wrangler.toml の [vars]) の先へ中継する */
  async fetch(request, env) {
    return fetch(buildOriginRequest(request, env.ORIGIN_URL));
  },
};
