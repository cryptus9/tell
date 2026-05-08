import SwiftUI

struct MenuBarView: View {
    var settings: AppSettings
    var transcription: TranscriptionService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                Text(modelLabel)
                    .font(.headline)
            }

            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Settings…") { openWindow(id: "settings") }
                .buttonStyle(.plain)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 220)
    }

    private var modelLabel: String {
        let src = settings.modelSource
        if src.hasPrefix("hf:") { return String(src.dropFirst(3)) }
        if src.hasPrefix("local:") { return "Local model" }
        return src
    }

    private var stateLabel: String {
        switch transcription.state {
        case .idle:         return "Idle"
        case .loading:      return "Loading model…"
        case .ready:        return "Ready"
        case .transcribing: return "Transcribing…"
        case .error(let m): return "Error: \(m)"
        }
    }

    private var stateColor: Color {
        switch transcription.state {
        case .ready:        return .green
        case .transcribing: return .orange
        case .error:        return .red
        default:            return .secondary
        }
    }
}
