// Widgets settings screen: previews of all available BitChord widgets with add-to-home-screen guidance.
import SwiftUI
import WidgetKit

/// Opened from Settings → Widgets.
/// Shows a visual catalogue of every available widget with its size, description and style options.
struct WidgetsScreen: View {
    var body: some View {
        List {
            // MARK: - Home Screen section
            Section {
                WidgetCatalogRow(
                    symbol: "square.fill",
                    title: "Now Playing 2×2",
                    description: "Album art with playback controls, in a small square.",
                    sizes: "Small",
                    styles: true
                )
                WidgetCatalogRow(
                    symbol: "rectangle.fill",
                    title: "Now Playing 4×2",
                    description: "Full-width album art with the track title, artist and playback controls.",
                    sizes: "Medium",
                    styles: true
                )
                WidgetCatalogRow(
                    symbol: "rectangle.split.3x1.fill",
                    title: "Now Playing 4×1",
                    description: "Track info with Like, Shuffle and playback controls in a single pill row.",
                    sizes: "Medium",
                    styles: true
                )
                WidgetCatalogRow(
                    symbol: "square.fill.on.square.fill",
                    title: "Now Playing 4×4",
                    description: "Big album art with full five-button transport — Like, Previous, Play, Next, Shuffle.",
                    sizes: "Large",
                    styles: true
                )
            } header: {
                Label("Home Screen", systemImage: "iphone")
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
            } footer: {
                Text("Long-press any widget on the Home Screen and tap **Edit Widget** to pick a style: Artwork (default), Glass, or Minimal.")
                    .font(.footnote)
            }

            // MARK: - Lock Screen section
            Section {
                WidgetCatalogRow(
                    symbol: "circle.fill",
                    title: "Circular",
                    description: "Album art in a small circle. Tap to open the player.",
                    sizes: "Accessory Circular",
                    styles: false
                )
                WidgetCatalogRow(
                    symbol: "rectangle.leadinghalf.inset.filled",
                    title: "Lock Screen Bar",
                    description: "Track name, artist and Previous / Play / Next controls in a compact bar.",
                    sizes: "Accessory Rectangular",
                    styles: false
                )
            } header: {
                Label("Lock Screen", systemImage: "lock.iphone")
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
            } footer: {
                Text("Long-press the Lock Screen → Customise → Lock Screen to add these widgets.")
                    .font(.footnote)
            }

            // MARK: - Style guide section
            Section {
                WidgetStylePreviewRow(
                    style: "Artwork",
                    symbol: "photo.fill",
                    description: "Full-bleed album art — the original BitChord look.",
                    color: .purple
                )
                WidgetStylePreviewRow(
                    style: "Glass",
                    symbol: "circle.hexagongrid.fill",
                    description: "Heavy-blurred art fills the background; the cover floats in a rounded square.",
                    color: .blue
                )
                WidgetStylePreviewRow(
                    style: "Minimal",
                    symbol: "square.lefthalf.filled",
                    description: "Solid dark card with a compact art thumbnail and clean white text.",
                    color: .gray
                )
            } header: {
                Label("Widget Styles", systemImage: "paintpalette.fill")
                    .textCase(nil)
                    .font(.subheadline.weight(.semibold))
            } footer: {
                Text("Styles are set per widget individually — you can mix Artwork on the small and Minimal on the large.")
                    .font(.footnote)
            }

            // MARK: - Reload tip
            Section {
                Button {
                    WidgetCenter.shared.reloadAllTimelines()
                } label: {
                    Label("Refresh all widgets now", systemImage: "arrow.clockwise")
                }
            } footer: {
                Text("Widgets update automatically when BitChord is in the foreground. Tap here to force-refresh them all.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Widgets")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Sub-views

/// One row for a widget in the catalogue.
private struct WidgetCatalogRow: View {
    var symbol: String
    var title: String
    var description: String
    var sizes: String
    var styles: Bool

    var body: some View {
        HStack(spacing: SettingsMetrics.iconGap) {
            SettingsIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    SizeTag(sizes)
                    if styles { StyleTag() }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small size/style tag pill.
private struct SizeTag: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct StyleTag: View {
    var body: some View {
        Text("3 Styles")
            .font(.caption2.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// One row in the style guide section.
private struct WidgetStylePreviewRow: View {
    var style: String
    var symbol: String
    var description: String
    var color: Color

    var body: some View {
        HStack(spacing: SettingsMetrics.iconGap) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(color)
                .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(style)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
