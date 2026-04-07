import Foundation

/// User access level for Parts Studio features.
enum UserRole: String, Codable, CaseIterable {
    case viewer     = "viewer"      // Read-only: view datasheets, device info
    case operator_  = "operator"    // Can boot devices, read memory
    case engineer   = "engineer"    // Full FEL access, write memory, peripherals
    case admin      = "admin"       // Everything + user management

    var displayName: String {
        switch self {
        case .viewer: return "Viewer"
        case .operator_: return "Operator"
        case .engineer: return "Engineer"
        case .admin: return "Admin"
        }
    }

    /// Whether this role can see raw FEL internals (thunk, swap buffers, addresses).
    var canSeeInternals: Bool {
        self == .engineer || self == .admin
    }

    /// Whether this role can write memory or execute code.
    var canWrite: Bool {
        self == .engineer || self == .admin
    }

    /// Whether this role can boot devices.
    var canBoot: Bool {
        self != .viewer
    }

    /// Whether this role can read memory.
    var canRead: Bool {
        self != .viewer
    }

    /// Whether this role can control peripherals (GPIO, SPI, UART).
    var canControlPeripherals: Bool {
        self == .engineer || self == .admin
    }

    /// Whether FEL mode is shown as "Recovery Mode" (user-friendly) or "FEL Mode" (technical).
    var felModeLabel: String {
        canSeeInternals ? "FEL Mode" : "Recovery Mode"
    }
}

/// Manages the current user role. Persisted via @AppStorage in AppState.
class UserSession: ObservableObject {
    @Published var role: UserRole

    init(role: UserRole = .admin) {
        self.role = role
    }
}
