import Foundation

/// Short term is the sectioned view; long term is a single flat list.
enum Horizon: String, Codable, CaseIterable, Identifiable {
    case shortTerm
    case longTerm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortTerm: return "Short Term"
        case .longTerm:  return "Long Term"
        }
    }
}

/// The sections of the short-term view, in display order.
enum Bucket: String, Codable, CaseIterable, Identifiable {
    case readings
    case assignments
    case emails
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .readings:    return "Readings"
        case .assignments: return "Assignments"
        case .emails:      return "Emails"
        case .other:       return "Other"
        }
    }

    /// Menu wording for the ⌘-number shortcut that jumps to this section.
    var singular: String {
        switch self {
        case .readings:    return "Reading"
        case .assignments: return "Assignment"
        case .emails:      return "Email"
        case .other:       return "Other Task"
        }
    }

    /// Placeholder for that section's own add field.
    var prompt: String {
        switch self {
        case .readings:    return "Add a reading…"
        case .assignments: return "Add an assignment…"
        case .emails:      return "Add an email…"
        case .other:       return "Add anything else…"
        }
    }
}

/// A single task.
struct Todo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    /// Which section a short-term task sits in. Long-term tasks are shown as
    /// one flat list, so this is carried but never read for them.
    var bucket: Bucket
    var horizon: Horizon
    var isDone: Bool
    var isStarred: Bool
    var createdAt: Date

    init(title: String, bucket: Bucket, horizon: Horizon = .shortTerm) {
        self.id = UUID()
        self.title = title
        self.bucket = bucket
        self.horizon = horizon
        self.isDone = false
        self.isStarred = false
        self.createdAt = Date()
    }

    /// Decoded by hand so task files written by earlier versions — which had no
    /// bucket, star, or horizon — still load instead of throwing the whole list
    /// away. Anything saved before horizons existed counts as short term.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        bucket = try c.decodeIfPresent(Bucket.self, forKey: .bucket) ?? .assignments
        horizon = try c.decodeIfPresent(Horizon.self, forKey: .horizon) ?? .shortTerm
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Which tasks the window is currently showing.
enum Filter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case starred = "Starred"
    case done = "Done"

    var id: String { rawValue }

    func matches(_ todo: Todo) -> Bool {
        switch self {
        case .all:     return true
        case .active:  return !todo.isDone
        case .starred: return todo.isStarred
        case .done:    return todo.isDone
        }
    }
}
