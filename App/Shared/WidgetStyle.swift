// Shared widget style enum, compiled into both the app and the widget extension.
import Foundation

/// The visual style a user can pick for any home-screen BitChord widget.
enum WidgetStyle: String, CaseIterable, Codable, Sendable {
    /// Full-bleed album art with the blurred foot — the original BitChord look.
    case artwork
    /// Heavy-blurred artwork fills the background; the cover floats in a rounded square.
    case glass
    /// Solid dark card with the cover in a compact leading square and clean white text.
    case minimal
}
