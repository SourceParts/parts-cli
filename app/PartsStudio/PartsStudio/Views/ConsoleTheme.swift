import SwiftUI

/// Shared console color theme for FELConsoleView and DevConsoleView.
/// Colors are persisted via @AppStorage using simple string names.
enum ConsoleColorName: String, CaseIterable {
    case green = "green"
    case amber = "amber"
    case white = "white"
    case cyan = "cyan"
    case blue = "blue"

    var color: Color {
        switch self {
        case .green: return .green
        case .amber: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case .white: return .white
        case .cyan: return .cyan
        case .blue: return Color(red: 0.4, green: 0.6, blue: 1.0)
        }
    }

    /// Swatch color shown in the picker (slightly brighter for visibility).
    var swatchColor: Color { color }
}

enum ConsoleBackgroundName: String, CaseIterable {
    case black = "black"
    case darkBlue = "darkBlue"
    case darkGreen = "darkGreen"

    var color: Color {
        switch self {
        case .black: return .black
        case .darkBlue: return Color(red: 0.0, green: 0.05, blue: 0.15)
        case .darkGreen: return Color(red: 0.0, green: 0.08, blue: 0.04)
        }
    }
}

/// Resolves a stored color name string to a SwiftUI Color.
enum ConsoleTheme {
    static func textColor(from name: String) -> Color {
        (ConsoleColorName(rawValue: name) ?? .green).color
    }

    static func backgroundColor(from name: String) -> Color {
        (ConsoleBackgroundName(rawValue: name) ?? .black).color
    }
}

/// A small row of colored circles for picking the console text color.
struct ConsoleColorPicker: View {
    @Binding var selectedName: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ConsoleColorName.allCases, id: \.rawValue) { scheme in
                Circle()
                    .fill(scheme.swatchColor)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(selectedName == scheme.rawValue ? 0.8 : 0), lineWidth: 1.5)
                    )
                    .onTapGesture {
                        selectedName = scheme.rawValue
                    }
                    .help(scheme.rawValue.capitalized)
            }
        }
    }
}
