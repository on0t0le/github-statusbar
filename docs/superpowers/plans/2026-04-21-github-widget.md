# GitHub PR Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menubar-only app that shows GitHub PRs assigned to or involving the user, grouped by category, refreshing every 5 minutes.

**Architecture:** `NSStatusItem` + SwiftUI `NSPopover` wired in `AppDelegate`. `GitHubService` fetches PRs via GitHub REST Search API (4 queries, `async/await`). `PRStore` (`ObservableObject`) holds categorized state and runs the 5-min timer. PAT stored in Keychain.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (`NSStatusItem`, `NSPopover`), Security framework (Keychain), `URLSession` async/await, Combine, xcodegen.

---

## File Map

| File | Responsibility |
|------|---------------|
| `project.yml` | xcodegen project config |
| `GitHubWidget/App/GitHubWidgetApp.swift` | `@main` App entry point |
| `GitHubWidget/App/AppDelegate.swift` | `NSStatusItem`, `NSPopover`, badge, timer |
| `GitHubWidget/Models/PullRequest.swift` | `PullRequest`, `GitHubUser`, `GitHubLabel`, `GitHubSearchResponse`, `PRFetchResult` |
| `GitHubWidget/Services/GitHubError.swift` | `GitHubError` enum with user-facing messages |
| `GitHubWidget/Services/GitHubService.swift` | `URLSessionProtocol`, `GitHubServiceProtocol`, `GitHubService` actor |
| `GitHubWidget/Store/PRStore.swift` | `PRStore` `ObservableObject`, categorization, diff stub |
| `GitHubWidget/Views/PopoverView.swift` | `PopoverView`, `SectionHeaderView` |
| `GitHubWidget/Views/PRRowView.swift` | `PRRowView` |
| `GitHubWidget/Views/SettingsView.swift` | `SettingsView` |
| `GitHubWidget/Utilities/KeychainHelper.swift` | PAT Keychain read/write/delete |
| `GitHubWidgetTests/PullRequestTests.swift` | Model + `PRFetchResult` unit tests |
| `GitHubWidgetTests/KeychainHelperTests.swift` | Keychain unit tests |
| `GitHubWidgetTests/GitHubServiceTests.swift` | Service tests with mock `URLSession` |
| `GitHubWidgetTests/PRStoreTests.swift` | Store tests with mock service |
| `README.md` | Setup and usage instructions |

---

## Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `GitHubWidget/` directory tree
- Create: `GitHubWidgetTests/` directory

- [ ] **Step 1: Install xcodegen**

```bash
brew install xcodegen
```

Expected output: `xcodegen` installed or already up to date.

- [ ] **Step 2: Create project.yml**

Create `/Users/on0t0le/projects/personal/github-widget/project.yml`:

```yaml
name: GitHubWidget
options:
  bundleIdPrefix: com.github-widget
  deploymentTarget:
    macOS: "13.0"
targets:
  GitHubWidget:
    type: application
    platform: macOS
    sources:
      - path: GitHubWidget
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.github-widget.GitHubWidget
        MACOSX_DEPLOYMENT_TARGET: "13.0"
        LSUIElement: YES
    info:
      path: GitHubWidget/Info.plist
      properties:
        LSUIElement: YES
        NSHumanReadableCopyright: ""
  GitHubWidgetTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: GitHubWidgetTests
    dependencies:
      - target: GitHubWidget
    settings:
      base:
        MACOSX_DEPLOYMENT_TARGET: "13.0"
```

- [ ] **Step 3: Create source directories**

```bash
mkdir -p GitHubWidget/App
mkdir -p GitHubWidget/Models
mkdir -p GitHubWidget/Services
mkdir -p GitHubWidget/Store
mkdir -p GitHubWidget/Views
mkdir -p GitHubWidget/Utilities
mkdir -p GitHubWidgetTests
```

- [ ] **Step 4: Run xcodegen**

```bash
xcodegen generate
```

Expected: `GitHubWidget.xcodeproj` created with no errors.

- [ ] **Step 5: Verify project opens**

```bash
open GitHubWidget.xcodeproj
```

Expected: Xcode opens, shows `GitHubWidget` and `GitHubWidgetTests` targets.

