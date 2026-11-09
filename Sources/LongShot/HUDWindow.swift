import AppKit
import SwiftUI

enum HUDMode {
    case working
    case recording
    case finishing
    case done
}

@MainActor
final class HUDState: ObservableObject {
    @Published var mode: HUDMode = .working
    @Published var title = "正在截屏"
    @Published var detail = "准备中…"
    @Published var manual = false
    var onStop: (() -> Void)?
}

private final class HUDWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDController {
    private let state = HUDState()
    private var panel: HUDWindow?
    private var hideTask: DispatchWorkItem?

    func show(
        title: String,
        label: String,
        frame: CGRect,
        manual: Bool = false,
        onStop: @escaping () -> Void
    ) {
        hideTask?.cancel()
        state.mode = .working
        state.title = title
        state.manual = manual
        state.detail = manual
            ? "滚动页面，完成后点“停止”"
            : "已选择 \(label) · 准备中…"
        state.onStop = onStop

        let panel = ensurePanel()
        position(panel, near: frame)
        panel.orderFrontRegardless()
    }

    func showCountdown(
        seconds: Int,
        label: String,
        frame: CGRect,
        onCancel: @escaping () -> Void
    ) {
        hideTask?.cancel()
        state.mode = .working
        state.manual = false
        state.title = "准备录屏"
        state.detail = "\(seconds) 秒后开始 · \(label)"
        state.onStop = onCancel
        let panel = ensurePanel()
        position(panel, near: frame)
        panel.orderFrontRegardless()
    }

    func updateCountdown(seconds: Int, label: String) {
        guard state.mode == .working else { return }
        state.detail = "\(max(0, seconds)) 秒后开始 · \(label)"
    }

    func showRecording(label: String, frame: CGRect, onStop: @escaping () -> Void) {
        hideTask?.cancel()
        state.mode = .recording
        state.title = "正在录屏"
        state.detail = "00:00 · \(label)"
        state.onStop = onStop
        let panel = ensurePanel()
        position(panel, near: frame)
        panel.orderFrontRegardless()
    }

    func updateRecording(elapsed: TimeInterval, label: String) {
        guard state.mode == .recording else { return }
        let total = max(0, Int(elapsed))
        state.detail = String(format: "%02d:%02d · %@", total / 60, total % 60, label)
    }

    func showRecordingSaving() {
        guard state.mode == .recording else { return }
        state.mode = .finishing
        state.title = "正在保存录屏"
        state.detail = "封装 MP4 视频…"
    }

    func showRecordingDone(fileName: String) {
        state.mode = .done
        state.title = "录屏已保存"
        state.detail = fileName
        hide(after: 1.2)
    }

    func update(_ progress: CaptureProgress) {
        hideTask?.cancel()
        guard state.mode == .working else { return }
        state.detail = state.manual
            ? "第 \(progress.screens) 屏 · \(progress.pixelHeight.formatted()) px · 完成后点停止"
            : "第 \(progress.screens) 屏 · 高度 \(progress.pixelHeight.formatted()) px"
    }

    func showStopping() {
        guard state.mode == .working else { return }
        state.title = "正在停止…"
        state.detail = "保存已经截取的内容"
    }

    func showFinishing(pixelHeight: Int) {
        guard state.mode == .working else { return }
        state.mode = .finishing
        state.title = "正在保存 PNG"
        state.detail = "原始像素 \(pixelHeight.formatted()) px · 正在编码 PNG…"
    }

    func updateFinishing(progress: Double, pixelHeight: Int) {
        guard state.mode == .finishing else { return }
        let percent = min(100, max(0, Int((progress * 100).rounded())))
        state.detail = "无损编码 \(percent)% · 高度 \(pixelHeight.formatted()) px"
    }

    func showDone(title: String, pixelHeight: Int) {
        state.mode = .done
        state.title = title
        state.detail = "图片高度 \(pixelHeight.formatted()) px，已保存到“图片/长截屏”"
        hide(after: 1.2)
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideTask = work
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            work.perform()
        }
    }

    private func ensurePanel() -> HUDWindow {
        if let panel { return panel }
        let panel = HUDWindow(
            contentRect: NSRect(x: 0, y: 0, width: 388, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSWindow, near screenCaptureFrame: CGRect) {
        let center = CGPoint(x: screenCaptureFrame.midX, y: screenCaptureFrame.midY)
        let appKitCenter = AppScreenGeometry.appKitPoint(fromScreenCapturePoint: center)
        let screen = AppScreenGeometry.screen(containing: appKitCenter) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - 18
        )
        panel.setFrameOrigin(origin)
    }
}

private struct HUDView: View {
    @ObservedObject var state: HUDState
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 38, height: 38)
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    if state.mode == .working || state.mode == .finishing || state.mode == .recording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .opacity(pulse ? 0.35 : 1)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                                value: pulse
                            )
                    }
                    Text(state.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Text(state.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if state.mode == .working || state.mode == .recording {
                Button("停止") {
                    state.onStop?()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if state.mode == .finishing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(width: 388, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.8)
                )
        )
        .onAppear { pulse = true }
    }

    private var iconName: String {
        switch state.mode {
        case .working, .finishing: return "arrow.down.to.line"
        case .recording: return "record.circle"
        case .done: return "checkmark"
        }
    }

    private var iconBackground: Color {
        switch state.mode {
        case .working, .finishing: return Color.accentColor.opacity(0.16)
        case .recording: return Color.red.opacity(0.16)
        case .done: return Color.green.opacity(0.16)
        }
    }

    private var iconForeground: Color {
        switch state.mode {
        case .working, .finishing: return .accentColor
        case .recording: return .red
        case .done: return .green
        }
    }
}
