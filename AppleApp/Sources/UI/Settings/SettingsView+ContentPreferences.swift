// Content preferences settings section for controlling Home feed shelves and media appearance.
import SwiftUI
import BitChordShared
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension SettingsView {
    func buildContentPreferencesRows(_ rows: inout SettingsRows) {
        rows.row("Prefer Music Only", "audio", "video", "prefer music", "song", "stream") {
            SettingsToggleLine(
                glyph: .musicOnly,
                title: "Prefer Music Only",
                subtitle: "Always stream the official audio track instead of video/MV audio",
                isOn: $preferMusicOnly
            )
        }
        rows.row("Hide Recents", "recents", "recent", "history", "home", "listen again") {
            SettingsToggleLine(
                glyph: .hideRecents,
                title: "Hide Recents",
                subtitle: "Hide the recently played tracks shelf from Home",
                isOn: $hideRecents
            )
        }
        rows.row("Hide Home Videos", "video", "music video", "feed", "home", "filter") {
            SettingsToggleLine(
                glyph: .hideVideos,
                title: "Hide Home Videos",
                subtitle: "Filter out non-music video recommendations from Home",
                isOn: $hideHomeVideos
            )
        }
        rows.row("Hide Top Picks", "top picks", "recommendations", "quick picks", "home") {
            SettingsToggleLine(
                glyph: .topPicks,
                title: "Hide Top Picks",
                subtitle: "Hide algorithmic recommendations from Home",
                isOn: $hideTopPicks
            )
        }
        rows.row("Hide Mood Stations", "mood", "moods", "activity", "stations", "home") {
            SettingsToggleLine(
                glyph: .moods,
                title: "Hide Mood Stations",
                subtitle: "Hide mood and activity playlist categories from Home",
                isOn: $hideHomeMoods
            )
        }
        rows.row("Square Video Thumbnails", "thumbnail", "aspect", "square", "video", "cover") {
            SettingsToggleLine(
                glyph: .squareThumbnails,
                title: "Square Video Thumbnails",
                subtitle: "Standardize video thumbnails to 1:1 squares to match album art",
                isOn: $squareVideoThumbnails
            )
        }
    }
}

