import Foundation

/// スクリーンショットを生成する言語の一覧。
/// (言語コード, リージョン付き言語タグ) の組で、リージョン付きタグはロケール依存表示 (日付等) の再現に使う。
/// 本プロジェクトのローカライズ対象 (en 基準 + ja。.claude/rules/localization-guidelines.md) に合わせて 2 言語とし、
/// 対応言語を増やす時はここに追加する (取り込み元: bannzai/mementomorning の同名ファイル)
let languageCodeAndLanguageWithRegion = [
    ("ja", "ja-JP"),
    ("en", "en-US"),
]

/// 環境変数 SNAPSHOT_LANGUAGES で言語をフィルタリングする。
/// シェルスクリプト側で TEST_RUNNER_SNAPSHOT_LANGUAGES を export すると、
/// xcodebuild がテストランナープロセスに SNAPSHOT_LANGUAGES として引き渡す。
/// 使用例: SNAPSHOT_LANGUAGES="ja" → ja のみ。未設定の場合は全言語を返す
func filteredLanguages() -> [(String, String)] {
    if let languagesEnvironment = ProcessInfo.processInfo.environment["SNAPSHOT_LANGUAGES"],
       !languagesEnvironment.isEmpty {
        let targetLanguages = languagesEnvironment.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let filtered = languageCodeAndLanguageWithRegion.filter { targetLanguages.contains($0.0) }
        // 未対応言語だけが指定された場合に空配列を返すと、テストが 1 枚も撮影せずに成功してしまう。
        // 指定ミスを黙って成功にしないため、ここで落として指定内容を報告する
        precondition(
            !filtered.isEmpty,
            "SNAPSHOT_LANGUAGES に対応していない言語が指定されています: \(languagesEnvironment) (対応言語: \(languageCodeAndLanguageWithRegion.map(\.0).joined(separator: ",")))"
        )
        return filtered
    }
    return languageCodeAndLanguageWithRegion
}
