import CoreGraphics
import Foundation
import Vision

enum OCRService {
    struct Result {
        let text: String
        let lineCount: Int
    }

    enum OCRError: LocalizedError {
        case noText
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noText: return "没有识别到可复制的文字。"
            case .failed(let message): return message
            }
        }
    }

    static func recognize(cgImage: CGImage) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                throw OCRError.failed("文字识别失败：\(error.localizedDescription)")
            }

            let observations = (request.results ?? []).sorted { left, right in
                let dy = abs(left.boundingBox.midY - right.boundingBox.midY)
                if dy > 0.012 {
                    return left.boundingBox.midY > right.boundingBox.midY
                }
                return left.boundingBox.minX < right.boundingBox.minX
            }

            let lines = observations.compactMap { observation -> String? in
                let text = observation.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (text?.isEmpty == false) ? text : nil
            }

            guard !lines.isEmpty else { throw OCRError.noText }
            return Result(text: lines.joined(separator: "\n"), lineCount: lines.count)
        }.value
    }
}
