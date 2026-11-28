// Widget bundle: home-screen (small, medium-wide, medium-pill, large) + lock-screen (circular, rectangular).
import SwiftUI
import WidgetKit

@main
struct BitChordWidgetBundle: WidgetBundle {
    var body: some Widget {
        // --- Home screen (all support style customisation) ---
        NowPlayingSquareWidget()
        NowPlayingWideWidget()
        NowPlayingPillWidget()
        NowPlayingLargeWidget()
        // --- Lock Screen ---
        NowPlayingLockCircularWidget()
        NowPlayingLockRectangularWidget()
    }
}

// MARK: - Home Screen Widgets

/// "Now playing 2×2" – small, style-customisable.
struct NowPlayingSquareWidget: Widget {
    static let kind = "com.music.bitchord.widget.square"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetStyleIntent.self, provider: NowPlayingIntentProvider()) { entry in
            CompactWidgetView(snapshot: entry.snapshot, art: entry.art, style: entry.style)
        }
        .configurationDisplayName(SharedStrings.widgetSquareLabel)
        .description(SharedStrings.widgetSquareDescription)
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

/// "Now playing 4×2" – medium wide, style-customisable.
struct NowPlayingWideWidget: Widget {
    static let kind = "com.music.bitchord.widget.wide"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetStyleIntent.self, provider: NowPlayingIntentProvider()) { entry in
            WideWidgetView(snapshot: entry.snapshot, art: entry.art, style: entry.style)
        }
        .configurationDisplayName(SharedStrings.widgetWideLabel)
        .description(SharedStrings.widgetWideDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// "Now playing 4×1" – medium pill, style-customisable.
struct NowPlayingPillWidget: Widget {
    static let kind = "com.music.bitchord.widget.pill"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetStyleIntent.self, provider: NowPlayingIntentProvider()) { entry in
            PillWidgetView(snapshot: entry.snapshot, art: entry.art, style: entry.style)
        }
        .configurationDisplayName(SharedStrings.widgetPillLabel)
        .description(SharedStrings.widgetPillDescription)
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

/// "Now playing 4×4" – large, style-customisable, NEW.
struct NowPlayingLargeWidget: Widget {
    static let kind = "com.music.bitchord.widget.large"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: WidgetStyleIntent.self, provider: NowPlayingIntentProvider()) { entry in
            LargeWidgetView(snapshot: entry.snapshot, art: entry.art, style: entry.style)
        }
        .configurationDisplayName(SharedStrings.widgetLargeLabel)
        .description(SharedStrings.widgetLargeDescription)
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen Widgets

/// Lock Screen circular – album art with play/pause tap, NEW.
struct NowPlayingLockCircularWidget: Widget {
    static let kind = "com.music.bitchord.widget.lock.circular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            LockCircularWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetLockCircularLabel)
        .description(SharedStrings.widgetLockCircularDescription)
        .supportedFamilies([.accessoryCircular])
    }
}

/// Lock Screen rectangular – track + controls bar, NEW.
struct NowPlayingLockRectangularWidget: Widget {
    static let kind = "com.music.bitchord.widget.lock.rectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: NowPlayingProvider()) { entry in
            LockRectangularWidgetView(snapshot: entry.snapshot, art: entry.art)
        }
        .configurationDisplayName(SharedStrings.widgetLockRectangularLabel)
        .description(SharedStrings.widgetLockRectangularDescription)
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Intent Provider

/// Timeline provider wired to WidgetStyleIntent so AppIntentConfiguration can resolve the style.
struct NowPlayingIntentProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetStyleIntent
    typealias Entry  = NowPlayingIntentEntry

    func placeholder(in context: Context) -> NowPlayingIntentEntry {
        NowPlayingIntentEntry(snapshot: WidgetFace.previewSnapshot, art: nil, style: .artwork)
    }

    func snapshot(for configuration: WidgetStyleIntent, in context: Context) async -> NowPlayingIntentEntry {
        // Always show preview when in gallery (context.isPreview) or when App Group
        // is unavailable (sideloaded without entitlement — eSign strips App Groups).
        // This shows a styled preview instead of a grey blank widget.
        let snapshot = context.isPreview ? WidgetFace.previewSnapshot : (NowPlayingSnapshot.load() ?? WidgetFace.previewSnapshot)
        let art      = WidgetArt.load(for: NowPlayingSnapshot.load())
        return NowPlayingIntentEntry(snapshot: snapshot, art: art, style: configuration.resolvedStyle)
    }

    func timeline(for configuration: WidgetStyleIntent, in context: Context) async -> Timeline<NowPlayingIntentEntry> {
        // If App Group data is available use it; otherwise show the preview snapshot
        // so the widget always renders something instead of a grey blank box.
        let liveSnapshot = NowPlayingSnapshot.load()
        let snapshot = liveSnapshot ?? WidgetFace.previewSnapshot
        let art      = WidgetArt.load(for: liveSnapshot)
        let entry    = NowPlayingIntentEntry(snapshot: snapshot, art: art, style: configuration.resolvedStyle)
        return Timeline(entries: [entry], policy: .never)
    }
}

/// Timeline entry that carries both the now-playing data and the chosen style.
struct NowPlayingIntentEntry: TimelineEntry {
    var date: Date = .now
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
    var style: WidgetStyle
}