- [ ] **Step 6: Commit scaffold**

```bash
git init
git add project.yml GitHubWidget.xcodeproj .gitignore
git commit -m "chore: scaffold xcodegen project"
```

---

## Task 2: PullRequest Model + PRFetchResult

**Files:**
- Create: `GitHubWidgetTests/PullRequestTests.swift`
- Create: `GitHubWidget/Models/PullRequest.swift`

- [ ] **Step 1: Write failing tests**

Create `GitHubWidgetTests/PullRequestTests.swift`:

```swift
import XCTest
@testable import GitHubWidget

final class PullRequestTests: XCTestCase {

    // MARK: - JSON decoding

    func test_pullRequest_decodesFromJSON() throws {
        let json = """
        {
            "id": 1,
            "number": 42,
            "title": "Fix auth bug",
            "html_url": "https://github.com/org/repo/pull/42",
            "repository_url": "https://api.github.com/repos/org/repo",
            "draft": false,
            "labels": [],
            "user": { "login": "bob", "avatar_url": "https://avatars.githubusercontent.com/u/1" }
        }
        """.data(using: .utf8)!

        let pr = try JSONDecoder().decode(PullRequest.self, from: json)

        XCTAssertEqual(pr.id, 1)
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Fix auth bug")
        XCTAssertEqual(pr.htmlUrl, "https://github.com/org/repo/pull/42")
        XCTAssertEqual(pr.user.login, "bob")
        XCTAssertFalse(pr.draft)
    }

    func test_pullRequest_repoName_extractsFromRepositoryUrl() {
        let pr = PullRequest.fixture(repositoryUrl: "https://api.github.com/repos/myorg/myrepo")
        XCTAssertEqual(pr.repoName, "myorg/myrepo")
    }

    func test_pullRequest_repoName_fallsBackWhenUrlMalformed() {
        let pr = PullRequest.fixture(repositoryUrl: "bad-url")
        XCTAssertEqual(pr.repoName, "bad-url")
    }

    // MARK: - PRFetchResult categorization

    func test_fetchResult_waitingOnMe_deduplicatesAcrossQueries() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [pr],
            assigned: [],
            readyToMerge: []
        )
        XCTAssertEqual(result.waitingOnMe.count, 1)
    }

    func test_fetchResult_readyToMerge_excludesWaitingOnMe() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [],
            assigned: [],
            readyToMerge: [pr]
        )
        XCTAssertTrue(result.readyToMergeDeduped.isEmpty)
    }

    func test_fetchResult_inProgress_excludesWaitingAndReady() {
        let waiting = PullRequest.fixture(id: 1)
        let ready = PullRequest.fixture(id: 2)
        let inProgressPR = PullRequest.fixture(id: 3)
        let result = PRFetchResult(
            reviewRequested: [waiting],
            changesRequested: [],
            assigned: [waiting, ready, inProgressPR],
            readyToMerge: [ready]
        )
        XCTAssertEqual(result.inProgress.count, 1)
        XCTAssertEqual(result.inProgress[0].id, 3)
    }

    func test_fetchResult_allPRs_deduplicatesAll() {
        let pr = PullRequest.fixture(id: 1)
        let result = PRFetchResult(
            reviewRequested: [pr],
            changesRequested: [pr],
            assigned: [pr],
            readyToMerge: [pr]
        )
        XCTAssertEqual(result.allPRs.count, 1)
    }
}

// MARK: - Fixtures

extension PullRequest {
    static func fixture(
        id: Int = 1,
        number: Int = 1,
        title: String = "Test PR",
        htmlUrl: String = "https://github.com/org/repo/pull/1",
        repositoryUrl: String = "https://api.github.com/repos/org/repo",
        draft: Bool = false
    ) -> PullRequest {
        PullRequest(
            id: id,
            number: number,
            title: title,
            htmlUrl: htmlUrl,
            repositoryUrl: repositoryUrl,
            user: GitHubUser(login: "testuser", avatarUrl: "https://example.com/avatar.png"),
            draft: draft,
            labels: []
        )
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/PullRequestTests 2>&1 | tail -20
```

Expected: compile error — `PullRequest` not defined.

- [ ] **Step 3: Implement PullRequest model**

