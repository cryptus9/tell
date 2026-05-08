import AppKit
import AVFoundation
import SwiftUI

@main
struct tellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup(id: "settings") {
            SettingsView(settings: appDelegate.settings)
        }

        MenuBarExtra("tell", systemImage: "mic") {
            MenuBarView(
                settings: appDelegate.settings,
                transcription: appDelegate.transcription
            )
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let transcription = TranscriptionService()
    private let hotkeyManager = HotkeyManager()
    private let recorder = AudioRecorder()
    private let pasteService = PasteService()
    private let overlay = RecordingOverlayPanel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        setupHotkey()
        preloadModel()
        observeHotkeySettings()
        observeModelSource()
        Task { @MainActor in checkAccessibility() }
    }

    private func setupHotkey() {
        hotkeyManager.onKeyDown = { [weak self] in
            guard let self else { return }
            overlay.show()
            recorder.start()
        }
        hotkeyManager.onKeyUp = { [weak self] in
            guard let self else { return }
            Task {
                let url = await self.recorder.stop()
                self.overlay.showProcessing()
                do {
                    let text = try await self.transcription.transcribe(url: url)
                    self.pasteService.paste(text: text)
                } catch {}
                self.overlay.hide()
            }
        }
        hotkeyManager.start(
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        )
    }

    private func observeHotkeySettings() {
        withObservationTracking {
            _ = settings.hotkeyKeyCode
            _ = settings.hotkeyModifiers
        } onChange: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.hotkeyManager.start(
                    keyCode: self.settings.hotkeyKeyCode,
                    modifiers: self.settings.hotkeyModifiers
                )
                self.observeHotkeySettings()
            }
        }
    }

    private func observeModelSource() {
        withObservationTracking {
            _ = settings.modelSource
        } onChange: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.preloadModel()
                self.observeModelSource()
            }
        }
    }

    private func preloadModel() {
        let src = settings.modelSource
        let source: ModelSource
        if src.hasPrefix("hf:") {
            source = .huggingFace(String(src.dropFirst(3)))
        } else if src.hasPrefix("local:") {
            source = .localFile(URL(fileURLWithPath: String(src.dropFirst(6))))
        } else if src.hasPrefix("server:"), let url = URL(string: String(src.dropFirst(7))) {
            source = .localServer(url)
        } else {
            source = .huggingFace(src)
        }
        Task { await transcription.preload(source: source) }
    }

    private func checkAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let alert = NSAlert()
        alert.messageText = "Accessibility Access Required"
        alert.informativeText = "tell needs Accessibility access to detect the hotkey and paste text. Grant access in System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
