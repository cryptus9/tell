import AppKit
import AVFoundation
import SwiftUI

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
    @State private var modelManager = ModelManager()
    @State private var isRecordingHotkey = false
    @State private var customRepoID = ""
    @State private var recorder = HotkeyRecorder()

    var body: some View {
        Form {
            hotkeySection
            modelSection
            permissionsSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { modelManager.refreshDownloaded() }
    }

    // MARK: - Hotkey

    private var hotkeySection: some View {
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

    private var hotkeyLabel: String {
        keyLabel(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func startRecordingHotkey() {
        isRecordingHotkey = true
        let rec = recorder

        // Capture regular key + modifiers
        rec.keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == 53 { // Escape — cancel
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

        // Capture modifier-only keys (Right Command, etc.) via flagsChanged
        var lastFlags = NSEvent.ModifierFlags()
        rec.flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let current = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // A modifier was pressed (flags grew)
            if !lastFlags.isEmpty && current.isEmpty {
                // all modifiers released — use the last pressed state
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

    // MARK: - Model

    private var modelSection: some View {
        Section("Whisper Model") {
            ForEach(ModelManager.curatedModels, id: \.self) { repoID in
                curatedModelRow(repoID: repoID)
            }

            Divider()

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

    private func curatedModelRow(repoID: String) -> some View {
        let shortName = repoID.components(separatedBy: "_whisper-").last ?? repoID
        let isActive = activeModel == repoID
        let isDownloaded = modelManager.downloadedModels.contains { $0 == repoID }
        let progress = modelManager.downloadProgress[repoID]

        return HStack {
            Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                .onTapGesture { settings.modelSource = "hf:\(repoID)" }

            Text(shortName.capitalized)
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

    // MARK: - Permissions

    private var permissionsSection: some View {
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