Create `GitHubWidget/Models/PullRequest.swift`:

```swift
import Foundation

struct PullRequest: Identifiable, Equatable, Codable {
    let id: Int
    let number: Int
    let title: String
    let htmlUrl: String
    let repositoryUrl: String
    let user: GitHubUser
    let draft: Bool
    let labels: [GitHubLabel]

    var repoName: String {
        let parts = repositoryUrl.split(separator: "/")
        guard parts.count >= 2 else { return repositoryUrl }
        return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, draft, labels, user
        case htmlUrl = "html_url"
        case repositoryUrl = "repository_url"
    }
}

struct GitHubUser: Codable, Equatable {
    let login: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

struct GitHubLabel: Codable, Equatable {
    let name: String
    let color: String
}

struct GitHubSearchResponse: Codable {
    let totalCount: Int
    let items: [PullRequest]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case items
    }
}

struct PRFetchResult {
    let reviewRequested: [PullRequest]
    let changesRequested: [PullRequest]
    let assigned: [PullRequest]
    let readyToMerge: [PullRequest]

    var waitingOnMe: [PullRequest] {
        deduplicated(reviewRequested + changesRequested)
    }

    var readyToMergeDeduped: [PullRequest] {
        let waitingIds = Set(waitingOnMe.map(\.id))
        return deduplicated(readyToMerge.filter { !waitingIds.contains($0.id) })
    }

    var inProgress: [PullRequest] {
        let excludedIds = Set((waitingOnMe + readyToMergeDeduped).map(\.id))
        return deduplicated(assigned.filter { !excludedIds.contains($0.id) })
    }

    var allPRs: [PullRequest] {
        deduplicated(reviewRequested + changesRequested + assigned + readyToMerge)
    }

    private func deduplicated(_ prs: [PullRequest]) -> [PullRequest] {
        var seen = Set<Int>()
        return prs.filter { seen.insert($0.id).inserted }
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/PullRequestTests 2>&1 | tail -10
```

Expected: `TEST SUCCEEDED` with all tests passing.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Models/PullRequest.swift GitHubWidgetTests/PullRequestTests.swift
git commit -m "feat: add PullRequest model and PRFetchResult categorization"
```

---

## Task 3: GitHubError

**Files:**
- Create: `GitHubWidget/Services/GitHubError.swift`

- [ ] **Step 1: Create GitHubError**

Create `GitHubWidget/Services/GitHubError.swift`:

```swift
import Foundation

enum GitHubError: Error, Equatable {
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case networkError
    case decodingError

