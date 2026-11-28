// Google Drive backup, sync schedule, and cross-device Replay management settings screen.
import BitChordCore
import SwiftUI

/// Opened from Settings → Your data → Google Drive Backup.
/// Manages Google Drive OAuth, automatic backup cadence, synced devices, and device restore.
struct DriveBackupScreen: View {
    @Environment(AppModel.self) private var app
    @State private var manager = DriveBackupManager.shared
    @State private var clientIdInput: String = DriveAuthSession.customClientId()
    @State private var showClientIdEditor: Bool = false
    @State private var deviceToRestore: RemoteDriveDevice?
    @State private var deviceToDelete: RemoteDriveDevice?

    var body: some View {
        List {
            SettingsGroup(header: "Google Drive", topSpacing: 8) {
                if manager.isConnected {
                    LabeledContent("Google Account", value: manager.accountEmail ?? "")
                    if let lastSyncAt = manager.lastSyncAt {
                        LabeledContent("Last Synced", value: lastSyncAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let status = manager.statusText {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(status)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        Task { await manager.syncNow(stats: app.replayStats) }
                    } label: {
                        Label("Back Up & Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(manager.isSyncing)

                    Button("Disconnect Google Drive", role: .destructive) {
                        Task { await manager.disconnect(stats: app.replayStats) }
                    }
                    .disabled(manager.isSyncing)
                } else {
                    Text("Back up your listening stats to your hidden Google Drive app folder and merge Replay across Android & iOS.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let status = manager.statusText {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(status)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        Task { await manager.connect(stats: app.replayStats) }
                    } label: {
                        Label("Connect Google Drive", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(manager.isSyncing)

                    Button("Configure OAuth Client ID") {
                        clientIdInput = DriveAuthSession.customClientId()
                        showClientIdEditor = true
                    }
                    .font(.footnote)
                }

                if let err = manager.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if manager.isConnected {
                SettingsGroup(header: "Schedule & Device") {
                    Picker("Automatic Sync", selection: Binding(
                        get: { manager.frequency },
                        set: { manager.setFrequency($0) }
                    )) {
                        ForEach(BackupFrequency.allCases) { freq in
                            Text(freq.label).tag(freq)
                        }
                    }
                    Toggle("Sync Over Cellular", isOn: Binding(
                        get: { manager.overCellular },
                        set: { manager.setOverCellular($0) }
                    ))
                    .tint(Color.accentColor)
                    TextField("This Device Name", text: Binding(
                        get: { manager.deviceName },
                        set: { manager.setDeviceName($0) }
                    ))
                }

                SettingsGroup(
                    header: "Synced Devices (\(manager.devices.count))",
                    footer: "Listening history from all synced Android and iOS devices is merged automatically into Replay without double-counting."
                ) {
                    if manager.devices.isEmpty {
                        Text("No synced devices yet. Tap Back Up & Sync Now to upload this device.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.devices) { device in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(device.name)
                                        .font(.headline)
                                    if device.deviceId == manager.deviceId {
                                        Text("This Device")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                                    }
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: device.sizeBytes, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(device.monthCount) months · Updated \(device.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if device.deviceId != manager.deviceId {
                                    HStack(spacing: 16) {
                                        Button("Restore as This Device") {
                                            deviceToRestore = device
                                        }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.borderless)
                                        Button("Remove", role: .destructive) {
                                            deviceToDelete = device
                                        }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .settingsGroupList()
        .collectionsListBottomInset()
        .navigationTitle("Google Drive Backup")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showClientIdEditor) {
            NavigationStack {
                Form {
                    Section {
                        TextField("iOS OAuth Client ID (.apps.googleusercontent.com)", text: $clientIdInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("OAuth Client ID")
                    } footer: {
                        Text("Optional override if GOOGLE_DRIVE_CLIENT_ID is not bundled at build time.")
                    }
                }
                .navigationTitle("Google Drive OAuth")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showClientIdEditor = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            DriveAuthSession.setCustomClientId(clientIdInput)
                            showClientIdEditor = false
                        }
                    }
                }
            }
        }
        .alert("Restore Device?", isPresented: Binding(
            get: { deviceToRestore != nil },
            set: { if !$0 { deviceToRestore = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToRestore = nil }
            Button("Restore") {
                if let dev = deviceToRestore {
                    Task { await manager.restore(device: dev, stats: app.replayStats) }
                }
                deviceToRestore = nil
            }
        } message: {
            Text("This replaces local Replay history with \(deviceToRestore?.name ?? "this device")'s backup and adopts its device partition.")
        }
        .alert("Remove Device Backup?", isPresented: Binding(
            get: { deviceToDelete != nil },
            set: { if !$0 { deviceToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { deviceToDelete = nil }
            Button("Remove", role: .destructive) {
                if let dev = deviceToDelete {
                    Task { await manager.deleteRemoteDevice(dev) }
                }
                deviceToDelete = nil
            }
        } message: {
            Text("This permanently deletes \(deviceToDelete?.name ?? "the device")'s backup files from your Google Drive.")
        }
    }
}
