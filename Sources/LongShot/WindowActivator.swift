import AppKit
import ApplicationServices

enum WindowActivator {
    static func activate(_ target: WindowTarget) {
        if let app = NSRunningApplication(processIdentifier: target.processID) {
            _ = app.activate(options: [.activateAllWindows])
        }
        raiseAXWindow(for: target)
    }

    private static func raiseAXWindow(for target: WindowTarget) {
        let appElement = AXUIElementCreateApplication(target.processID)
        AXUIElementSetAttributeValue(
            appElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        var rawWindows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &rawWindows
        ) == .success,
        let windows = rawWindows as? [AXUIElement],
        !windows.isEmpty else {
            return
        }

        var bestElement: AXUIElement?
        var bestScore = 0

        for window in windows {
            var score = 0
            if let number = intAttribute(window, "AXWindowNumber"), number == Int(target.id) {
                score += 100
            }

            let title = stringAttribute(window, kAXTitleAttribute as CFString) ?? ""
            if !target.title.isEmpty, title == target.title {
                score += 40
            } else if !target.title.isEmpty, !title.isEmpty,
                      title.contains(target.title) || target.title.contains(title) {
                score += 16
            }

            if let size = sizeAttribute(window) {
                let widthDelta = abs(size.width - target.frame.width)
                let heightDelta = abs(size.height - target.frame.height)
                if widthDelta < 3, heightDelta < 3 {
                    score += 30
                } else if widthDelta < 24, heightDelta < 24 {
                    score += 10
                }
            }

            if let position = pointAttribute(window) {
                // Accessibility positions and ScreenCaptureKit frames both use
                // a top-left global origin.
                let centerY = position.y + (sizeAttribute(window)?.height ?? target.frame.height) / 2
                if abs(centerY - target.frame.midY) < 24 { score += 8 }
            }

            if score > bestScore {
                bestScore = score
                bestElement = window
            }
        }

        guard let element = bestElement ?? windows.first else { return }
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func intAttribute(_ element: AXUIElement, _ name: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value as? String
    }

    private static func sizeAttribute(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &value
        ) == .success, let axValue = value,
           CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return size
    }

    private static func pointAttribute(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &value
        ) == .success, let axValue = value,
           CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgPoint, &point) else { return nil }
        return point
    }
}
