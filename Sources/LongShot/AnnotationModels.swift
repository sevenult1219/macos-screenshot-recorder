import AppKit
import CoreGraphics
import Foundation

enum AnnotationTool: String, CaseIterable, Identifiable {
    case arrow
    case rectangle
    case redact
    case pen
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .arrow: return "箭头"
        case .rectangle: return "矩形"
        case .redact: return "遮挡"
        case .pen: return "画笔"
        case .text: return "文字"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .redact: return "eye.slash"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        }
    }
}

enum AnnotationInk: String, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case black
    case white

    var id: String { rawValue }

    var color: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 0.96, green: 0.22, blue: 0.22, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.52, blue: 0.08, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.12, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.16, green: 0.76, blue: 0.36, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.18, green: 0.47, blue: 1.0, alpha: 1)
        case .black: return .black
        case .white: return .white
        }
    }

    var label: String {
        switch self {
        case .red: return "红"
        case .orange: return "橙"
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .black: return "黑"
        case .white: return "白"
        }
    }
}

struct ImageAnnotation: Identifiable {
    enum Kind {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case redact(CGRect)
        case pen([CGPoint])
        case text(CGPoint, String)
    }

    let id = UUID()
    var kind: Kind
    var ink: AnnotationInk
    var lineWidth: CGFloat

    var fontSize: CGFloat {
        max(22, lineWidth * 6)
    }
}

struct AnnotationDraft {
    var tool: AnnotationTool
    var start: CGPoint
    var current: CGPoint
    var points: [CGPoint]

    var rect: CGRect {
        CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}

enum AnnotationRenderer {
    enum RenderError: LocalizedError {
        case contextFailed
        case pngFailed

        var errorDescription: String? {
            switch self {
            case .contextFailed: return "无法创建标注画布。"
            case .pngFailed: return "无法生成标注后的 PNG。"
            }
        }
    }

    static func pngData(
        image: CGImage,
        pixelSize: CGSize,
        annotations: [ImageAnnotation]
    ) throws -> Data {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw RenderError.contextFailed
        }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true
        defer { NSGraphicsContext.current = previous }

        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor.clear.setFill()
        bounds.fill()
        NSImage(cgImage: image, size: NSSize(width: width, height: height))
            .draw(in: bounds, from: .zero, operation: .copy, fraction: 1)

        for annotation in annotations {
            draw(annotation, in: context, canvasHeight: CGFloat(height))
        }

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.pngFailed
        }
        return data
    }

    private static func draw(
        _ annotation: ImageAnnotation,
        in context: NSGraphicsContext,
        canvasHeight: CGFloat
    ) {
        let color = annotation.ink.color
        color.setStroke()
        color.setFill()
        let width = max(1, annotation.lineWidth)
        let rect: (CGRect) -> NSRect = { value in
            NSRect(
                x: value.minX,
                y: canvasHeight - value.maxY,
                width: value.width,
                height: value.height
            )
        }
        let point: (CGPoint) -> NSPoint = { value in
            NSPoint(x: value.x, y: canvasHeight - value.y)
        }

        switch annotation.kind {
        case .arrow(let start, let end):
            let from = point(start)
            let to = point(end)
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: from)
            path.line(to: to)
            path.stroke()

            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(10, width * 3.8)
            let headAngle = CGFloat.pi / 7
            let left = NSPoint(
                x: to.x - headLength * cos(angle - headAngle),
                y: to.y - headLength * sin(angle - headAngle)
            )
            let right = NSPoint(
                x: to.x - headLength * cos(angle + headAngle),
                y: to.y - headLength * sin(angle + headAngle)
            )
            let head = NSBezierPath()
            head.lineWidth = width
            head.lineCapStyle = .round
            head.move(to: left)
            head.line(to: to)
            head.line(to: right)
            head.stroke()

        case .rectangle(let value):
            let path = NSBezierPath(rect: rect(value))
            path.lineWidth = width
            path.stroke()

        case .redact(let value):
            NSColor.black.setFill()
            NSBezierPath(
                roundedRect: rect(value),
                xRadius: min(10, width * 2),
                yRadius: min(10, width * 2)
            ).fill()

        case .pen(let points):
            guard let first = points.first else { return }
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: point(first))
            for value in points.dropFirst() {
                path.line(to: point(value))
            }
            path.stroke()

        case .text(let location, let text):
            guard !text.isEmpty else { return }
            let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .semibold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let string = NSAttributedString(string: text, attributes: attributes)
            let size = string.boundingRect(
                with: NSSize(width: 2_000, height: 2_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).size
            string.draw(
                at: NSPoint(
                    x: location.x,
                    y: canvasHeight - location.y - size.height
                )
            )
        }
    }
}
