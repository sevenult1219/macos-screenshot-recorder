import AppKit

@MainActor
final class PinnedImageController {
    static let shared = PinnedImageController()

    private var panels: [PinnedPanel] = []
    private var cascade = 0

    func pin(image: NSImage, title: String) {
        let maxDimension: CGFloat = 520
        let aspect = image.size.width / max(1, image.size.height)
        var width = min(maxDimension, max(180, image.size.width))
        var height = width / max(0.01, aspect)
        if height > maxDimension {
            height = maxDimension
            width = height * aspect
        }
        width = max(160, width)
        height = max(100, height)

        let panel = PinnedPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 160, height: 100)
        panel.animationBehavior = .utilityWindow

        let content = PinnedContentView(image: image, title: title) { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.close(panel)
        }
        panel.contentView = content
        content.autoresizingMask = [.width, .height]
        content.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.setContentSize(NSSize(width: width, height: height))

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(cascade % 8) * 26
        cascade += 1
        panel.setFrame(
            NSRect(
                x: screen.midX - width / 2 + offset,
                y: screen.midY - height / 2 - offset,
                width: width,
                height: height
            ),
            display: false
        )

        panels.append(panel)
        panel.orderFrontRegardless()
    }

    private func close(_ panel: PinnedPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}

private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PinnedContentView: NSView {
    private let image: NSImage
    private let closeButton: NSButton
    private let onClose: () -> Void

    init(image: NSImage, title: String, onClose: @escaping () -> Void) {
        self.image = image
        self.onClose = onClose
        self.closeButton = NSButton()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "关闭贴图"
        )
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22)
        ])

        toolTip = title
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 240, height: 160)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.setFill()
        bounds.fill()
        image.draw(
            in: bounds,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc private func closeTapped() {
        onClose()
    }
}
