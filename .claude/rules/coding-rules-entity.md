---
paths:
  - "Alarmify/**/*.swift"
  - "AlarmifyNotificationService/**/*.swift"
---

# コーディングルール (データ層)

push payload・永続化データ・API レスポンスなどデータ層に関するコーディングルール。取り込み元: bannzai/mementomorning の同名ルール (SwiftData 固有の項目は本プロジェクトの DB 方針が確定してから取り込む)。

## ドキュメントコメント

- struct, class, enum の宣言直前に `///` のドキュメントコメントを書き、そのデータ型が何を表し、どう使われるかを説明する

## 命名規則

- 変数名には通常、動詞 (editing, selected 等) をつけない。Feature 名が役割を表すため名詞だけでよい。必要な場合はコメントで理由を明記する
- `@AppStorage` の変数名は key 名と一致させる (`@AppStorage(.apnsDeviceToken) var apnsDeviceToken`)。どの UserDefaults キーを使っているか一目で分かるようにするため

## 外部入力の境界

- サーバー・push から受け取る JSON は、境界で 1 度だけ型付きの struct (`AlarmRequest` 等) に変換し、以降は辞書を引き回さない。変換に失敗した入力は nil / エラーで弾き、既定値で補わない
- 文字列とローカライゼーション: 永続化されるデータの表示用文字列は `String(localized:)` を使う (外部サービスからの文言・ユーザーの自由入力値は除く)

## プロパティ設計

- enum やフラグで使うプロパティが変わる場合、保存側で「使わない方を nil にする」処理は不要。そのまま保存し、使用側で enum / flag を switch して適切なプロパティを使う。使用方法はコメントで明記する
- enum に `var label: String` / `var systemImage: String` のような表示用プロパティを持たせない。enum は純粋なデータ型にし、表示ロジックは使用側 (View) の switch で判定する
