import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import WhisperKit

enum ModelSource {
    case huggingFace(String)
    case localFile(URL)
}

@Observable
@MainActor
final class ModelManager {
    static let curatedModels = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-small",
        "openai_whisper-medium",
    ]

    private static let defaultsKey = "downloadedWhisperKitModels"

    var downloadedModels: [String] = []
    var isDownloading = false
    var downloadProgress: [String: Double] = [:]

    func refreshDownloaded() {
        let tracked = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        let onDisk = Self.scanFilesystem()
        let merged = Array(Set(tracked + onDisk))
        if merged != tracked {
            UserDefaults.standard.set(merged, forKey: Self.defaultsKey)
        }
        downloadedModels = merged
    }

    private static func scanFilesystem() -> [String] {
        let candidates = [
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
        ].compactMap { $0 }

        var found = Set<String>()
        for snapshots in candidates {
            guard let hashes = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { continue }
            for hash in hashes {
                let hashPath = snapshots.appendingPathComponent(hash).path
                if let variants = try? FileManager.default.contentsOfDirectory(atPath: hashPath) {
                    found.formUnion(variants.filter { !$0.hasPrefix(".") })
                }
            }
        }
        return Array(found)
    }

    func download(repoID: String) async throws {
        isDownloading = true
        downloadProgress[repoID] = 0.0
        defer {
            isDownloading = false
            downloadProgress.removeValue(forKey: repoID)
        }
        _ = try await WhisperKit.download(
            variant: repoID,
            progressCallback: { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress[repoID] = progress.fractionCompleted
                }
            }
        )
        markDownloaded(repoID)
    }

    private func markDownloaded(_ repoID: String) {
        var list = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        if !list.contains(repoID) { list.append(repoID) }
        UserDefaults.standard.set(list, forKey: Self.defaultsKey)
        downloadedModels = list
    }

    func openLocalFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select CoreML model bundle"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.folder]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
