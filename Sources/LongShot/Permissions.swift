import ApplicationServices
import AppKit
import AVFoundation
import CoreGraphics

enum Permissions {
    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openSystemSettings(for permission: CapturePermission) {
        let anchor: String
        switch permission {
        case .screen: anchor = "Privacy_ScreenCapture"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .microphone: anchor = "Privacy_Microphone"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum AppScreenGeometry {
    /// ScreenCaptureKit uses a top-left origin; AppKit windows use bottom-left.
    static func appKitPoint(fromScreenCapturePoint point: CGPoint) -> CGPoint {
        let mainMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGPoint(x: point.x, y: mainMaxY - point.y)
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}
