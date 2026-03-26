import Foundation

enum ProcessStatus: Equatable {
    case stopped, running, crashed, crashLooping
}

enum SidebarItem: Identifiable, Equatable {
    case profile(Profile, ProcessStatus)
    case terminal(UUID)

    var id: String {
        switch self {
        case .profile(let p, _): return "profile-\(p.id)"
        case .terminal(let id): return "terminal-\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .profile(let p, _): return p.name
        case .terminal(let id): return "Shell \(id.uuidString.prefix(4))"
        }
    }
}