    var userMessage: String {
        switch self {
        case .notConfigured:
            return "Add token in Settings"
        case .unauthorized:
            return "Invalid token — check Settings"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited, retry in \(max(1, seconds / 60))m"
            }
            return "Rate limited, retry later"
        case .networkError:
            return "No connection"
        case .decodingError:
            return "Failed to parse response"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add GitHubWidget/Services/GitHubError.swift
git commit -m "feat: add GitHubError enum"
```

---

## Task 4: KeychainHelper

**Files:**
- Create: `GitHubWidgetTests/KeychainHelperTests.swift`
- Create: `GitHubWidget/Utilities/KeychainHelper.swift`

- [ ] **Step 1: Write failing tests**

Create `GitHubWidgetTests/KeychainHelperTests.swift`:

```swift
import XCTest
@testable import GitHubWidget

final class KeychainHelperTests: XCTestCase {
    private let testKey = "test_keychain_key_\(UUID().uuidString)"

    override func tearDown() {
        super.tearDown()
        KeychainHelper.delete(key: testKey)
    }

    func test_saveAndLoad_roundtrips() {
        KeychainHelper.save(key: testKey, value: "secret-token")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "secret-token")
    }

    func test_load_returnsNilForMissingKey() {
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }

    func test_save_overwritesExistingValue() {
        KeychainHelper.save(key: testKey, value: "old-value")
        KeychainHelper.save(key: testKey, value: "new-value")
        XCTAssertEqual(KeychainHelper.load(key: testKey), "new-value")
    }

    func test_delete_removesValue() {
        KeychainHelper.save(key: testKey, value: "to-delete")
        KeychainHelper.delete(key: testKey)
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/KeychainHelperTests 2>&1 | tail -10
```

Expected: compile error — `KeychainHelper` not defined.

- [ ] **Step 3: Implement KeychainHelper**

Create `GitHubWidget/Utilities/KeychainHelper.swift`:

```swift
import Security
import Foundation

enum KeychainHelper {
    static func save(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/KeychainHelperTests 2>&1 | tail -10
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Utilities/KeychainHelper.swift GitHubWidgetTests/KeychainHelperTests.swift
git commit -m "feat: add KeychainHelper for PAT storage"
```

---

## Task 5: GitHubService

**Files:**
- Create: `GitHubWidgetTests/GitHubServiceTests.swift`
- Create: `GitHubWidget/Services/GitHubService.swift`

- [ ] **Step 1: Write failing tests**

Create `GitHubWidgetTests/GitHubServiceTests.swift`:

```swift
import XCTest
@testable import GitHubWidget

final class GitHubServiceTests: XCTestCase {

    // MARK: - Successful fetch

    func test_fetchPRs_parsesSearchResponse() async throws {
        let json = searchResponseJSON(items: [pullRequestJSON(id: 1)])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        let result = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")

        XCTAssertEqual(result.reviewRequested.count, 1)
        XCTAssertEqual(result.reviewRequested[0].id, 1)
    }

    func test_fetchPRs_deduplicatesSamePRacrossQueries() async throws {
        let json = searchResponseJSON(items: [pullRequestJSON(id: 99)])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        let result = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")

        XCTAssertEqual(result.allPRs.count, 1)
    }

    // MARK: - Error mapping

    func test_fetchPRs_throws_unauthorized_on401() async {
        let session = MockURLSession(responseData: Data(), statusCode: 401)
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "bad", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    func test_fetchPRs_throws_rateLimited_on429() async {
        let session = MockURLSession(responseData: Data(), statusCode: 429, retryAfter: "120")
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .rateLimited(retryAfter: 120))
        }
    }

    func test_fetchPRs_throws_decodingError_onBadJSON() async {
        let session = MockURLSession(responseData: Data("not json".utf8), statusCode: 200)
        let service = GitHubService(session: session)

        do {
            _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "")
            XCTFail("Expected throw")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .decodingError)
        }
    }

    // MARK: - Org filter

    func test_fetchPRs_appendsOrgFilterToQuery() async throws {
        let json = searchResponseJSON(items: [])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "myorg")

        let urls = session.capturedRequests.map { $0.url?.absoluteString ?? "" }
        XCTAssert(urls.allSatisfy { $0.contains("org%3Amyorg") || $0.contains("org:myorg") })
    }

    func test_fetchPRs_appendsRepoFilterToQuery() async throws {
        let json = searchResponseJSON(items: [])
        let session = MockURLSession(responseData: json, statusCode: 200)
        let service = GitHubService(session: session)

        _ = try await service.fetchPRs(token: "tok", username: "me", orgFilter: "myorg/myrepo")

        let urls = session.capturedRequests.map { $0.url?.absoluteString ?? "" }
        XCTAssert(urls.allSatisfy { $0.contains("repo%3Amyorg") || $0.contains("repo:myorg") })
    }
}

// MARK: - Helpers

private func searchResponseJSON(items: [String]) -> Data {
    let itemsJSON = items.joined(separator: ",")
    return """
    {"total_count": \(items.count), "incomplete_results": false, "items": [\(itemsJSON)]}
    """.data(using: .utf8)!
}

private func pullRequestJSON(id: Int) -> String {
    """
    {
        "id": \(id),
        "number": \(id),
        "title": "PR \(id)",
        "html_url": "https://github.com/org/repo/pull/\(id)",
        "repository_url": "https://api.github.com/repos/org/repo",
        "draft": false,
        "labels": [],
        "user": { "login": "alice", "avatar_url": "https://example.com/avatar.png" }
    }
    """
}

// MARK: - MockURLSession

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    private let responseData: Data
    private let statusCode: Int
    private let retryAfter: String?
    private(set) var capturedRequests: [URLRequest] = []

