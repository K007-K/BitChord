// New widget views: style-aware home-screen views and lock-screen views.
// Companion to WidgetViews.swift. Existing CompactWidgetView / WideWidgetView / PillWidgetView
// gain a style property; new LargeWidgetView and lock-screen views live here.
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Style background helpers

/// A blurred, heavily-darkened cover used as the Glass-style background.
struct GlassBackground: View {
    var art: WidgetArt?

    var body: some View {
        ZStack {
            if let art {
                Image(uiImage: art.body)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetPlaceholderArt()
            }
            Color.black.opacity(0.30)
        }
        .accessibilityHidden(true)
    }
}

/// A solid near-black card used as the Minimal-style background.
struct MinimalBackground: View {
    var body: some View {
        Color(red: 0x0F / 255, green: 0x10 / 255, blue: 0x17 / 255)
            .accessibilityHidden(true)
    }
}

/// A compact rounded-square artwork thumbnail used in Glass and Minimal styles.
struct ArtThumbnail: View {
    var art: WidgetArt?
    var size: CGFloat

    var body: some View {
        Group {
            if let art {
                Image(uiImage: art.cover)
                    .resizable()
                    .scaledToFill()
            } else {
                WidgetPlaceholderArt()
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
        .accessibilityLabel(SharedStrings.widgetArtwork)
    }
}

// MARK: - Style background chooser (WidgetKit canvas)

extension View {
    @ViewBuilder
    func styleBackground(
        _ style: WidgetStyle,
        art: WidgetArt?,
        band: CGFloat,
        canvas: WidgetCanvas
    ) -> some View {
        switch style {
        case .artwork:
            self.widgetBackground(canvas) { WidgetCoverBackdrop(art: art, band: band) }
        case .glass:
            self.widgetBackground(canvas) { GlassBackground(art: art) }
        case .minimal:
            self.widgetBackground(canvas) { MinimalBackground() }
        }
    }
}

// MARK: - Glass / Minimal content layouts (small)

struct StyledCompactContent: View {
    var face: WidgetFace
    var art: WidgetArt?
    var style: WidgetStyle

    var body: some View {
        if style == .artwork {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                Text(face.title)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 4)
                HStack(spacing: 0) {
                    WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill",
                                  label: SharedStrings.widgetPrevious,
                                  opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 17, height: 40)
                    WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol,
                                  label: face.toggleLabel,
                                  opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 20, height: 40)
                    WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill",
                                  label: SharedStrings.widgetNext,
                                  opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 17, height: 40)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ArtThumbnail(art: art, size: 60)
                    .padding(.leading, 2)
                Spacer(minLength: 0)
                Text(face.title)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
                HStack(spacing: 0) {
                    WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill",
                                  label: SharedStrings.widgetPrevious,
                                  opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 14, height: 34)
                    WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol,
                                  label: face.toggleLabel,
                                  opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 17, height: 34)
                    WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill",
                                  label: SharedStrings.widgetNext,
                                  opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 14, height: 34)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Glass / Minimal content layouts (medium-wide)

struct StyledWideContent: View {
    var face: WidgetFace
    var art: WidgetArt?
    var style: WidgetStyle

