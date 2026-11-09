import AVFoundation
import Foundation

enum VideoTrimmer {
    enum TrimError: LocalizedError {
        case invalidRange
        case sessionUnavailable
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidRange: return "裁剪区间无效。"
            case .sessionUnavailable: return "无法创建视频裁剪任务。"
            case .exportFailed(let message): return message
            }
        }
    }

    static func export(
        source: URL,
        start: TimeInterval,
        end: TimeInterval
    ) async throws -> URL {
        guard end - start >= 0.2 else { throw TrimError.invalidRange }
        let outputURL = try makeOutputURL(source: source)
        defer {
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
        }

        do {
            try await runExport(
                asset: AVURLAsset(url: source),
                preset: AVAssetExportPresetPassthrough,
                start: start,
                end: end,
                outputURL: outputURL
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            try await runExport(
                asset: AVURLAsset(url: source),
                preset: AVAssetExportPresetHighestQuality,
                start: start,
                end: end,
                outputURL: outputURL
            )
        }
        return outputURL
    }

    private static func runExport(
        asset: AVURLAsset,
        preset: String,
        start: TimeInterval,
        end: TimeInterval,
        outputURL: URL
    ) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw TrimError.sessionUnavailable
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        if session.status != .completed {
            throw TrimError.exportFailed(
                session.error?.localizedDescription ?? "视频裁剪失败，请换一个区间重试。"
            )
        }
    }

    private static func makeOutputURL(source: URL) throws -> URL {
        let directory = try ScreenRecorder.outputDirectory()
        let base = source.deletingPathExtension().lastPathComponent
        var url = directory.appendingPathComponent("\(base)_裁剪.mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)_裁剪_\(suffix).mp4")
            suffix += 1
        }
        return url
    }
}
