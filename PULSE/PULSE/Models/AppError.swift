import Foundation

enum AppError: Error, LocalizedError {
    case healthKitUnavailable
    case healthKitAuthorizationDenied
    case healthKitQueryFailed(String)
    case apiFailure(String)
    case jsonParseFailed(String)
    case storeLoadFailed(String)
    case storeSaveFailed(String)
    case configMissing(String)
    case agentMaxIterationsReached

    var errorDescription: String? {
        switch self {
        case .healthKitUnavailable:
            return "Health data is not available on this device."
        case .healthKitAuthorizationDenied:
            return "Health access was denied. Enable it in Settings > Health > Data Access."
        case .healthKitQueryFailed(let detail):
            return "Could not read health data: \(detail)"
        case .apiFailure(let detail):
            return "Could not reach the coaching service. \(detail)"
        case .jsonParseFailed(let detail):
            return "Response parsing failed: \(detail)"
        case .storeLoadFailed(let detail):
            return "Could not load stored data: \(detail)"
        case .storeSaveFailed(let detail):
            return "Could not save data: \(detail)"
        case .configMissing(let key):
            return "Missing configuration key: \(key). Check Config.plist."
        case .agentMaxIterationsReached:
            return "The AI took too many steps to answer this. Try asking a more specific question."
        }
    }

    /// User-visible message suitable for displaying in an alert.
    var userMessage: String {
        errorDescription ?? "An unexpected error occurred."
    }
}
