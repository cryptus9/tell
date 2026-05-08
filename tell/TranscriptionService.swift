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
    private var serverURL: URL?

    func preload(source: ModelSource) async {
        state = .loading
        kit = nil
        serverURL = nil
        do {
            switch source {
            case .huggingFace(let repoID):
                kit = try await WhisperKit(model: repoID)
                state = .ready
            case .localFile(let url):
                kit = try await WhisperKit(modelFolder: url.path)
                state = .ready
            case .localServer(let url):
                serverURL = url
                state = .ready
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func transcribe(url: URL) async throws -> String {
        state = .transcribing
        defer { state = .ready }

        if let serverURL {
            return try await transcribeViaServer(audioURL: url, baseURL: serverURL)
        }
        guard let kit else { throw TranscriptionError.notReady }
        return try await transcribeViaWhisperKit(kit: kit, audioURL: url)
    }

    private func transcribeViaWhisperKit(kit: WhisperKit, audioURL: URL) async throws -> String {
        let options = DecodingOptions(task: .transcribe)
        let results = try await kit.transcribe(audioPath: audioURL.path, decodeOptions: options)
        let raw = results.map(\.text).joined(separator: " ")
        let text = raw
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[NOISE]", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw TranscriptionError.noSpeech }
        return text
    }

    private func transcribeViaServer(audioURL: URL, baseURL: URL) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("v1/audio/transcriptions")
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: audioURL)
        var body = Data()
        let crlf = "\r\n"

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)".data(using: .utf8)!)
        body.append("whisper-1\(crlf)".data(using: .utf8)!)

        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(audioData)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.serverError
        }
        struct Response: Decodable { let text: String }
        let text = try JSONDecoder().decode(Response.self, from: data).text
            .trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw TranscriptionError.noSpeech }
        return text
    }
}

enum TranscriptionError: LocalizedError {
    case notReady, noSpeech, serverError
    var errorDescription: String? {
        switch self {
        case .notReady:     return "Model not loaded"
        case .noSpeech:     return nil
        case .serverError:  return "Server transcription failed"
        }
    }
}
