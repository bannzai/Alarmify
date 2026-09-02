# 0003. GoogleService-Info.plist をリポジトリにコミットする

## Status
Accepted (2026-09-02)

## Context
iOS アプリから Firebase (Auth の匿名認証・FCM) を使うため、`FirebaseApp.configure()` が読む `GoogleService-Info.plist` をアプリのバンドルに含める必要がある。Alarmify のリポジトリは public のため、この plist に含まれる iOS 用 API キー (`AIza...`) と Firebase プロジェクト ID が誰でも読める状態になる。

選択肢は 2 つあった。

1. API キーに制限をかけた上でリポジトリにコミットする
2. `.gitignore` に入れ、base64 を GitHub Secrets に置いて CI で復元する

`GoogleService-Info.plist` の値は「どのプロジェクトのどのアプリか」を示す識別子であり、秘密鍵ではない (Firebase の公式ドキュメントも、この構成ファイルは秘匿情報ではないと明記している)。アプリのバイナリからも取り出せるため、非公開にしても攻撃者に対する防御にはならない。実際の防御は、キーの持ち主を制限することと、バックエンド側の認可で行う。

一方 2 は、開発者が手元に plist を用意する手順と CI での復元手順が増え、Xcode で開いた直後にビルドが通らない状態が常態化する。CI (`.github/workflows/ci.yml`) は fork からの pull request でも動くが、fork では Secrets が渡らないためビルドが落ちる。

## Decision
`Alarmify/GoogleService-Info.plist` をリポジトリにコミットする。あわせて次の制限・防御を置く。

- Firebase が自動作成した iOS 用 API キーに、bundle id の制限をかける (`gcloud services api-keys update <キー> --allowed-bundle-ids=com.bannzai.Alarmify`。適用済み)
- Firestore のセキュリティルールは全パス deny にし、クライアント SDK からの直接アクセスを塞ぐ (#2 で整備)
- ユーザーのデータに触る操作はすべて Cloud Functions 経由にし、Firebase Auth の ID トークンで認可する
- アプリ以外からの Functions 呼び出しは Firebase App Check で弾く (#4)

APNs の認証キー (.p8)、サービスアカウントの秘密鍵、Apple ID / Team ID の実値は従来どおりコミットしない (AGENTS.md「秘匿情報」)。本 ADR が対象にするのは `GoogleService-Info.plist` だけである。

## Consequences

**良い点:**
- clone してそのままビルド・実行できる。fork からの pull request でも CI が通る
- CI に plist 復元の仕組みを持ち込まずに済む

**悪い点 / 引き受けるリスク:**
- Firebase プロジェクト ID と API キーが公開される。bundle id 制限があるため他アプリからの流用はできないが、`identitytoolkit` 等のエンドポイントに対する匿名アカウントの大量作成は API キーだけでは防げない。App Check (#4) の導入までは、この経路が開いたままになる
- API キーをローテーションした場合は plist の差し替えコミットが必要になる
