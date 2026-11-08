import CoreGraphics
import Foundation
import LongShotCore

struct OpenedMedia: Identifiable {
    enum Kind {
        case image(RawImageFile, pixelSize: CGSize)
        case video(URL)
    }

    let id = UUID()
    let url: URL
    let kind: Kind

    var isVideo: Bool {
        if case .video = kind { return true }
        return false
    }

    var title: String {
        isVideo ? "视频" : "图片"
    }

    var detailText: String {
        switch kind {
        case .image(_, let pixelSize):
            return "\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px"
        case .video:
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "\(url.pathExtension.uppercased()) · \(formatter.string(fromByteCount: size))"
        }
    }
}
