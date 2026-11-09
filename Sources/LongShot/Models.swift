import AppKit
import CoreGraphics
import Foundation
import LongShotCore

struct WindowTarget: Identifiable, Hashable {
    let id: CGWindowID
    let processID: pid_t
    let appName: String
    let title: String
    let bundleIdentifier: String?
    let frame: CGRect

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    var subtitle: String {
        "\(appName) · \(Int(frame.width.rounded())) × \(Int(frame.height.rounded()))"
    }
}

enum AppSection {
    case home
    case screenshot
    case record
}

enum ScreenshotSource: String {
    case window
    case region
}

enum ScreenshotMode: CaseIterable, Identifiable {
    case normal
    case long

    var id: Self { self }
    var title: String { self == .normal ? "普通截屏" : "长截屏" }
}

enum RecordSourceChoice: String {
    case window
    case screen
    case region
}

struct RegionTarget {
    /// Rectangle in ScreenCaptureKit's top-left global screen coordinates.
    let rect: CGRect
    let displayID: CGDirectDisplayID
    let displayFrame: CGRect
    let scrollTarget: WindowTarget?

    var widthInPoints: Int { max(1, Int(rect.width.rounded())) }
    var heightInPoints: Int { max(1, Int(rect.height.rounded())) }

    var label: String {
        "框选区域 \(widthInPoints) × \(heightInPoints) pt"
    }
}

enum CaptureSource {
    case window(WindowTarget)
    case region(RegionTarget)

    var hudLabel: String {
        switch self {
        case .window(let target):
            return target.appName
        case .region(let target):
            return target.label
        }
    }

    var hudFrame: CGRect {
        switch self {
        case .window(let target):
            return target.frame
        case .region(let target):
            return target.rect
        }
    }

    var windowTarget: WindowTarget? {
        switch self {
        case .window(let target):
            return target
        case .region(let target):
            return target.scrollTarget
        }
    }
}

struct CaptureSettings: Equatable {
    var overlapFraction: Double = 0.55
    var scrollDelay: Double = 0.55
    var recordingFPS: Int = 30
    var recordingAudio: Bool = true
    var recordingMicrophone: Bool = false
    var allowCompatibilityScroll: Bool = true
    var manualScroll: Bool = false
    var recordingCountdown: Int = 0

    var scrollFraction: Double {
        max(0.30, min(0.55, 1.0 - overlapFraction))
    }
}

struct CaptureProgress: Equatable, Sendable {
    var screens: Int
    var pixelHeight: Int
}

struct CaptureOutput {
    let rawImage: RawImageFile
    let screens: Int
    let width: Int
    let height: Int
    let backingScale: CGFloat
    let isSingleShot: Bool
    let warning: String?
}

struct CaptureResult: Identifiable {
    let id = UUID()
    let rawImage: RawImageFile
    let fileURL: URL?
    let width: Int
    let height: Int
    let screens: Int
    let backingScale: CGFloat
    let isSingleShot: Bool
    let warning: String?

    var dimensionsText: String {
        "\(width) × \(height) px"
    }

    var fileSizeText: String {
        guard let fileURL,
              let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum CapturePhase: Equatable {
    case idle
    case capturing
    case result
}

enum CapturePermission {
    case screen
    case accessibility
    case microphone
}

enum DiscoveryError: Error, LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "尚未获得屏幕录制权限。请在“系统设置 → 隐私与安全性 → 屏幕录制”中允许“截录”。"
    }
}

enum CaptureError: Error, LocalizedError {
    case permissionDenied
    case accessibilityDenied
    case windowUnavailable
    case screenUnavailable
    case diskFull
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要屏幕录制权限才能截取窗口。"
        case .accessibilityDenied:
            return "需要辅助功能权限才能自动滚动窗口。"
        case .windowUnavailable:
            return "所选窗口已关闭或不再可见。"
        case .screenUnavailable:
            return "无法读取所选窗口所在的显示器。"
        case .diskFull:
            return "磁盘剩余空间不足。请清理磁盘后重试；已截取的内容会自动保存。"
        case .captureFailed(let message):
            return "窗口截图失败：\(message)"
        }
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