    init(responseData: Data, statusCode: Int, retryAfter: String? = nil) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.retryAfter = retryAfter
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        capturedRequests.append(request)
        var headers: [String: String] = [:]
        if let ra = retryAfter { headers["Retry-After"] = ra }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (responseData, response)
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/GitHubServiceTests 2>&1 | tail -10
```

Expected: compile error — `GitHubService` and `URLSessionProtocol` not defined.

- [ ] **Step 3: Implement GitHubService**

Create `GitHubWidget/Services/GitHubService.swift`:

```swift
import Foundation

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

protocol GitHubServiceProtocol: Sendable {
    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult
}

actor GitHubService: GitHubServiceProtocol {
    static let shared = GitHubService()

    private let session: URLSessionProtocol

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult {
        async let reviewRequested = search(
            query: buildQuery("is:pr review-requested:@me state:open", orgFilter: orgFilter),
            token: token
        )
        async let changesRequested = search(
            query: buildQuery("is:pr author:@me review:changes_requested state:open", orgFilter: orgFilter),
            token: token
        )
        async let assigned = search(
            query: buildQuery("is:pr assignee:@me state:open", orgFilter: orgFilter),
            token: token
        )
        async let readyToMerge = search(
            query: buildQuery("is:pr author:@me review:approved state:open", orgFilter: orgFilter),
            token: token
        )

        let (rr, cr, a, rtm) = try await (reviewRequested, changesRequested, assigned, readyToMerge)
        return PRFetchResult(reviewRequested: rr, changesRequested: cr, assigned: a, readyToMerge: rtm)
    }

    private func buildQuery(_ base: String, orgFilter: String) -> String {
        guard !orgFilter.isEmpty else { return base }
        if orgFilter.contains("/") {
            return "\(base) repo:\(orgFilter)"
        } else {
            return "\(base) org:\(orgFilter)"
        }
    }

    private func search(query: String, token: String) async throws -> [PullRequest] {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "50")
        ]
        guard let url = components.url else { throw GitHubError.networkError }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GitHubError.networkError
        }

        guard let http = response as? HTTPURLResponse else { throw GitHubError.networkError }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(GitHubSearchResponse.self, from: data).items
            } catch {
                throw GitHubError.decodingError
            }
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw GitHubError.rateLimited(retryAfter: retryAfter)
        default:
            throw GitHubError.networkError
        }
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/GitHubServiceTests 2>&1 | tail -10
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Services/GitHubService.swift GitHubWidgetTests/GitHubServiceTests.swift
git commit -m "feat: add GitHubService with async/await GitHub REST API queries"
```

---

## Task 6: PRStore

**Files:**
- Create: `GitHubWidgetTests/PRStoreTests.swift`
- Create: `GitHubWidget/Store/PRStore.swift`

- [ ] **Step 1: Write failing tests**

Create `GitHubWidgetTests/PRStoreTests.swift`:

```swift
import XCTest
@testable import GitHubWidget

@MainActor
final class PRStoreTests: XCTestCase {

    func test_refresh_setsNotConfiguredError_whenNoPAT() async {
        let store = PRStore(service: MockGitHubService())
        KeychainHelper.delete(key: "github_pat")

        await store.refresh()

        XCTAssertEqual(store.error, .notConfigured)
        XCTAssertTrue(store.waitingOnMe.isEmpty)
    }

