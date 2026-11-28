// AppIntent and configuration types for customizable home-screen widget styles.
// WidgetStyle enum lives in App/Shared/WidgetStyle.swift (compiled into both targets).
import AppIntents
import WidgetKit

// MARK: - AppEntity (required by AppIntentConfiguration)

/// An AppEntity wrapper so `WidgetStyle` can be used as an `AppIntentConfiguration` parameter.
struct WidgetStyleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Widget Style")
    }

    static var defaultQuery = WidgetStyleQuery()

    var id: String
    var style: WidgetStyle

    var displayRepresentation: DisplayRepresentation {
        switch style {
        case .artwork: return DisplayRepresentation(title: "Artwork", subtitle: "Full-bleed album art")
        case .glass:   return DisplayRepresentation(title: "Glass",   subtitle: "Blurred artwork background")
        case .minimal: return DisplayRepresentation(title: "Minimal", subtitle: "Dark card with cover thumbnail")
        }
    }

    init(_ style: WidgetStyle) {
        self.id    = style.rawValue
        self.style = style
    }
}

struct WidgetStyleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetStyleEntity] {
        WidgetStyle.allCases
            .filter { identifiers.contains($0.rawValue) }
            .map { WidgetStyleEntity($0) }
    }

    func suggestedEntities() async throws -> [WidgetStyleEntity] {
        WidgetStyle.allCases.map { WidgetStyleEntity($0) }
    }
}

// MARK: - AppIntent

/// The configurable intent stored with every home-screen BitChord widget.
struct WidgetStyleIntent: WidgetConfigurationIntent {
    static var title:       LocalizedStringResource = "Style"
    static var description: IntentDescription       = IntentDescription("Choose the visual style of the widget.")

    @Parameter(title: "Style")
    var style: WidgetStyleEntity?

    /// Resolved style with a safe fallback.
    var resolvedStyle: WidgetStyle { style?.style ?? .artwork }
}
