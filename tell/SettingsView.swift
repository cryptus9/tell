import AppKit
import AVFoundation
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case model = "Model"
    case configuration = "Configuration"
    case permissions = "Permissions"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .model: return "cpu"
        case .configuration: return "keyboard"
        case .permissions: return "lock.shield"
        }
    }
}

// Reference type so closures can reliably remove the monitor.
private final class HotkeyRecorder {
    var keyDownMonitor: Any?
    var flagsMonitor: Any?

    func stop() {
        keyDownMonitor.map(NSEvent.removeMonitor); keyDownMonitor = nil
        flagsMonitor.map(NSEvent.removeMonitor);   flagsMonitor = nil
    }
}

struct SettingsView: View {
    var settings: AppSettings
    @State private var selection: SettingsTab = .model

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(160)
        } detail: {
            switch selection {
            case .model:        ModelSettingsView(settings: settings)
            case .configuration: ConfigurationSettingsView(settings: settings)
            case .permissions:  PermissionsSettingsView()
            }
        }
        .frame(width: 580, height: 400)
    }
}

// MARK: - Model

private struct ModelSettingsView: View {
    var settings: AppSettings
    @State private var modelManager = ModelManager()
    @State private var customRepoID = ""

    var body: some View {
        Form {
            Section {
                ForEach(ModelManager.curatedModels, id: \.self) { repoID in
                    curatedModelRow(repoID: repoID)
                }
            }

            Section {
                HStack {
                    TextField("Custom HF repo (e.g. distil-whisper/distil-large-v3)", text: $customRepoID)
                    Button("Download") {
                        let repo = customRepoID
                        settings.modelSource = "hf:\(repo)"
                        Task { try? await modelManager.download(repoID: repo) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(customRepoID.isEmpty || modelManager.isDownloading)
                }

                Button("Load from file…") {
                    if let url = modelManager.openLocalFile() {
                        settings.modelSource = "local:\(url.path)"
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { modelManager.refreshDownloaded() }
    }

    private static let modelSizes: [String: String] = [
        "tiny": "~75 MB", "base": "~145 MB", "small": "~490 MB",
        "medium": "~1.5 GB", "large": "~3 GB",
    ]

    private func modelHint(for repoID: String) -> String {
        let lang = repoID.hasSuffix(".en") ? "English only" : "Multilingual"
        let variant = repoID.components(separatedBy: "_whisper-").last?
            .replacingOccurrences(of: ".en", with: "")
            .components(separatedBy: "-").first ?? ""
        let size = Self.modelSizes[variant].map { " · \($0)" } ?? ""
        return lang + size
    }

    private func curatedModelRow(repoID: String) -> some View {
        let shortName = repoID.components(separatedBy: "_whisper-").last ?? repoID
        let isActive = activeModel == repoID
        let isDownloaded = modelManager.downloadedModels.contains { $0 == repoID }
        let progress = modelManager.downloadProgress[repoID]

        return HStack {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .onTapGesture { settings.modelSource = "hf:\(repoID)" }

            VStack(alignment: .leading, spacing: 2) {
                Text(shortName.capitalized)
                Text(modelHint(for: repoID))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            if let p = progress {
                ProgressView(value: p)
                    .frame(width: 80)
                    .progressViewStyle(.linear)
            } else if isDownloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Download") {
                    Task { try? await modelManager.download(repoID: repoID) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(modelManager.isDownloading)
            }
        }
    }

    private var activeModel: String {
        let src = settings.modelSource
        if src.hasPrefix("hf:") { return String(src.dropFirst(3)) }
        return ""
    }
}

// MARK: - Configuration

private struct ConfigurationSettingsView: View {
    var settings: AppSettings
    @State private var isRecordingHotkey = false
    @State private var recorder = HotkeyRecorder()

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Push-to-talk")
                    Spacer()
                    Button(isRecordingHotkey ? "Press any key… (Esc to cancel)" : hotkeyLabel) {
                        if isRecordingHotkey { stopRecordingHotkey() }
                        else { startRecordingHotkey() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeyLabel: String {
        keyLabel(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        let rec = recorder

        rec.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 {
                stopRecordingHotkey()
                return nil
            }
            settings.hotkeyKeyCode = Int(event.keyCode)
            settings.hotkeyModifiers = Int(event.modifierFlags
                .intersection([.command, .option, .control, .shift])
                .rawValue)
            stopRecordingHotkey()
            return nil
        }

        var lastFlags = NSEvent.ModifierFlags()
        rec.flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let current = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if !lastFlags.isEmpty && current.isEmpty {
                settings.hotkeyKeyCode = Int(event.keyCode)
                settings.hotkeyModifiers = 0
                stopRecordingHotkey()
            }
            lastFlags = current
            return event
        }
    }

    private func stopRecordingHotkey() {
        isRecordingHotkey = false
        recorder.stop()
    }

    private func keyLabel(keyCode: Int, modifiers: Int) -> String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    private func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "Esc",
            54: "⌘R", 55: "⌘L", 56: "⇧L", 60: "⇧R",
            58: "⌥L", 61: "⌥R", 59: "⌃L", 62: "⌃R",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        if let name = map[keyCode] { return name }
        if let str = keyCodeToString(keyCode) { return str.uppercased() }
        return "Key \(keyCode)"
    }

    private func keyCodeToString(_ keyCode: Int) -> String? {
        let src = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true) else { return nil }
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil }
        return String(decoding: chars.prefix(length), as: UTF16.self)
    }
}

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    var body: some View {
        Form {
            Section("Permissions") {
                permissionRow(
                    label: "Accessibility",
                    granted: AXIsProcessTrusted(),
                    pane: "Accessibility"
                )
                permissionRow(
                    label: "Microphone",
                    granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                    pane: "Microphone"
                )
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(label: String, granted: Bool, pane: String) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
            Text(label)
            Spacer()
            if !granted {
                Button("Open Settings") { openPrivacyPane(pane) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private func openPrivacyPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
