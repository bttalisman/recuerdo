import SwiftUI

/// Enhances visual contrast between list sections and background in dark mode.
struct DarkModeContrastModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .scrollContentBackground(.hidden)
                .background(Color.black)
        } else {
            content
        }
    }
}

/// Adds a subtle warm gradient to list row backgrounds.
struct SubtleSectionGlow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.listRowBackground(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.185, green: 0.13, blue: 0.10),
                       Color(red: 0.085, green: 0.085, blue: 0.085)]

                    : [Color(red: 1.0, green: 0.995, blue: 0.985),
                       Color(red: 1.0, green: 0.96, blue: 0.90)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

extension View {
    func enhancedDarkContrast() -> some View {
        modifier(DarkModeContrastModifier())
    }

    func subtleSectionGlow() -> some View {
        modifier(SubtleSectionGlow())
    }
}
