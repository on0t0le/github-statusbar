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
