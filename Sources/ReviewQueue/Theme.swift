import ReviewQueueCore
import SwiftUI

extension Reason.Tone {
    var color: Color {
        switch self {
        case .request: return .blue
        case .commits: return .purple
        case .reply: return .teal
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
}

extension CIStatus.Summary {
    var color: Color {
        switch self {
        case .passed: return .green
        case .failed: return .red
        case .running: return .orange
        case .none: return .secondary.opacity(0.4)
        }
    }

    var help: String {
        switch self {
        case .passed: return "Checks passed"
        case .failed: return "Checks failed"
        case .running: return "Checks running"
        case .none: return "No checks"
        }
    }
}

let rowDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM · HH:mm"
    return f
}()
