import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?

    func start() {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = recordingURL()

        try? FileManager.default.removeItem(at: url)
        file = try? AVAudioFile(forWriting: url, settings: format.settings)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.file?.write(from: buffer)
        }

        try? engine.start()
    }

    func stop() async -> URL {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
        return recordingURL()
    }

    private func recordingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tell_recording.wav")
    }
}
