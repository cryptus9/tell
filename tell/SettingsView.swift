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
        .frame(minWidth: 560, minHeight: 300)
    }
}

// MARK: - Shared

private struct MetricDots: View {
    let label: String
    let score: Int
    let total: Int = 3

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(1...total, id: \.self) { i in
                    Circle()
                        .frame(width: 6, height: 6)
                        .foregroundStyle(i <= score ? Color.accentColor : Color.secondary.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - Model

private struct ModelSettingsView: View {
    var settings: AppSettings
    @State private var modelManager = ModelManager()
    @State private var serverURLText = ""
    @State private var search = ""
    @State private var languageFilter: LanguageFilter = .all
    @State private var sizeFilter: ModelSizeCategory? = nil
    @State private var speedFilter: ModelSpeed? = nil

    enum LanguageFilter: String, CaseIterable {
        case all = "All", multilingual = "Multilingual", english = "English"
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            Form {
                let openAI = filtered(ModelManager.openAIModels)
                let distil  = filtered(ModelManager.distilModels)
                if !openAI.isEmpty {
                    Section("OpenAI Whisper") {
                        ForEach(openAI) { modelRow($0) }
                    }
                }
                if !distil.isEmpty {
                    Section("Distil-Whisper") {
                        ForEach(distil) { modelRow($0) }
                    }
                }
                if openAI.isEmpty && distil.isEmpty {
                    Section { Text("No models match filters").foregroundStyle(.secondary) }
                }
                Section("Local Server") {
                    HStack {
                        TextField("http://localhost:8000", text: $serverURLText)
                        Button("Use") {
                            settings.modelSource = "server:\(serverURLText)"
                        }
                        .buttonStyle(.bordered)
                        .disabled(URL(string: serverURLText) == nil || serverURLText.isEmpty)
                    }
                    Text("OpenAI-compatible /v1/audio/transcriptions endpoint. Works with faster-whisper-server, LocalAI, and others.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { modelManager.refreshDownloaded() }
    }

    private var filterBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search models…", text: $search).textFieldStyle(.plain)
                Divider().frame(height: 16)
                Picker("", selection: $languageFilter) {
                    ForEach(LanguageFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            HStack(spacing: 12) {
                Text("Size").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $sizeFilter) {
                    Text("Any").tag(Optional<ModelSizeCategory>.none)
                    ForEach(ModelSizeCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Divider().frame(height: 16)

                Text("Speed").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $speedFilter) {
                    Text("Any").tag(Optional<ModelSpeed>.none)
                    ForEach(ModelSpeed.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func filtered(_ models: [WhisperModelInfo]) -> [WhisperModelInfo] {
        models.filter { m in
            let matchSearch = search.isEmpty || m.displayName.localizedCaseInsensitiveContains(search)
            let matchLang: Bool = switch languageFilter {
                case .all: true
                case .multilingual: m.multilingual
                case .english: !m.multilingual
            }
            let matchSize = sizeFilter == nil || m.sizeCategory == sizeFilter
            let matchSpeed = speedFilter == nil || m.speed == speedFilter
            return matchSearch && matchLang && matchSize && matchSpeed
        }
    }

    private func modelRow(_ model: WhisperModelInfo) -> some View {
        let isActive = activeModel == model.repoID
        let isDownloaded = modelManager.downloadedModels.contains(model.repoID)
        let progress = modelManager.downloadProgress[model.repoID]

        return HStack {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .onTapGesture { settings.modelSource = "hf:\(model.repoID)" }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                Text(model.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    MetricDots(label: "Speed",    score: model.speedScore)
                    MetricDots(label: "Accuracy", score: model.accuracyScore)
                }
            }
            Spacer()

            if let p = progress {
                ProgressView(value: p).frame(width: 80).progressViewStyle(.linear)
            } else if isDownloaded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Button(role: .destructive) {
                        modelManager.delete(repoID: model.repoID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button("Download") {
                    Task { try? await modelManager.download(repoID: model.repoID) }
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
