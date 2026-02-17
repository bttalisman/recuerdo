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

extension View {
    func enhancedDarkContrast() -> some View {
        modifier(DarkModeContrastModifier())
    }
}
