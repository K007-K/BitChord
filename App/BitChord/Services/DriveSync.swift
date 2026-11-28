// Google Drive appDataFolder OAuth, REST v3 client, and cross-device Replay sync compatible with BitChord Android.
import AuthenticationServices
import BitChordCore
import CryptoKit
import Foundation
import Observation
import OSLog
import Replay
import Security
import UIKit
import zlib

private let driveLog = Logger(subsystem: "com.music.bitchord", category: "DriveSync")

// MARK: - Gzip Codec (zlib RFC 1952)

enum GzipCodec {
    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        var status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            MAX_MEM_LEVEL,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw NSError(
                domain: "GzipCodec",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize gzip compression"]
            )
        }
        defer { deflateEnd(&stream) }

        var output = Data(capacity: max(64, data.count / 2))
        let chunkSize = 16_384
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)

            repeat {
                try buffer.withUnsafeMutableBytes { outRaw in
                    guard let outPtr = outRaw.bindMemory(to: Bytef.self).baseAddress else { return }
                    stream.next_out = outPtr
                    stream.avail_out = uInt(chunkSize)
                    status = deflate(&stream, Z_FINISH)
                    if status == Z_STREAM_ERROR {
                        throw NSError(
                            domain: "GzipCodec",
                            code: Int(status),
                            userInfo: [NSLocalizedDescriptionKey: "Gzip compression failed"]
                        )
                    }
                    let have = chunkSize - Int(stream.avail_out)
                    if have > 0 { output.append(outPtr, count: have) }
                }
            } while stream.avail_out == 0
        }
        return output
    }

    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var stream = z_stream()
        var status = inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw NSError(
                domain: "GzipCodec",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to initialize gzip decompression"]
            )
        }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: data.count * 3)
        let chunkSize = 16_384
        var buffer = [UInt8](repeating: 0, count: chunkSize)

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)

            repeat {
                buffer.withUnsafeMutableBytes { outRaw in
                    guard let outPtr = outRaw.bindMemory(to: Bytef.self).baseAddress else { return }
                    stream.next_out = outPtr
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    let have = chunkSize - Int(stream.avail_out)
                    if have > 0 { output.append(outPtr, count: have) }
                }
                if status != Z_OK && status != Z_STREAM_END && status != Z_BUF_ERROR {
                    throw NSError(
                        domain: "GzipCodec",
                        code: Int(status),
                        userInfo: [NSLocalizedDescriptionKey: "Gzip decompression failed"]
                    )
                }
            } while status != Z_STREAM_END && stream.avail_out == 0
        }
        return output
    }
}

// MARK: - Keychain Storage

private enum DriveKeychain {
    private static let service = "com.music.bitchord.drive"

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - OAuth (PKCE via ASWebAuthenticationSession)

/// Handles Google OAuth 2.0 PKCE sign-in, token refresh, and revocation for the `drive.appdata` scope.
@MainActor
final class DriveAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let scope = "https://www.googleapis.com/auth/drive.appdata"
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private static let revokeEndpoint = "https://oauth2.googleapis.com/revoke"

    private static let accessTokenKey = "drive_access_token"
    private static let refreshTokenKey = "drive_refresh_token"
    private static let expiresAtKey = "drive_expires_at"
    private static let customClientIdKey = "drive_custom_client_id"

    /// Resolves the iOS OAuth Client ID from environment, Info.plist, or Keychain override.
    static func resolvedClientId() -> String? {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_DRIVE_CLIENT_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty,
           !env.hasPrefix("$(") {
            return env
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_DRIVE_CLIENT_ID") as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        if let saved = DriveKeychain.load(account: customClientIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            return saved
        }
        return nil
    }

