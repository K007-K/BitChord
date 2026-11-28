<div align="center">

<br/>

<img src=".github/assets/icon.png" alt="BitChord app icon" width="160" />

# BitChord for iOS

### A YouTube Music client for iPhone and iPad — maintained by K007-K

<br/>

[![Version](https://img.shields.io/badge/version-v1.0.6-e5404f?style=for-the-badge&labelColor=0d1117)](#install)
[![Platform](https://img.shields.io/badge/iOS-17%2B-0d1117?style=for-the-badge)](#requirements)
[![License](https://img.shields.io/github/license/K007-K/BitChord?style=for-the-badge&labelColor=0d1117)](LICENSE)
[![Release](https://img.shields.io/github/v/release/K007-K/BitChord?style=for-the-badge&labelColor=0d1117&color=e5404f)](https://github.com/K007-K/BitChord/releases/latest)

<br/>

[Install](#install) · [Features](#features) · [What's New](#whats-new-in-v106) · [Build from Source](#building-from-source) · [Credits](#credits) · [Disclaimer](#disclaimer-and-legal-notice)

</div>

> [!IMPORTANT]
> BitChord is not affiliated with, endorsed by, or connected to YouTube, Google or Apple in any way. Use it at your own discretion.

---

## What this is

BitChord for iOS is a native SwiftUI YouTube Music client for iPhone and iPad. This build is independently maintained by [K007-K](https://github.com/K007-K) with custom features, bug fixes and improvements on top of the community iOS port.

**In-app updater:** This build includes a built-in updater — once installed, go to **Settings → Updates → Check for Updates** to download and install new versions without needing a Mac each time.

---

## What's New in v1.0.6

### 🎨 Customizable Widgets
- **Small (2×2):** Album art + compact controls
- **Medium 4×2:** Full-width artwork + title, artist, controls
- **Medium 4×1:** Pill row with track info + all controls
- **Large 4×4:** Big cover + full 5-button transport (Like, Prev, Play, Next, Shuffle)
- **Lock Screen Circular:** Album art circle
- **Lock Screen Bar:** Track + Prev/Play/Next in a compact bar
- **3 styles per widget:** Artwork (default), Glass (blurred background), Minimal (dark card)
- Pick a style per widget: long-press → Edit Widget

### 🔄 In-App Updater
- Settings → Updates → **Check for Updates**
- Fetches the latest release from GitHub automatically
- Downloads IPA with a live progress bar
- Opens in eSign for one-tap install — no Mac needed after first install

### 🐛 Fixes
- Fixed app jumping to player every time it came to foreground with music playing
- Widgets show a branded placeholder instead of grey boxes when sideloaded via eSign
- Listen Together party server updated for Android compatibility

---

## Features

### Playback
- Search, browse and play the YouTube Music catalogue: Home, Explore, moods, genres, artist, album and playlist pages.
- Separate streaming quality for Wi-Fi and mobile data, plus a Dolby Atmos option.
- Optional add-on sources for lossless and Atmos streams, with YouTube Music as the fallback.
- Crossfade (0–12 s), Automix, loudness normalization, skip silence, equalizer.
- On-device song cache with an adjustable size limit.
- Stats for nerds: codec, bitrate and audio pipeline on the Now Playing screen.

### Lyrics
- Synced lyrics with line and word highlighting from multiple providers: LRCLIB, Musixmatch, Genius, KuGou, and more.
- Translate lyrics, adjust timing offset, share lines as an image card.

### Library & Offline
- Sign in with Google for your YouTube Music library, playlists and history.
- Download tracks for offline play with metadata and lyrics baked in.
- Import audio from the Files app. Play from SMB and WebDAV network shares.
- Export and import settings and listening history as JSON.

### Widgets & System
- **Home Screen widgets:** Small, Medium (4×2 and 4×1), Large (4×4) — all with 3 style options.
- **Lock Screen widgets:** Circular album art, Rectangular bar with controls.
- Lock Screen and Control Center controls.
- Share extension for YouTube / YouTube Music links.
- App Intents for playback. CarPlay interface (requires Apple entitlement).

### Social & Integrations
- **Listen Together:** host a party, invite with a code, link or QR code.
- **Replay:** listening stats by period with a shareable poster.
- Scrobbling to Last.fm and ListenBrainz.
- Discord Rich Presence.

### Look & Feel
- Animated cover art from Apple Music, Tidal, Spotify and community index.
- Player colours from album artwork. Landscape player + iPad support.
- 5 app icons. 16 languages.

---

## Requirements

- iPhone or iPad running **iOS 17 or later**.
- A sideloading tool: **eSign** (free), AltStore or SideStore.

> [!NOTE]
> For live widget data (actual song/art in widgets), install via **AltStore or SideStore**. eSign strips the App Group entitlement that lets the app share data with its widgets. With eSign, widgets show a styled BitChord placeholder.

---

## Install

### Option 1 — eSign (easiest, free)
1. Download the latest IPA from the [Releases page](https://github.com/K007-K/BitChord/releases/latest).
2. Install using [eSign](https://esign.yyyue.xyz/).
3. Open the app → **Settings → Updates → Check for Updates** for future updates — no Mac needed.

### Option 2 — AltStore / SideStore
1. Download the latest IPA from the [Releases page](https://github.com/K007-K/BitChord/releases/latest).
2. Add it via AltStore or SideStore.
3. Widgets will show live now-playing data (App Group works with these tools).

---

## Building from Source

### Requirements
- macOS with Xcode 16 or later.
- An Apple Developer account (free tier works for local builds).

### Steps

```bash
git clone https://github.com/K007-K/BitChord.git
cd BitChord
open BitChord.xcworkspace
```

Select the `BitChord` scheme, choose your device or simulator, and build.

> [!NOTE]
> The project uses a local ONNX Runtime stub (`scratch/onnxruntime-stub/`) so the build works without the upstream Swift package. No changes needed.

### Build unsigned IPA (for eSign)

```bash
xcodebuild \
  -workspace BitChord.xcworkspace \
  -scheme BitChord \
  -configuration Release \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Then package the `.app` into a Payload folder and zip as `.ipa`.

---

## Project Structure

```
App/
  BitChord/            iOS app target
    App/               entry point, root view, scene lifecycle
    Features/          one folder per screen (NowPlaying, Browse, Settings, …)
    Services/          AppModel, PlayerController, PlaybackObservers, …
    Navigation/        AppRouter, DeepLink, AppRoute
    Intents/           App Intents and Siri support
  BitChordWidget/      Widget extension (home screen + lock screen)
  Shared/              code compiled into both app and widget
BitChordKit/           Swift package — the audio engine and logic
  Sources/
    BitChordCore       shared models and utilities
    AudioPlayer        AVFoundation player
    AudioCache         on-disk cache
    AudioDSP           equalizer, loudness, skip silence, spatial audio
    Automix            transition planning
    Lyrics             providers, parsing, storage, translation
    Downloads          offline downloads
    ListenTogether     party client
    Integrations       Last.fm, ListenBrainz, Discord
    Replay             listening stats
```

---

## Credits

### Original iOS Port
Based on the community iOS port of [BitChord](https://github.com/bagumamartin/BitChord) by [bagumamartin](https://github.com/bagumamartin). The design, screen layout and core logic come from that project.

### BitChord for Android
The iOS app mirrors [BitChord for Android](https://github.com/kushagrasinghx/BitChord) by [Kushagra Singh](https://github.com/kushagrasinghx), licensed under GPL-3.0.

### Third-party Libraries
- [AMSMB2](https://github.com/amosavian/AMSMB2) — SMB share support (LGPL-2.1)
- [ONNX Runtime](https://github.com/microsoft/onnxruntime-swift-package-manager) — Automix models (MIT)
- Beat This! (CPJKU) and Open-Unmix (Inria/SigSep) ML models

### Services
Lyrics: LRCLIB, Musixmatch, Genius, KuGou, PaxSenix, BetterLyrics and more.  
Animated covers: Apple Music, Tidal, Spotify, community canvas index.  
Listen Together: BitChord party backend.

---

## Disclaimer and Legal Notice

BitChord for iOS is an independent, community-driven third-party audio player. It is not associated with Google LLC, YouTube, YouTube Music, Apple Inc. or any of their affiliates.

- **No media hosting.** BitChord does not host, upload or store copyrighted music.
- **Fair use.** This software is for personal research, education and fair use. You are responsible for compliance with your local copyright laws and the YouTube Terms of Service.
- **No service guarantee.** BitChord does not guarantee that any third-party platform will continue to work with it.
- **Copyleft.** BitChord is free software under GPL-3.0. Any distribution must include the source under the same license.

## License

Licensed under the [GNU General Public License v3.0](LICENSE). Files ported from Orchard remain under AGPL-3.0 as their headers state. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for the full list.
