import WidgetKit

/// One drawing of the widget: the last snapshot the app wrote, with its cover baked.
struct NowPlayingEntry: TimelineEntry {
    var date: Date
    /// Nil when nothing has played yet.
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
}

/// Reads what the app published to the App Group (MediaWidgetSnapshot.load).
///
/// The widget never asks the player: it is on screen while the app isn't running, and the snapshot
/// is what the app last said. The app reloads the timelines whenever what a widget shows changes
/// (track, play/pause, like, shuffle), so a single entry that never expires is enough.
struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: .now, snapshot: WidgetFace.previewSnapshot, art: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        // Show the preview track in the gallery, or when App Group is unavailable (eSign sideload
        // strips the entitlement) so the widget renders a styled preview instead of grey blank.
        if context.isPreview || NowPlayingSnapshot.load() == nil {
            completion(placeholder(in: context))
            return
        }
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        // If App Group is unavailable, always show preview so it renders something.
        let entry = NowPlayingSnapshot.load() != nil ? current() : placeholder(in: context)
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func current() -> NowPlayingEntry {
        let snapshot = NowPlayingSnapshot.load()
        return NowPlayingEntry(date: .now, snapshot: snapshot, art: WidgetArt.load(for: snapshot))
    }
}