    static func setCustomClientId(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            DriveKeychain.delete(account: customClientIdKey)
        } else {
            DriveKeychain.save(trimmed, account: customClientIdKey)
        }
    }

    static func customClientId() -> String {
        DriveKeychain.load(account: customClientIdKey) ?? ""
    }

    static func redirectScheme(for clientId: String) -> String {
        let prefix = clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    func validAccessToken() async throws -> String {
        do {
            if let token = DriveKeychain.load(account: Self.accessTokenKey),
               let expRaw = DriveKeychain.load(account: Self.expiresAtKey),
               let exp = Double(expRaw),
               Date().timeIntervalSince1970 < exp - 60 {
                return token
            }
            if let refresh = DriveKeychain.load(account: Self.refreshTokenKey),
               let clientId = Self.resolvedClientId() {
                return try await refreshAccessToken(refreshToken: refresh, clientId: clientId)
            }
            throw NSError(
                domain: "DriveAuth",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Google Drive sign-in required"]
            )
        } catch {
            driveLog.error("Unable to obtain valid access token: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func signIn() async throws -> String {
        do {
            guard let clientId = Self.resolvedClientId() else {
                throw NSError(
                    domain: "DriveAuth",
                    code: 400,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Set GOOGLE_DRIVE_CLIENT_ID in environment, Info.plist, or Configure OAuth Client ID below.",
                    ]
                )
            }
            let verifier = Self.randomVerifier()
            let challenge = Self.codeChallenge(for: verifier)
            let scheme = Self.redirectScheme(for: clientId)
            let redirectURI = "\(scheme):/oauth2redirect"

            var components = URLComponents(string: Self.authEndpoint)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scope),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]
            guard let authURL = components.url else {
                throw URLError(.badURL)
            }

            let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: scheme
                ) { url, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: URLError(.cancelled))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }

            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let err = items.first(where: { $0.name == "error" })?.value {
                throw NSError(
                    domain: "DriveAuth",
                    code: 403,
                    userInfo: [NSLocalizedDescriptionKey: "Google sign-in failed: \(err)"]
                )
            }
            guard let code = items.first(where: { $0.name == "code" })?.value else {
                throw NSError(
                    domain: "DriveAuth",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Missing authorization code"]
                )
            }
            return try await exchangeCode(code: code, clientId: clientId, verifier: verifier, redirectURI: redirectURI)
        } catch {
            driveLog.error("Google Drive OAuth sign-in failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func revokeAndClear() async {
        let token = DriveKeychain.load(account: Self.refreshTokenKey) ?? DriveKeychain.load(account: Self.accessTokenKey)
        DriveKeychain.delete(account: Self.accessTokenKey)
        DriveKeychain.delete(account: Self.refreshTokenKey)
        DriveKeychain.delete(account: Self.expiresAtKey)
        guard let token, var components = URLComponents(string: Self.revokeEndpoint) else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        do {
            _ = try await URLSession.shared.data(for: req)
        } catch {
            driveLog.error("Failed to revoke Google Drive token: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func exchangeCode(code: String, clientId: String, verifier: String, redirectURI: String) async throws -> String {
        do {
            return try await requestToken(params: [
                "client_id": clientId,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
            ])
        } catch {
            driveLog.error("OAuth code exchange failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func refreshAccessToken(refreshToken: String, clientId: String) async throws -> String {
        do {
            return try await requestToken(params: [
                "client_id": clientId,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ])
        } catch {
            driveLog.error("OAuth token refresh failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private func requestToken(params: [String: String]) async throws -> String {
        do {
            var req = URLRequest(url: URL(string: Self.tokenEndpoint)!)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var components = URLComponents()
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = components.percentEncodedQuery?.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? "Token exchange failed"
                throw NSError(
                    domain: "DriveAuth",
                    code: (response as? HTTPURLResponse)?.statusCode ?? 500,
                    userInfo: [NSLocalizedDescriptionKey: text]
                )
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            guard let access = json["access_token"] as? String else {
                throw NSError(
                    domain: "DriveAuth",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "Missing access_token in response"]
                )
            }
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            DriveKeychain.save(access, account: Self.accessTokenKey)
            DriveKeychain.save(String(Date().timeIntervalSince1970 + expiresIn), account: Self.expiresAtKey)
            if let refresh = json["refresh_token"] as? String {
                DriveKeychain.save(refresh, account: Self.refreshTokenKey)
            }
            return access
        } catch {
            driveLog.error("OAuth token request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Drive REST API v3

struct DriveFileInfo: Identifiable {
    let id: String
    let name: String
    let md5: String?
    let modifiedAt: String
    let sizeBytes: Int64
    let properties: [String: String]
}

struct DriveProfile {
    let email: String?
    let name: String?
}

/// Minimal Google Drive REST v3 client targeting `appDataFolder`.
enum DriveApi {
    private static let apiBase = "https://www.googleapis.com/drive/v3"
    private static let uploadBase = "https://www.googleapis.com/upload/drive/v3"
    private static let fields = "id,name,md5Checksum,modifiedTime,size,appProperties"

    static func profile(token: String) async throws -> DriveProfile {
        do {
            var components = URLComponents(string: "\(apiBase)/about")!
            components.queryItems = [URLQueryItem(name: "fields", value: "user(emailAddress,displayName)")]
            var req = URLRequest(url: components.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await execute(req)
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let user = root?["user"] as? [String: Any]
            return DriveProfile(
                email: user?["emailAddress"] as? String,
                name: user?["displayName"] as? String
            )
        } catch {
            driveLog.error("DriveApi.profile failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func listAll(token: String) async throws -> [DriveFileInfo] {
        do {
            var all: [DriveFileInfo] = []
            var pageToken: String?
            repeat {
                var components = URLComponents(string: "\(apiBase)/files")!
                var items = [
                    URLQueryItem(name: "spaces", value: "appDataFolder"),
                    URLQueryItem(name: "fields", value: "nextPageToken,files(\(fields))"),
                    URLQueryItem(name: "pageSize", value: "200"),
                ]
                if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
                components.queryItems = items

                var req = URLRequest(url: components.url!)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await execute(req)
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                let files = root["files"] as? [[String: Any]] ?? []
                for item in files {
                    guard let id = item["id"] as? String,
                          let name = item["name"] as? String else { continue }
                    let sizeStr = item["size"] as? String
                    let size = sizeStr.flatMap(Int64.init) ?? (item["size"] as? Int64) ?? 0
                    all.append(DriveFileInfo(
                        id: id,
                        name: name,
                        md5: item["md5Checksum"] as? String,
                        modifiedAt: (item["modifiedTime"] as? String) ?? "",
                        sizeBytes: size,
                        properties: item["appProperties"] as? [String: String] ?? [:]
                    ))
                }
                pageToken = root["nextPageToken"] as? String
            } while pageToken != nil
            return all
        } catch {
            driveLog.error("DriveApi.listAll failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func download(token: String, fileId: String) async throws -> Data {
        do {
            var components = URLComponents(string: "\(apiBase)/files/\(fileId)")!
            components.queryItems = [URLQueryItem(name: "alt", value: "media")]
            var req = URLRequest(url: components.url!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await execute(req)
            return data
        } catch {
            driveLog.error("DriveApi.download(\(fileId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func uploadGzip(
        token: String,
        name: String,
        existingId: String?,
        gzipData: Data,
        properties: [String: String]
    ) async throws -> DriveFileInfo {
        do {
            let boundary = "BitChordBoundary-\(UUID().uuidString)"
            var metadata: [String: Any] = [
                "name": name,
                "mimeType": "application/gzip",
                "appProperties": properties,
            ]
            if existingId == nil {
                metadata["parents"] = ["appDataFolder"]
            }
            let metaData = try JSONSerialization.data(withJSONObject: metadata)

            var body = Data()
            body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
            body.append(metaData)
            body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/gzip\r\n\r\n".utf8))
            body.append(gzipData)
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))

            let endpoint = existingId.map { "\(uploadBase)/files/\($0)" } ?? "\(uploadBase)/files"
            var components = URLComponents(string: endpoint)!
            components.queryItems = [
                URLQueryItem(name: "uploadType", value: "multipart"),
                URLQueryItem(name: "fields", value: fields),
            ]
            var req = URLRequest(url: components.url!)
            req.httpMethod = existingId == nil ? "POST" : "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            req.httpBody = body

            let (data, _) = try await execute(req)
            let item = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return DriveFileInfo(
                id: (item["id"] as? String) ?? existingId ?? "",
                name: (item["name"] as? String) ?? name,
                md5: item["md5Checksum"] as? String,
                modifiedAt: (item["modifiedTime"] as? String) ?? "",
                sizeBytes: Int64(gzipData.count),
                properties: item["appProperties"] as? [String: String] ?? properties
            )
        } catch {
            driveLog.error("DriveApi.uploadGzip(\(name, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func delete(token: String, fileId: String) async throws {
        do {
            var req = URLRequest(url: URL(string: "\(apiBase)/files/\(fileId)")!)
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try await execute(req)
        } catch {
            driveLog.error("DriveApi.delete(\(fileId, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func execute(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            if http.statusCode == 401 {
                throw NSError(
                    domain: "DriveApi",
                    code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Google Drive authorization expired"]
                )
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Drive error \(http.statusCode)"
                throw NSError(
                    domain: "DriveApi",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: msg]
                )
            }
            return (data, http)
        } catch {
            driveLog.error("DriveApi HTTP request failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

// MARK: - Sync Models & Compatibility Decoder

enum BackupFrequency: String, CaseIterable, Identifiable {
    case off = "OFF"
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var intervalSeconds: TimeInterval {
        switch self {
        case .off: return 0
        case .daily: return 86_400
        case .weekly: return 7 * 86_400
        case .monthly: return 30 * 86_400
        }
    }
}

struct DeviceManifest: Codable {
    var schema: Int = 1
    var deviceId: String
    var name: String
    var ownerInstall: String
    var updatedAt: Int64
    var versionName: String
    var months: [String: String]
}

struct RemoteDriveDevice: Identifiable {
    let deviceId: String
    let name: String
    let updatedAt: Date
    let monthCount: Int
    let sizeBytes: Int64
    let manifestFileId: String
    let manifest: DeviceManifest
    var id: String { deviceId }
}

/// Decodes monthly buckets written by both integer-ms clients (Android / BitChordKit) and float-ms iOS builds.
private enum DriveBucketDecoder {
    private struct FloatTrack: Codable {
        var id: String
        var title: String?
        var artist: String?
        var album: String?
        var albumId: String?
        var artistId: String?
        var art: String?
        var ms: Double?
        var plays: Int?
        var last: Double?
    }

    private struct FloatNameEntry: Codable {
        var name: String?
        var sub: String?
        var art: String?
        var id: String?
        var ms: Double?
        var plays: Int?
        var key: String?
    }

    private struct FloatBucket: Codable {
        var version: Int?
        var month: String
        var tracks: [FloatTrack]?
        var artists: [FloatNameEntry]?
        var albums: [FloatNameEntry]?
        var hours: [Double]?
        var days: [Int: Double]?
    }

    static func decode(_ data: Data, using decoder: JSONDecoder) throws -> ReplayStoredBucket {
        if let exact = try? decoder.decode(ReplayStoredBucket.self, from: data) {
            return exact
        }
        let fallback = try decoder.decode(FloatBucket.self, from: data)
        return ReplayStoredBucket(
            version: fallback.version ?? 1,
            month: fallback.month,
            tracks: (fallback.tracks ?? []).map {
                ReplayTrackEntry(
                    id: $0.id,
                    title: $0.title ?? "",
                    artist: $0.artist ?? "",
                    album: $0.album,
                    albumId: $0.albumId,
                    artistId: $0.artistId,
                    art: $0.art,
                    ms: Int64(($0.ms ?? 0).rounded()),
                    plays: $0.plays ?? 0,
                    last: Int64(($0.last ?? 0).rounded())
                )
            },
            artists: (fallback.artists ?? []).map {
                ReplayNameEntry(
                    name: $0.name ?? "",
                    sub: $0.sub,
                    art: $0.art,
                    id: $0.id,
                    ms: Int64(($0.ms ?? 0).rounded()),
                    plays: $0.plays ?? 0,
                    key: $0.key
                )
            },
            albums: (fallback.albums ?? []).map {
                ReplayNameEntry(
                    name: $0.name ?? "",
                    sub: $0.sub,
                    art: $0.art,
                    id: $0.id,
                    ms: Int64(($0.ms ?? 0).rounded()),
                    plays: $0.plays ?? 0,
                    key: $0.key
                )
            },
            hours: (0..<24).map { idx in
                let hours = fallback.hours ?? []
                return idx < hours.count ? Int64(hours[idx].rounded()) : 0
            },
            days: (fallback.days ?? [:]).mapValues { Int64($0.rounded()) }
        )
    }
}

// MARK: - Backup Manager

/// Coordinates Google Drive OAuth, automatic scheduled sync, peer bucket merging, and restore.
@Observable
@MainActor
final class DriveBackupManager {
    static let shared = DriveBackupManager()

    var accountEmail: String?
    var accountName: String?
    var frequency: BackupFrequency = .daily
    var overCellular: Bool = false
    var lastSyncAt: Date?
    var lastError: String?
    var deviceId: String?
    var deviceName: String = ""
    var installId: String = ""
    var isSyncing: Bool = false
    var statusText: String?
    var devices: [RemoteDriveDevice] = []

    private let authSession = DriveAuthSession()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let email = "drive_backup_email"
        static let name = "drive_backup_name"
        static let frequency = "drive_backup_frequency"
        static let cellular = "drive_backup_cellular"
        static let lastSync = "drive_backup_last_sync"
        static let deviceId = "drive_backup_device_id"
        static let deviceName = "drive_backup_device_name"
        static let installId = "drive_backup_install_id"
    }

    private init() {
        accountEmail = defaults.string(forKey: Keys.email)
        accountName = defaults.string(forKey: Keys.name)
        if let rawFreq = defaults.string(forKey: Keys.frequency), let parsed = BackupFrequency(rawValue: rawFreq) {
            frequency = parsed
        }
        overCellular = defaults.bool(forKey: Keys.cellular)
        let ts = defaults.double(forKey: Keys.lastSync)
        lastSyncAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        deviceId = defaults.string(forKey: Keys.deviceId)
        deviceName = defaults.string(forKey: Keys.deviceName) ?? Self.defaultDeviceName()
        if let existingInstall = defaults.string(forKey: Keys.installId), !existingInstall.isEmpty {
            installId = existingInstall
        } else {
            let created = UUID().uuidString
            installId = created
            defaults.set(created, forKey: Keys.installId)
        }
    }

    var isConnected: Bool { accountEmail != nil }

    func setFrequency(_ freq: BackupFrequency) {
        frequency = freq
        defaults.set(freq.rawValue, forKey: Keys.frequency)
    }

    func setOverCellular(_ enabled: Bool) {
        overCellular = enabled
        defaults.set(enabled, forKey: Keys.cellular)
    }

    func setDeviceName(_ name: String) {
        deviceName = name
        defaults.set(name, forKey: Keys.deviceName)
    }

    func connect(stats: ReplayListeningStats) async {
        lastError = nil
        statusText = "Connecting to Google Drive…"
        do {
            let token = try await authSession.signIn()
            let profile = try await DriveApi.profile(token: token)
            accountEmail = profile.email ?? "Connected"
            accountName = profile.name
            defaults.set(accountEmail, forKey: Keys.email)
            defaults.set(accountName, forKey: Keys.name)
            if deviceId == nil {
                let newId = UUID().uuidString
                deviceId = newId
                defaults.set(newId, forKey: Keys.deviceId)
                defaults.set(deviceName, forKey: Keys.deviceName)
            }
            try await performSync(token: token, push: true, stats: stats)
        } catch {
            driveLog.error("Google Drive connect failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        statusText = nil
    }

    func disconnect(stats: ReplayListeningStats) async {
        do {
            await authSession.revokeAndClear()
            stats.replacePeerMonths([:])
            accountEmail = nil
            accountName = nil
            devices = []
            lastError = nil
            statusText = nil
            defaults.removeObject(forKey: Keys.email)
            defaults.removeObject(forKey: Keys.name)
        }
    }

    func syncNow(stats: ReplayListeningStats) async {
        guard !isSyncing else { return }
        lastError = nil
        do {
            let token = try await authSession.validAccessToken()
            try await performSync(token: token, push: true, stats: stats)
        } catch {
            driveLog.error("Google Drive sync failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
        statusText = nil
    }

    func syncIfDueOnLaunch(stats: ReplayListeningStats, isMetered: Bool) {
        guard isConnected, frequency != .off, !isSyncing else { return }
        if !overCellular && isMetered { return }
        if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < frequency.intervalSeconds {
            return
        }
        Task {
            await syncNow(stats: stats)
        }
    }

    func restore(device: RemoteDriveDevice, stats: ReplayListeningStats) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        statusText = "Restoring \(device.name)…"
        defer {
            isSyncing = false
            statusText = nil
        }
        do {
            let token = try await authSession.validAccessToken()
            let files = try await DriveApi.listAll(token: token)
            let monthFiles = files.filter {
                $0.properties["kind"] == "replay" && $0.properties["deviceId"] == device.deviceId
            }
            let decoder = JSONDecoder()
            var restoredMonths: [ReplayStoredBucket] = []
            for file in monthFiles {
                let gz = try await DriveApi.download(token: token, fileId: file.id)
                let raw = try GzipCodec.decompress(gz)
                let bucket = try DriveBucketDecoder.decode(raw, using: decoder)
                restoredMonths.append(bucket)
            }
            try stats.importAll(restoredMonths)
            deviceId = device.deviceId
            deviceName = device.name.isEmpty ? Self.defaultDeviceName() : device.name
            defaults.set(deviceId, forKey: Keys.deviceId)
            defaults.set(deviceName, forKey: Keys.deviceName)
            try await performSync(token: token, push: false, stats: stats)
        } catch {
            driveLog.error("Failed to restore device \(device.deviceId, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func deleteRemoteDevice(_ device: RemoteDriveDevice) async {
        lastError = nil
        statusText = "Removing \(device.name)…"
        defer { statusText = nil }
        do {
            let token = try await authSession.validAccessToken()
            let files = try await DriveApi.listAll(token: token)
            let toDelete = files.filter { $0.properties["deviceId"] == device.deviceId }
            for file in toDelete {
                try await DriveApi.delete(token: token, fileId: file.id)
            }
            if device.deviceId == deviceId {
                let newId = UUID().uuidString
                deviceId = newId
                defaults.set(newId, forKey: Keys.deviceId)
            }
            devices.removeAll { $0.deviceId == device.deviceId }
        } catch {
            driveLog.error("Failed to delete remote device: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    private func performSync(token: String, push: Bool, stats: ReplayListeningStats) async throws {
        isSyncing = true
        defer { isSyncing = false }

        do {
            statusText = "Checking Drive…"
            let myId = deviceId ?? UUID().uuidString
            if deviceId == nil {
                deviceId = myId
                defaults.set(myId, forKey: Keys.deviceId)
            }

            let files = try await DriveApi.listAll(token: token)
            let manifestFiles = files.filter { $0.properties["kind"] == "device" }
            let replayFiles = files.filter { $0.properties["kind"] == "replay" }
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            if push {
                let localMonths = stats.exportAll()
                var monthHashes: [String: String] = [:]
                let myRemoteMonths = Dictionary(
                    uniqueKeysWithValues: replayFiles
                        .filter { $0.properties["deviceId"] == myId }
                        .compactMap { f in f.properties["month"].map { ($0, f) } }
                )
                for (idx, bucket) in localMonths.enumerated() {
                    statusText = "Uploading \(idx + 1)/\(max(1, localMonths.count))…"
                    let raw = try encoder.encode(bucket)
                    let sha = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
                    monthHashes[bucket.month] = sha
                    let gz = try GzipCodec.compress(raw)
                    let fileName = "replay-\(myId)-\(bucket.month).json.gz"
                    _ = try await DriveApi.uploadGzip(
                        token: token,
                        name: fileName,
                        existingId: myRemoteMonths[bucket.month]?.id,
                        gzipData: gz,
                        properties: [
                            "kind": "replay",
                            "deviceId": myId,
                            "month": bucket.month,
                        ]
                    )
                }
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let manifest = DeviceManifest(
                    schema: 1,
                    deviceId: myId,
                    name: deviceName.isEmpty ? Self.defaultDeviceName() : deviceName,
                    ownerInstall: installId,
                    updatedAt: Int64(Date().timeIntervalSince1970 * 1000),
                    versionName: version,
                    months: monthHashes
                )
                let manifestRaw = try encoder.encode(manifest)
                let manifestGz = try GzipCodec.compress(manifestRaw)
                let existingManifest = manifestFiles.first { $0.properties["deviceId"] == myId }
                _ = try await DriveApi.uploadGzip(
                    token: token,
                    name: "device-\(myId).json.gz",
                    existingId: existingManifest?.id,
                    gzipData: manifestGz,
                    properties: [
                        "kind": "device",
                        "deviceId": myId,
                    ]
                )
            }

            statusText = "Downloading other devices…"
            let refreshedFiles = try await DriveApi.listAll(token: token)
            let refreshedManifests = refreshedFiles.filter { $0.properties["kind"] == "device" }
            let refreshedReplay = refreshedFiles.filter { $0.properties["kind"] == "replay" }

            var remoteDevices: [RemoteDriveDevice] = []
            var peerBuckets: [String: [ReplayStoredBucket]] = [:]

            for mf in refreshedManifests {
                guard let devId = mf.properties["deviceId"] else { continue }
                do {
                    let gz = try await DriveApi.download(token: token, fileId: mf.id)
                    let raw = try GzipCodec.decompress(gz)
                    let manifest = try decoder.decode(DeviceManifest.self, from: raw)
                    let devReplayFiles = refreshedReplay.filter { $0.properties["deviceId"] == devId }
                    let totalBytes = devReplayFiles.reduce(mf.sizeBytes) { $0 + $1.sizeBytes }
                    remoteDevices.append(RemoteDriveDevice(
                        deviceId: devId,
                        name: manifest.name.isEmpty ? "BitChord Device" : manifest.name,
                        updatedAt: Date(timeIntervalSince1970: TimeInterval(manifest.updatedAt) / 1000.0),
                        monthCount: manifest.months.count,
                        sizeBytes: totalBytes,
                        manifestFileId: mf.id,
                        manifest: manifest
                    ))

                    if devId != myId {
                        var months: [ReplayStoredBucket] = []
                        for rf in devReplayFiles {
                            let rgz = try await DriveApi.download(token: token, fileId: rf.id)
                            let rraw = try GzipCodec.decompress(rgz)
                            if let bucket = try? DriveBucketDecoder.decode(rraw, using: decoder) {
                                months.append(bucket)
                            }
                        }
                        peerBuckets[devId] = months
                    }
                } catch {
                    driveLog.error("Failed reading manifest for device \(devId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            stats.replacePeerMonths(peerBuckets)
            devices = remoteDevices.sorted { $0.updatedAt > $1.updatedAt }
            lastSyncAt = Date()
            defaults.set(lastSyncAt?.timeIntervalSince1970 ?? 0, forKey: Keys.lastSync)
        } catch {
            driveLog.error("Drive sync pipeline error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func defaultDeviceName() -> String {
        UIDevice.current.name
    }
}