    func test_refresh_populatesCategories_onSuccess() async {
        let waiting = PullRequest.fixture(id: 1)
        let ready = PullRequest.fixture(id: 2)
        let inProg = PullRequest.fixture(id: 3)
        let mockResult = PRFetchResult(
            reviewRequested: [waiting],
            changesRequested: [],
            assigned: [inProg],
            readyToMerge: [ready]
        )
        let service = MockGitHubService(result: mockResult)
        let store = PRStore(service: service)
        KeychainHelper.save(key: "github_pat", value: "test-token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()

        XCTAssertNil(store.error)
        XCTAssertEqual(store.waitingOnMe.count, 1)
        XCTAssertEqual(store.readyToMerge.count, 1)
        XCTAssertEqual(store.inProgress.count, 1)
        XCTAssertNotNil(store.lastUpdated)
    }

    func test_refresh_setsError_onServiceThrow() async {
        let service = MockGitHubService(error: .unauthorized)
        let store = PRStore(service: service)
        KeychainHelper.save(key: "github_pat", value: "bad-token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()

        XCTAssertEqual(store.error, .unauthorized)
    }

    func test_totalCount_sumsCategoryLengths() async {
        let mockResult = PRFetchResult(
            reviewRequested: [.fixture(id: 1), .fixture(id: 2)],
            changesRequested: [],
            assigned: [.fixture(id: 3)],
            readyToMerge: []
        )
        let store = PRStore(service: MockGitHubService(result: mockResult))
        KeychainHelper.save(key: "github_pat", value: "token")
        defer { KeychainHelper.delete(key: "github_pat") }

        await store.refresh()

        XCTAssertEqual(store.totalCount, 3)
    }
}

// MARK: - MockGitHubService

final class MockGitHubService: GitHubServiceProtocol, @unchecked Sendable {
    private let result: PRFetchResult?
    private let error: GitHubError?

    init(
        result: PRFetchResult = PRFetchResult(reviewRequested: [], changesRequested: [], assigned: [], readyToMerge: []),
        error: GitHubError? = nil
    ) {
        self.result = result
        self.error = error
    }

    func fetchPRs(token: String, username: String, orgFilter: String) async throws -> PRFetchResult {
        if let error { throw error }
        return result!
    }
}
```

- [ ] **Step 2: Run tests — expect failure**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/PRStoreTests 2>&1 | tail -10
```

Expected: compile error — `PRStore` not defined.

- [ ] **Step 3: Implement PRStore**

Create `GitHubWidget/Store/PRStore.swift`:

```swift
import Foundation
import Combine

@MainActor
final class PRStore: ObservableObject {
    @Published var waitingOnMe: [PullRequest] = []
    @Published var readyToMerge: [PullRequest] = []
    @Published var inProgress: [PullRequest] = []
    @Published var isLoading = false
    @Published var error: GitHubError?
    @Published var lastUpdated: Date?

    @Published private(set) var totalCount: Int = 0

    private var previousPRs: [PullRequest] = []
    private let service: any GitHubServiceProtocol

    init(service: any GitHubServiceProtocol = GitHubService.shared) {
        self.service = service
    }

    func refresh() async {
        guard let token = KeychainHelper.load(key: "github_pat"), !token.isEmpty else {
            error = .notConfigured
            return
        }
        let username = UserDefaults.standard.string(forKey: "github_username") ?? ""
        let orgFilter = UserDefaults.standard.string(forKey: "github_org_filter") ?? ""

        isLoading = true
        error = nil

        do {
            let result = try await service.fetchPRs(token: token, username: username, orgFilter: orgFilter)
            diffAndEmitEvents(old: previousPRs, new: result.allPRs)
            previousPRs = result.allPRs

            waitingOnMe = result.waitingOnMe
            readyToMerge = result.readyToMergeDeduped
            inProgress = result.inProgress
            totalCount = waitingOnMe.count + readyToMerge.count + inProgress.count
            lastUpdated = Date()
        } catch let e as GitHubError {
            error = e
        } catch {
            self.error = .networkError
        }

        isLoading = false
    }

    private func diffAndEmitEvents(old: [PullRequest], new: [PullRequest]) {
        // Stub: future UserNotifications emitted here for newly added PRs
        _ = Set(new.map(\.id)).subtracting(Set(old.map(\.id)))
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' -only-testing:GitHubWidgetTests/PRStoreTests 2>&1 | tail -10
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add GitHubWidget/Store/PRStore.swift GitHubWidgetTests/PRStoreTests.swift
git commit -m "feat: add PRStore with categorization and refresh logic"
```

---

## Task 7: SettingsView

**Files:**
- Create: `GitHubWidget/Views/SettingsView.swift`

- [ ] **Step 1: Implement SettingsView**

Create `GitHubWidget/Views/SettingsView.swift`:

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var username = ""
    @State private var orgFilter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Personal Access Token")
                    .font(.subheadline)
                SecureField("ghp_...", text: $token)
                    .textFieldStyle(.roundedBorder)
                Text("Required scopes: repo, read:user")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("GitHub Username")
                    .font(.subheadline)
                TextField("yourhandle", text: $username)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Org / Repo Filter (optional)")
                    .font(.subheadline)
                TextField("myorg  or  myorg/myrepo", text: $orgFilter)
                    .textFieldStyle(.roundedBorder)
                Text("Leave blank to show all your PRs")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear(perform: load)
    }