    var body: some View {
        if style == .artwork {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(face.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if face.hasTrack, let artist = face.artist {
                            Text(artist)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 8)
                    WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill",
                                  label: SharedStrings.widgetPrevious,
                                  opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 18, height: 44, fillsWidth: false)
                    WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol,
                                  label: face.toggleLabel,
                                  opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 22, height: 44, fillsWidth: false)
                    WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill",
                                  label: SharedStrings.widgetNext,
                                  opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 18, height: 44, fillsWidth: false)
                }
                .frame(height: 60)
                .padding(.leading, 14)
                .padding(.trailing, 4)
            }
        } else {
            HStack(spacing: 12) {
                ArtThumbnail(art: art, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(face.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if face.hasTrack, let artist = face.artist {
                        Text(artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill",
                                      label: SharedStrings.widgetPrevious,
                                      opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 16, height: 36, fillsWidth: false)
                        WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol,
                                      label: face.toggleLabel,
                                      opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 20, height: 36, fillsWidth: false)
                        WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill",
                                      label: SharedStrings.widgetNext,
                                      opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 16, height: 36, fillsWidth: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - CompactWidgetView / WideWidgetView / PillWidgetView style extensions

extension CompactWidgetView {
    init(snapshot: NowPlayingSnapshot?, art: WidgetArt?, style: WidgetStyle) {
        self.snapshot = snapshot
        self.art      = art
        self.style    = style
    }
}

extension WideWidgetView {
    init(snapshot: NowPlayingSnapshot?, art: WidgetArt?, style: WidgetStyle) {
        self.snapshot = snapshot
        self.art      = art
        self.style    = style
    }
}

extension PillWidgetView {
    init(snapshot: NowPlayingSnapshot?, art: WidgetArt?, style: WidgetStyle) {
        self.snapshot = snapshot
        self.art      = art
        self.style    = style
    }
}

// MARK: - Large Widget (NEW)

/// 4×4 large home-screen widget: big cover + full five-button transport.
struct LargeWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?
    var style: WidgetStyle = .artwork
    var canvas: WidgetCanvas = .widgetKit

    static let band: CGFloat = 88

    var body: some View {
        let face = WidgetFace(snapshot)
        VStack(spacing: 0) {
            if style != .artwork {
                Group {
                    if let art {
                        Image(uiImage: art.cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        WidgetPlaceholderArt()
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: style == .minimal ? 190 : 180)
                .clipShape(RoundedRectangle(cornerRadius: style == .minimal ? 18 : 0, style: .continuous))
                .padding(style == .minimal ? 12 : 0)
                .padding(.top, style == .minimal ? 4 : 0)
                .accessibilityLabel(SharedStrings.widgetArtwork)
            } else {
                Spacer(minLength: 0)
            }
            VStack(spacing: 2) {
                Text(face.title)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if face.hasTrack, let artist = face.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 0) {
                    WidgetControl(intent: ToggleLikeIntent(), symbol: face.likeSymbol,
                                  label: face.likeLabel,
                                  opacity: face.opacity(.like), isLive: face.hasTrack, glyph: 20, height: 52,
                                  isOn: face.hasTrack && face.isLiked)
                    WidgetControl(intent: PreviousTrackIntent(), symbol: "backward.fill",
                                  label: SharedStrings.widgetPrevious,
                                  opacity: face.opacity(.previous), isLive: face.hasTrack, glyph: 22, height: 52)
                    WidgetControl(intent: TogglePlaybackIntent(), symbol: face.toggleSymbol,
                                  label: face.toggleLabel,
                                  opacity: face.opacity(.togglePlayPause), isLive: face.hasTrack, glyph: 30, height: 52)
                    WidgetControl(intent: NextTrackIntent(), symbol: "forward.fill",
                                  label: SharedStrings.widgetNext,
                                  opacity: face.opacity(.next), isLive: face.hasTrack, glyph: 22, height: 52)
                    WidgetControl(intent: ToggleShuffleIntent(), symbol: "shuffle",
                                  label: face.shuffleLabel,
                                  opacity: face.opacity(.shuffle), isLive: face.hasTrack, glyph: 18, height: 52,
                                  isOn: face.hasTrack && face.shuffleEnabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .padding(.top, 8)
            .frame(height: Self.band)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .styleBackground(style, art: art, band: Self.band, canvas: canvas)
        .widgetURL(SharedConstants.openPlayerURL)
    }
}

// MARK: - Lock Screen Circular (NEW)

/// Lock Screen circular widget: artwork circle with play/pause overlay.
struct LockCircularWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?

    var body: some View {
        let face = WidgetFace(snapshot)
        ZStack {
            if let art {
                Image(uiImage: art.cover)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Circle().fill(Color(white: 0.15))
            }
            if face.isPlaying {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .widgetURL(SharedConstants.openPlayerURL)
        .accessibilityLabel(face.title)
    }
}

// MARK: - Lock Screen Rectangular (NEW)

/// Lock Screen rectangular widget: title + artist + prev/play/next.
struct LockRectangularWidgetView: View {
    var snapshot: NowPlayingSnapshot?
    var art: WidgetArt?

    var body: some View {
        let face = WidgetFace(snapshot)
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(face.title)
                    .font(.system(.caption, weight: .semibold))
                    .lineLimit(1)
                if face.hasTrack, let artist = face.artist {
                    Text(artist)
                        .font(.system(.caption2))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(intent: PreviousTrackIntent()) {
                Image(systemName: "backward.fill").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!face.hasTrack)
            Button(intent: TogglePlaybackIntent()) {
                Image(systemName: face.toggleSymbol).font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!face.hasTrack)
            Button(intent: NextTrackIntent()) {
                Image(systemName: "forward.fill").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .disabled(!face.hasTrack)
        }
        .widgetURL(SharedConstants.openPlayerURL)
        .accessibilityLabel(face.pillTitle)
    }
}
