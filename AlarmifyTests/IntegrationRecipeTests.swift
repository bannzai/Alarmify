import XCTest
@testable import Alarmify

/// 連携レシピのスニペットに API トークンが埋め込まれることのテスト
final class IntegrationRecipeTests: XCTestCase {
    func testTokenIsEmbeddedInEveryRecipe() {
        let token = "alm_test_token_123"

        for recipe in IntegrationRecipe.allCases {
            let bodies = recipe.snippets(apiToken: token, backend: .production).map(\.body)
            XCTAssertTrue(bodies.contains { $0.contains(token) }, "\(recipe) has no snippet containing the token")
            XCTAssertFalse(bodies.contains { $0.contains("{{API_TOKEN}}") }, "\(recipe) left the token marker unreplaced")
            XCTAssertFalse(bodies.contains { $0.contains(IntegrationRecipe.apiTokenPlaceholder) }, "\(recipe) still shows the placeholder")
        }
    }

    func testPlaceholderIsUsedWhenTokenIsMissing() {
        for recipe in IntegrationRecipe.allCases {
            let bodies = recipe.snippets(apiToken: nil, backend: .production).map(\.body)
            XCTAssertTrue(bodies.contains { $0.contains(IntegrationRecipe.apiTokenPlaceholder) }, "\(recipe) has no snippet containing the placeholder")
        }
    }

    func testEveryRecipeCallsTheAlarmsEndpoint() {
        for recipe in IntegrationRecipe.allCases {
            let bodies = recipe.snippets(apiToken: nil, backend: .production).map(\.body)
            XCTAssertTrue(bodies.contains { $0.contains(IntegrationRecipe.endpoint(for: .production)) }, "\(recipe) does not reference the endpoint")
        }
    }

    func testSnippetLabelsAreUniqueWithinRecipe() {
        for recipe in IntegrationRecipe.allCases {
            let labels = recipe.snippets(apiToken: nil, backend: .production).map(\.label)
            XCTAssertEqual(labels.count, Set(labels).count, "\(recipe) has duplicate snippet labels")
        }
    }

    func testEndpointFollowsTheSelectedBackend() {
        let bodies = IntegrationRecipe.shell.snippets(apiToken: nil, backend: .emulator).map(\.body)
        XCTAssertTrue(bodies.contains { $0.contains("http://127.0.0.1:5001/demo-alarmify/asia-northeast1/api/v1/alarms") })
        XCTAssertFalse(bodies.contains { $0.contains("alarmify-prod") })
    }

    func testDocumentationURLPointsToRecipesSite() {
        XCTAssertEqual(IntegrationRecipe.githubActions.documentationURL.absoluteString, "https://bannzai.github.io/Alarmify/recipes/github-actions")
        XCTAssertEqual(IntegrationRecipe.shell.documentationURL.absoluteString, "https://bannzai.github.io/Alarmify/recipes/cron")
    }
}