    private func load() {
        token = KeychainHelper.load(key: "github_pat") ?? ""
        username = UserDefaults.standard.string(forKey: "github_username") ?? ""
        orgFilter = UserDefaults.standard.string(forKey: "github_org_filter") ?? ""
    }

    private func save() {
        KeychainHelper.save(key: "github_pat", value: token)
        UserDefaults.standard.set(username, forKey: "github_username")
        UserDefaults.standard.set(orgFilter, forKey: "github_org_filter")
        dismiss()
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

```bash
xcodebuild build -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 3: Commit**

```bash
git add GitHubWidget/Views/SettingsView.swift
git commit -m "feat: add SettingsView for PAT and username configuration"
```

---

## Task 8: PRRowView

**Files:**
- Create: `GitHubWidget/Views/PRRowView.swift`

- [ ] **Step 1: Implement PRRowView**

Create `GitHubWidget/Views/PRRowView.swift`:

```swift
import SwiftUI
import AppKit

struct PRRowView: View {
    let pr: PullRequest

    var body: some View {
        Button(action: openPR) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.repoName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(pr.title)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 4)
                Text("@\(pr.user.login)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.htmlUrl, forType: .string)
            }
        }
    }

    private func openPR() {
        guard let url = URL(string: pr.htmlUrl) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add GitHubWidget/Views/PRRowView.swift
git commit -m "feat: add PRRowView with click-to-open and copy URL context menu"
```

---

## Task 9: PopoverView

**Files:**
- Create: `GitHubWidget/Views/PopoverView.swift`

- [ ] **Step 1: Implement PopoverView**

Create `GitHubWidget/Views/PopoverView.swift`:

```swift
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: PRStore
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 340)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private var headerView: some View {
        HStack {
            Text("GitHub PRs")
                .font(.headline)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading)
            Button { showSettings = true } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var contentView: some View {
        if let error = store.error {
            errorView(error)
        } else if store.waitingOnMe.isEmpty && store.readyToMerge.isEmpty && store.inProgress.isEmpty && !store.isLoading {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !store.waitingOnMe.isEmpty {
                        SectionHeaderView(emoji: "👀", title: "WAITING ON ME", count: store.waitingOnMe.count)
                        ForEach(store.waitingOnMe) { pr in
                            PRRowView(pr: pr)
                            Divider().padding(.leading, 12)
                        }
                    }
                    if !store.readyToMerge.isEmpty {
                        SectionHeaderView(emoji: "✅", title: "READY TO MERGE", count: store.readyToMerge.count)
                        ForEach(store.readyToMerge) { pr in
                            PRRowView(pr: pr)
                            Divider().padding(.leading, 12)
                        }
                    }
                    if !store.inProgress.isEmpty {
                        SectionHeaderView(emoji: "🔄", title: "IN PROGRESS", count: store.inProgress.count)
                        ForEach(store.inProgress) { pr in
                            PRRowView(pr: pr)
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private var footerView: some View {
        HStack(spacing: 6) {
            if store.isLoading {
                ProgressView().scaleEffect(0.6)
                Text("Refreshing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let date = store.lastUpdated {
                Text("Updated \(date, formatter: relativeFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func errorView(_ error: GitHubError) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.title2)
            Text(error.userMessage)
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        Text("No open PRs")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }
}

struct SectionHeaderView: View {
    let emoji: String
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text("\(emoji) \(title) (\(count))")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.separatorColor).opacity(0.1))
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild build -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add GitHubWidget/Views/PopoverView.swift
git commit -m "feat: add PopoverView with sections, error state, and empty state"
```

---

## Task 10: AppDelegate + App Entry Point

**Files:**
- Create: `GitHubWidget/App/AppDelegate.swift`
- Create: `GitHubWidget/App/GitHubWidgetApp.swift`

- [ ] **Step 1: Implement AppDelegate**

Create `GitHubWidget/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let store = PRStore()
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupBadgeObserver()
        startTimer()
        Task { await store.refresh() }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: "GitHub PRs")
        button.imagePosition = .imageLeft
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 440)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))
    }

    private func setupBadgeObserver() {
        store.$totalCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.updateBadge(count: count) }
            .store(in: &cancellables)
    }

    private func startTimer() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { await self?.store.refresh() }
        }
    }

    private func updateBadge(count: Int) {
        statusItem.button?.title = count > 0 ? " \(count)" : ""
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
```

- [ ] **Step 2: Implement App entry point**

Create `GitHubWidget/App/GitHubWidgetApp.swift`:

```swift
import SwiftUI

@main
struct GitHubWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene keeps app alive with no windows; LSUIElement hides dock icon
        Settings { EmptyView() }
    }
}
```

- [ ] **Step 3: Build the full app**

```bash
xcodebuild build -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' 2>&1 | grep -E '(error:|BUILD)'
```

Expected: `BUILD SUCCEEDED` with no errors.

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -scheme GitHubWidget -destination 'platform=macOS,arch=arm64' 2>&1 | tail -15
```

