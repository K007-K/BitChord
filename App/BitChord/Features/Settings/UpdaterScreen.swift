// UpdaterScreen.swift — In-app updater: checks GitHub releases, downloads IPA, opens in eSign.
import SwiftUI

// MARK: - Models

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String
    let body: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

private enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(release: GitHubRelease, ipaURL: String)
    case downloading(progress: Double)
    case downloaded(localURL: URL)
    case error(message: String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking): return true
        case (.upToDate(let a), .upToDate(let b)): return a == b
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.downloaded(let a), .downloaded(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        case (.updateAvailable, .updateAvailable): return true
        default: return false
        }
    }
}

// MARK: - UpdaterScreen

/// Settings → Check for Updates screen.
/// Fetches api.github.com/repos/K007-K/BitChord/releases/latest, compares tag_name to
/// CFBundleShortVersionString, and lets the user download the IPA and open it in eSign.
struct UpdaterScreen: View {
    @State private var state: UpdateState = .idle
    @State private var docController: UIDocumentInteractionControllerHolder?

    private let githubRepo = "K007-K/BitChord"
    private let apiURL = "https://api.github.com/repos/K007-K/BitChord/releases/latest"
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

    var body: some View {
        List {
            // Current version header
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BitChord")
                            .font(.headline)
                        Text("Installed: v\(currentVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // State-driven body
            switch state {
            case .idle:
                Section {
                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        HStack {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                            Spacer()
                        }
                    }
                }

            case .checking:
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Checking for updates…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

            case .upToDate(let version):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("You're up to date", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("v\(version) is the latest release.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                }

            case .updateAvailable(let release, let ipaURL):
                Section(header: Text("New Version Available")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(release.name.isEmpty ? release.tagName : release.name)
                            .font(.headline)
                        Text("Your version: v\(currentVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if !release.body.isEmpty {
                    Section(header: Text("What's New")) {
                        Text(release.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                Section {
                    Button {
                        Task { await downloadIPA(urlString: ipaURL) }
                    } label: {
                        Label("Download & Install", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                    }
                }
                Section(footer: Text("The IPA will be downloaded and opened in eSign (or Files). Tap \u{201C}Open in eSign\u{201D} to install.")) {
                    EmptyView()
                }

            case .downloading(let progress):
                Section(header: Text("Downloading Update")) {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                        Text("\(Int(progress * 100))% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

            case .downloaded(let url):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Download Complete", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Tap below to open in eSign and install.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        openInESign(url: url)
                    } label: {
                        Label("Open in eSign / Files", systemImage: "arrow.up.forward.app.fill")
                            .font(.headline)
                    }
                }

            case .error(let message):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Something went wrong", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button {
                        Task { await checkForUpdates() }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                }
            }

            // Footer note
            Section(footer: Text("Updates are hosted on GitHub (K007-K/BitChord). BitChord is a sideloaded app — you must reinstall via eSign each time.")) {
                EmptyView()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Check for Updates")
        .navigationBarTitleDisplayMode(.large)
        .task { await checkForUpdates() }
    }

    // MARK: - Logic

    @MainActor
    private func checkForUpdates() async {
        state = .checking
        do {
            let release = try await fetchLatestRelease()
            let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if isNewer(latestVersion, than: currentVersion) {
                // Find the first .ipa asset
                if let ipaAsset = release.assets.first(where: { $0.name.hasSuffix(".ipa") }) {
                    state = .updateAvailable(release: release, ipaURL: ipaAsset.browserDownloadURL)
                } else {
                    // No IPA asset — still show the release info
                    state = .updateAvailable(release: release, ipaURL: "")
                }
            } else {
                state = .upToDate(version: latestVersion)
            }
        } catch {
            state = .error(message: error.localizedDescription)
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: apiURL) else {
            throw UpdaterError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BitChord-iOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdaterError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    @MainActor
    private func downloadIPA(urlString: String) async {
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            state = .error(message: "No IPA asset found in this release. Please check GitHub manually.")
            return
        }
        state = .downloading(progress: 0)
        do {
            let localURL = try await downloadWithProgress(from: url)
            state = .downloaded(localURL: localURL)
        } catch {
            state = .error(message: "Download failed: \(error.localizedDescription)")
        }
    }

    private func downloadWithProgress(from remoteURL: URL) async throws -> URL {
        let (asyncBytes, response) = try await URLSession.shared.bytes(from: remoteURL)
        let totalBytes = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length")
            .flatMap { Int($0) } ?? 0

        // Write to Documents directory so the user can also find it in Files
        let fileName = remoteURL.lastPathComponent.isEmpty ? "BitChord.ipa" : remoteURL.lastPathComponent
        let destURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)

        // Remove old file if present
        try? FileManager.default.removeItem(at: destURL)

        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destURL) else {
            throw UpdaterError.fileWrite
        }
        defer { try? handle.close() }

        // Buffer in 256 KB chunks — avoids 44M single-byte disk writes that caused slow downloads
        let chunkSize = 256 * 1024
        var buffer = Data(capacity: chunkSize)
        var received = 0

        for try await byte in asyncBytes {
            buffer.append(byte)
            received += 1

            if buffer.count >= chunkSize {
                handle.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }

            if totalBytes > 0, received % 51200 == 0 {
                let progress = Double(received) / Double(totalBytes)
                await MainActor.run { state = .downloading(progress: min(progress, 0.99)) }
            }
        }

        // Flush any remaining bytes
        if !buffer.isEmpty {
            handle.write(buffer)
        }

        return destURL
    }

    private func openInESign(url: URL) {
        let holder = UIDocumentInteractionControllerHolder(url: url)
        docController = holder
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        holder.controller.presentOpenInMenu(from: .zero, in: rootVC.view, animated: true)
    }

    /// Returns true if `a` is strictly newer than `b` (simple dot-separated integer comparison).
    private func isNewer(_ a: String, than b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        let count = max(partsA.count, partsB.count)
        for i in 0..<count {
            let vA = i < partsA.count ? partsA[i] : 0
            let vB = i < partsB.count ? partsB[i] : 0
            if vA != vB { return vA > vB }
        }
        return false
    }
}

// MARK: - Helpers

private enum UpdaterError: LocalizedError {
    case invalidURL
    case badResponse(Int)
    case fileWrite

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid GitHub API URL."
        case .badResponse(let code): return "GitHub returned HTTP \(code). Check your internet connection."
        case .fileWrite: return "Could not write the downloaded file to disk."
        }
    }
}

/// Keeps UIDocumentInteractionController alive while the share sheet is open.
private final class UIDocumentInteractionControllerHolder: NSObject, UIDocumentInteractionControllerDelegate {
    let controller: UIDocumentInteractionController

    init(url: URL) {
        controller = UIDocumentInteractionController(url: url)
        super.init()
        controller.delegate = self
        controller.uti = "com.apple.itunes.ipa"
    }
}
