import Foundation
import Observation
import WhisperKit

enum TranscriptionState {
    case idle, loading, ready, transcribing
    case error(String)
}

@Observable
@MainActor
final class TranscriptionService {
    var state: TranscriptionState = .idle

    private var kit: WhisperKit?

    func preload(source: ModelSource) async {
        state = .loading
        do {
            switch source {
            case .huggingFace(let repoID):
                kit = try await WhisperKit(model: repoID)
            case .localFile(let url):
                kit = try await WhisperKit(modelFolder: url.path)
            }
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func transcribe(url: URL) async throws -> String {
        guard let kit else { throw TranscriptionError.notReady }
        state = .transcribing
        defer { state = .ready }
        let options = DecodingOptions(task: .transcribe)
        let results = try await kit.transcribe(audioPath: url.path, decodeOptions: options)
        let raw = results.map(\.text).joined(separator: " ")
        let text = raw
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[NOISE]", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw TranscriptionError.noSpeech }
        return text
    }
}

enum TranscriptionError: LocalizedError {
    case notReady
    case noSpeech
    var errorDescription: String? {
        switch self {
        case .notReady: return "Model not loaded"
        case .noSpeech: return nil
        }
    }
}