Expected: `TEST SUCCEEDED`, all tests passing.

- [ ] **Step 5: Manual smoke test**

Open the app in Xcode, run it, and verify:
- No dock icon appears
- Status bar shows the pull icon
- Click opens popover with "Add token in Settings" error (no PAT configured yet)
- Click gear → Settings sheet appears
- Enter a real PAT + username, click Save
- Click refresh → PRs load and appear in correct sections
- Badge count updates in status bar
- Click a PR → opens in browser
- Right-click a PR → "Copy URL" works

- [ ] **Step 6: Commit**

```bash
git add GitHubWidget/App/AppDelegate.swift GitHubWidget/App/GitHubWidgetApp.swift
git commit -m "feat: wire AppDelegate with NSStatusItem, popover, badge, and 5-min timer"
```

---

## Task 11: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

Create `README.md`:

```markdown
# GitHub PR Widget

macOS menubar app showing GitHub pull requests that need your attention.

## What it shows

- **👀 Waiting on me** — review requested on your PRs, or you requested changes and are waiting for re-review
- **✅ Ready to merge** — your PRs that have been approved
- **🔄 In progress** — PRs assigned to you

Badge count on the menubar icon shows the total number of PRs across all categories. Refreshes every 5 minutes. Click any PR to open it in your browser.

## Prerequisites

- macOS 13+
- Xcode 15+
- [Homebrew](https://brew.sh) (for xcodegen)

## Build & Run

```bash
brew install xcodegen
xcodegen generate
open GitHubWidget.xcodeproj
```

Press **⌘R** in Xcode to run.

## Configuration

1. **Generate a GitHub Personal Access Token**
   - Go to [github.com/settings/tokens](https://github.com/settings/tokens) → **Generate new token (classic)**
   - Required scopes: `repo`, `read:user`
   - Copy the generated token (starts with `ghp_`)

2. **Configure the app**
   - Click the menubar icon
   - Click the ⚙ gear icon
   - Paste your token in the **Personal Access Token** field
   - Enter your **GitHub username**
   - Optionally filter to a specific org (`myorg`) or repo (`myorg/myrepo`)
   - Click **Save**

The token is stored securely in your macOS Keychain.

## Future

- macOS notifications for new review requests and PR status changes
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with setup and PAT instructions"
```

---

## Manual Testing Checklist

After all tasks complete, verify:

- [ ] No dock icon when app runs
- [ ] Menubar icon visible with SF Symbol
- [ ] Badge count shows total PRs, hidden when 0
- [ ] Popover opens/closes on click
- [ ] "Add token in Settings" shown when no PAT configured
- [ ] Settings sheet saves PAT to Keychain (verify with Keychain Access.app)
- [ ] Settings sheet saves username + org filter to UserDefaults
- [ ] PRs appear in correct sections after configuring PAT
- [ ] Click PR row opens correct GitHub URL in browser
- [ ] Right-click → Copy URL puts URL on clipboard
- [ ] Manual refresh (↻) button works
- [ ] 5-minute auto-refresh fires (verify by waiting or temporarily setting timer to 10s)
- [ ] "Invalid token" error shown for bad PAT
- [ ] "No connection" shown when offline
