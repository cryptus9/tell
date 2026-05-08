import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import WhisperKit

enum ModelSource {
    case huggingFace(String)
    case localFile(URL)
    case localServer(URL)
}

enum ModelSizeCategory: String, CaseIterable {
    case small = "Small"      // < 500 MB
    case medium = "Medium"    // 500 MB – 2 GB
    case large = "Large"      // > 2 GB
}

enum ModelSpeed: String, CaseIterable {
    case fast = "Fast"
    case balanced = "Balanced"
    case accurate = "Accurate"
}

struct WhisperModelInfo: Identifiable {
    let repoID: String
    let displayName: String
    let size: String
    let sizeCategory: ModelSizeCategory
    let speed: ModelSpeed
    let accuracyScore: Int  // 1–3
    let multilingual: Bool
    var id: String { repoID }

    var speedScore: Int {
        switch speed {
        case .fast: return 3
        case .balanced: return 2
        case .accurate: return 1
        }
    }

    var hint: String { (multilingual ? "Multilingual" : "English only") + " · \(size)" }
}

@Observable
@MainActor
final class ModelManager {
    static let openAIModels: [WhisperModelInfo] = [
        .init(repoID: "openai_whisper-tiny",            displayName: "Tiny",           size: "~75 MB",  sizeCategory: .small,  speed: .fast,     accuracyScore: 1, multilingual: true),
        .init(repoID: "openai_whisper-tiny.en",         displayName: "Tiny",           size: "~75 MB",  sizeCategory: .small,  speed: .fast,     accuracyScore: 1, multilingual: false),
        .init(repoID: "openai_whisper-base",            displayName: "Base",           size: "~145 MB", sizeCategory: .small,  speed: .fast,     accuracyScore: 1, multilingual: true),
        .init(repoID: "openai_whisper-base.en",         displayName: "Base",           size: "~145 MB", sizeCategory: .small,  speed: .fast,     accuracyScore: 1, multilingual: false),
        .init(repoID: "openai_whisper-small",           displayName: "Small",          size: "~490 MB", sizeCategory: .small,  speed: .balanced, accuracyScore: 2, multilingual: true),
        .init(repoID: "openai_whisper-small.en",        displayName: "Small",          size: "~490 MB", sizeCategory: .small,  speed: .balanced, accuracyScore: 2, multilingual: false),
        .init(repoID: "openai_whisper-medium",          displayName: "Medium",         size: "~1.5 GB", sizeCategory: .medium, speed: .balanced, accuracyScore: 2, multilingual: true),
        .init(repoID: "openai_whisper-medium.en",       displayName: "Medium",         size: "~1.5 GB", sizeCategory: .medium, speed: .balanced, accuracyScore: 2, multilingual: false),
        .init(repoID: "openai_whisper-large-v2",        displayName: "Large v2",       size: "~3 GB",   sizeCategory: .large,  speed: .accurate, accuracyScore: 3, multilingual: true),
        .init(repoID: "openai_whisper-large-v3",        displayName: "Large v3",       size: "~3 GB",   sizeCategory: .large,  speed: .accurate, accuracyScore: 3, multilingual: true),
        .init(repoID: "openai_whisper-large-v3-turbo",  displayName: "Large v3 Turbo", size: "~1.6 GB", sizeCategory: .medium, speed: .balanced, accuracyScore: 2, multilingual: true),
    ]

    static let distilModels: [WhisperModelInfo] = [
        .init(repoID: "distil-whisper_distil-small.en",  displayName: "Distil Small",    size: "~330 MB", sizeCategory: .small,  speed: .fast,     accuracyScore: 1, multilingual: false),
        .init(repoID: "distil-whisper_distil-medium.en", displayName: "Distil Medium",   size: "~750 MB", sizeCategory: .medium, speed: .fast,     accuracyScore: 2, multilingual: false),
        .init(repoID: "distil-whisper_distil-large-v2",  displayName: "Distil Large v2", size: "~1.5 GB", sizeCategory: .medium, speed: .balanced, accuracyScore: 2, multilingual: true),
        .init(repoID: "distil-whisper_distil-large-v3",  displayName: "Distil Large v3", size: "~1.5 GB", sizeCategory: .medium, speed: .balanced, accuracyScore: 3, multilingual: true),
    ]

    static var curatedModels: [String] { (openAIModels + distilModels).map(\.repoID) }

    private static let defaultsKey = "downloadedWhisperKitModels"

    var downloadedModels: [String] = []
    var availableModelIDs: Set<String> = Set(curatedModels)
    var isDownloading = false
    var downloadProgress: [String: Double] = [:]

    func refreshAvailable() async {
        if let ids = try? await WhisperKit.fetchAvailableModels() {
            availableModelIDs = Set(ids)
        }
    }

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

    func delete(repoID: String) {
        let candidates = [
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/huggingface/hub/models--argmaxinc--whisperkit-coreml/snapshots"),
        ].compactMap { $0 }

        for snapshots in candidates {
            guard let hashes = try? FileManager.default.contentsOfDirectory(atPath: snapshots.path) else { continue }
            for hash in hashes {
                let target = snapshots.appendingPathComponent(hash).appendingPathComponent(repoID)
                if FileManager.default.fileExists(atPath: target.path) {
                    try? FileManager.default.removeItem(at: target)
                }
            }
        }

        var list = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
        list.removeAll { $0 == repoID }
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
