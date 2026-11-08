import AppKit
import CoreGraphics
import LongShotCore
import ScreenCaptureKit

final class CaptureEngine {
    typealias ProgressHandler = @MainActor (CaptureProgress) -> Void

    private enum ScrollStrategy {
        case pidPixel
        case pidLine
    }

    private let source: CaptureSource
    private let settings: CaptureSettings
    private let mode: ScreenshotMode
    private let progressHandler: ProgressHandler

    private let lock = NSLock()
    private var cancelled = false
    private var liveWindowFrame: CGRect
    private var strategy: ScrollStrategy = .pidPixel
    private var triedFallback = false

    private var scrollTarget: WindowTarget? { source.windowTarget }

    init(
        source: CaptureSource,
        settings: CaptureSettings,
        mode: ScreenshotMode,
        progress: @escaping ProgressHandler
    ) {
        self.source = source
        self.settings = settings
        self.mode = mode
        self.progressHandler = progress
        self.liveWindowFrame = source.hudFrame
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func run() async throws -> CaptureOutput {
        guard Permissions.hasScreenRecording else { throw CaptureError.permissionDenied }
        if mode == .long, scrollTarget != nil, !Permissions.hasAccessibility {
            throw CaptureError.accessibilityDenied
        }

        if let scrollTarget {
            await MainActor.run { WindowActivator.activate(scrollTarget) }
            try await sleep(milliseconds: 420)
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
        var captureRegion: RegionTarget?

        switch source {
        case .window(let windowTarget):
            guard let window = content.windows.first(where: { $0.windowID == windowTarget.id }) else {
                throw CaptureError.windowUnavailable
            }
            liveWindowFrame = window.frame
            filter = SCContentFilter(desktopIndependentWindow: window)
            let pixelScale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            configuration = makeWindowConfiguration(for: window, pixelScale: pixelScale)

        case .region(let regionTarget):
            guard let display = content.displays.first(where: { $0.displayID == regionTarget.displayID })
                ?? content.displays.first(where: { $0.frame.intersects(regionTarget.rect) }) else {
                throw CaptureError.screenUnavailable
            }
            captureRegion = regionTarget
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let ownApplications = content.applications.filter { $0.processID == ownPID }
            let ownWindows = content.windows.filter {
                $0.owningApplication?.processID == ownPID
            }
            if ownApplications.isEmpty {
                filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            } else {
                filter = SCContentFilter(
                    display: display,
                    excludingApplications: ownApplications,
                    exceptingWindows: []
                )
            }
            let displayScale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            configuration = makeDisplayConfiguration(display: display, pixelScale: displayScale)
        }

        var previous: BGRAImage
        let backingScale: CGFloat
        do {
            let fullImage = try await capture(filter: filter, configuration: configuration)
            let frameImage: CGImage
            if let captureRegion {
                frameImage = try cropToRegion(fullImage, region: captureRegion)
                backingScale = CGFloat(frameImage.width) / max(captureRegion.rect.width, 1)
            } else {
                frameImage = fullImage
                backingScale = CGFloat(fullImage.width) / max(liveWindowFrame.width, 1)
            }
            previous = try BGRAImage(cgImage: frameImage)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        let canvas: StitchCanvas
        do {
            canvas = try StitchCanvas(first: previous)
        } catch CanvasError.diskFull {
            throw CaptureError.diskFull
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        if mode == .normal {
            await report(screens: 1, height: canvas.height)
            let rawImage: RawImageFile
            do {
                rawImage = try canvas.finalize()
            } catch {
                throw CaptureError.captureFailed(error.localizedDescription)
            }
            return CaptureOutput(
                rawImage: rawImage,
                screens: 1,
                width: canvas.width,
                height: canvas.height,
                backingScale: backingScale,
                isSingleShot: true,
                warning: nil
            )
        }

        let aligner = FrameAligner(
            maximumScrollFraction: min(0.60, max(0.46, settings.scrollFraction + 0.09))
        )

        let viewportPoints = Double(previous.height) / Double(max(0.5, backingScale))
        var screens = 1
        var scrollPoints = viewportPoints * settings.scrollFraction
        var warning: String?
        let targetScrollPixels = Double(previous.height) * settings.scrollFraction

        await report(screens: screens, height: canvas.height)

        while true {
            if isCancelled { break }
            guard scrollTarget != nil else {
                warning = "所选区域下没有可滚动的窗口，已保存当前画面。"
                break
            }

            await report(screens: screens, height: canvas.height)

            sendScroll(points: scrollPoints)
            try await sleep(milliseconds: Int(settings.scrollDelay * 1000))

            guard !isCancelled else { break }

            var next = try await captureBitmap(
                filter: filter,
                configuration: configuration,
                region: captureRegion
            )
            var moved = !previous.isNearlyEqual(to: next, tolerance: 0.0012)

            if !moved, !triedFallback {
                triedFallback = true
                strategy = .pidLine
                sendScroll(points: scrollPoints * 1.15)
                try await sleep(milliseconds: Int(settings.scrollDelay * 1000) + 120)
                guard !isCancelled else { break }
                next = try await captureBitmap(
                    filter: filter,
                    configuration: configuration,
                    region: captureRegion
                )
                moved = !previous.isNearlyEqual(to: next, tolerance: 0.0012)
            }

            guard moved else {
                if screens == 1 {
                    warning = "当前窗口没有可滚动的内容，已保存可见画面。"
                }
                break
            }

            let alignment: AlignmentResult
            do {
                alignment = try aligner.align(previous: previous, next: next)
            } catch {
                warning = "页面内容变化较大，已在第 \(screens) 屏停止拼接，前面截取的内容仍会保存。"
                break
            }

            guard alignment.offset > 0 else {
                if screens == 1 {
                    warning = "当前窗口没有可滚动的内容，已保存可见画面。"
                }
                break
            }

            do {
                _ = try canvas.append(next, offset: alignment.offset)
            } catch CanvasError.diskFull {
                warning = "磁盘剩余空间不足，已停止滚动并保存已截取的 \(canvas.height.formatted()) px 内容。"
                break
            } catch {
                warning = "拼接下一屏时遇到问题，已保留前面截取的内容。"
                break
            }

            screens += 1
            previous = next

            let measured = Double(alignment.offset)
            if measured > 15, alignment.confidence > 0.08 {
                let ratio = targetScrollPixels / measured
                let clamped = max(0.62, min(1.70, ratio))
                scrollPoints = max(50, min(viewportPoints * 0.82, scrollPoints * clamped))
            }

            await report(screens: screens, height: canvas.height)

            if isCancelled {
                warning = "已手动停止，图片包含刚刚截取到的 \(screens) 屏内容。"
                break
            }
            if warning != nil { break }
        }

        if isCancelled, warning == nil {
            warning = "已手动停止，图片包含已截取的 \(screens) 屏内容。"
        }

        await report(screens: screens, height: canvas.height)

        let rawImage: RawImageFile
        do {
            rawImage = try canvas.finalize()
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }

        return CaptureOutput(
            rawImage: rawImage,
            screens: screens,
            width: canvas.width,
            height: canvas.height,
            backingScale: backingScale,
            isSingleShot: false,
            warning: warning
        )
    }

    // MARK: - Capture configuration

    private func makeWindowConfiguration(
        for window: SCWindow,
        pixelScale: CGFloat
    ) -> SCStreamConfiguration {
        let scale = max(1, pixelScale)
        let width = max(2, Int((window.frame.width * scale).rounded()))
        let height = max(2, Int((window.frame.height * scale).rounded()))

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    private func makeDisplayConfiguration(
        display: SCDisplay,
        pixelScale: CGFloat
    ) -> SCStreamConfiguration {
        let scale = max(1, pixelScale)
        let configuration = SCStreamConfiguration()
        configuration.width = max(2, Int((display.frame.width * scale).rounded()))
        configuration.height = max(2, Int((display.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        return configuration
    }

    private func capture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureError.captureFailed(error.localizedDescription)
        }
    }

    private func captureBitmap(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration,
        region: RegionTarget?
    ) async throws -> BGRAImage {
        let fullImage = try await capture(filter: filter, configuration: configuration)
        let image: CGImage
        if let region {
            image = try cropToRegion(fullImage, region: region)
        } else {
            image = fullImage
        }
        return try BGRAImage(cgImage: image)
    }

    private func cropToRegion(_ image: CGImage, region: RegionTarget) throws -> CGImage {
        let frame = region.displayFrame
        guard frame.width > 0, frame.height > 0 else { throw CaptureError.captureFailed("区域坐标无效") }
        let scaleX = CGFloat(image.width) / frame.width
        let scaleY = CGFloat(image.height) / frame.height
        let x0 = max(0, min(image.width - 1, Int(((region.rect.minX - frame.minX) * scaleX).rounded())))
        let y0 = max(0, min(image.height - 1, Int(((region.rect.minY - frame.minY) * scaleY).rounded())))
        let x1 = max(x0 + 1, min(image.width, Int(((region.rect.maxX - frame.minX) * scaleX).rounded())))
        let y1 = max(y0 + 1, min(image.height, Int(((region.rect.maxY - frame.minY) * scaleY).rounded())))
        let rect = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        guard let cropped = image.cropping(to: rect) else {
            throw CaptureError.captureFailed("无法裁剪框选区域")
        }
        return cropped
    }

    // MARK: - Scrolling

    private func sendScroll(points: Double) {
        // Send scroll only to the captured application. A global HID event would
        // steal the user's mouse wheel and can affect whichever app is under the
        // pointer. postToPid leaves the cursor and other applications untouched.
        guard let scrollTarget else { return }
        let units: CGScrollEventUnit = strategy == .pidLine ? .line : .pixel
        let magnitude: Int32 = strategy == .pidLine
            ? max(1, Int32(points / 48))
            : Int32(max(1, min(9_000, points)))
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 1,
            wheel1: -magnitude,
            wheel2: 0,
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.postToPid(scrollTarget.processID)
    }

    // MARK: - Helpers

    private func report(screens: Int, height: Int) async {
        await progressHandler(CaptureProgress(screens: screens, pixelHeight: height))
    }

    private func sleep(milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
    }
}
