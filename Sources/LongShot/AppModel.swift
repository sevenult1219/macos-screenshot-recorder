import AppKit
import AVFoundation
import Combine
import ImageIO
import LongShotCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var windows: [WindowTarget] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var selectedScreenshotWindowID: CGWindowID?
    @Published var selectedRecordingWindowID: CGWindowID?
    @Published private(set) var isLoadingWindows = false
    @Published var hasScreenPermission = Permissions.hasScreenRecording
    @Published var hasAccessibilityPermission = Permissions.hasAccessibility
    @Published var hasMicrophonePermission = Permissions.hasMicrophone
    @Published var phase: CapturePhase = .idle
    @Published var result: CaptureResult?
    @Published var screenshotSaveURL: URL?
    @Published var alert: AppAlert?
    @Published var toast: String?
    @Published var isExportingSegments = false
    @Published var segmentExportProgress: Double = 0
    @Published var isSelectingRegion = false
    @Published var isRecording = false
    @Published var recordingResult: RecordingResult?
    @Published var recordingSaveURL: URL?
    @Published var openedMedia: OpenedMedia?
    @Published var recordingRegion: RegionTarget?
    @Published var screenshotRegion: RegionTarget?
    @Published var recordSourceChoice: RecordSourceChoice = .window
    @Published var screenshotSource: ScreenshotSource = .window
    @Published var screenshotMode: ScreenshotMode = .long
    @Published var section: AppSection = .home
    @Published var settings: CaptureSettings = CaptureSettings() {
        didSet { persistSettings() }
    }

    private var engine: CaptureEngine?
    private var captureTask: Task<Void, Never>?
    private let hud = HUDController()
    private let regionSelector = RegionSelectionController()
    private var recorder: ScreenRecorder?
    private var recordingStarting = false
    private var microphoneRequestInFlight = false
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var recordingLabel = ""
    private var didObserveActivation = false

    init() {
        loadSettings()
    }

    var selectedScreenshotWindow: WindowTarget? {
        guard let selectedScreenshotWindowID else { return nil }
        return windows.first { $0.id == selectedScreenshotWindowID }
    }

    var selectedRecordingWindow: WindowTarget? {
        guard let selectedRecordingWindowID else { return nil }
        return windows.first { $0.id == selectedRecordingWindowID }
    }

    var isCapturing: Bool { phase == .capturing }

    var canSelectRegion: Bool {
        !isCapturing && !isSelectingRegion && !isRecording && !recordingStarting && phase != .result
    }

    var canRecord: Bool {
        hasScreenPermission && !isCapturing && !isRecording && !recordingStarting && !isSelectingRegion && phase != .result
    }

    var canStartScreenshot: Bool {
        guard hasScreenPermission, phase != .capturing, !isRecording, !recordingStarting, !isSelectingRegion else {
            return false
        }
        if screenshotMode == .long, !hasAccessibilityPermission { return false }
        if screenshotSource == .window {
            return selectedScreenshotWindow != nil
        }
        return screenshotRegion != nil
    }

    func onAppear() {
        refreshPermissions()
        observeActivationIfNeeded()
        if hasScreenPermission {
            Task {
                if windows.isEmpty { await refreshWindows() }
            }
        } else {
            requestScreenPermissionAtFirstLaunch()
        }
    }

    private func requestScreenPermissionAtFirstLaunch() {
        let key = "didRequestScreenCaptureAtLaunch"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            let granted = Permissions.requestScreenRecording()
            hasScreenPermission = Permissions.hasScreenRecording || granted
            if hasScreenPermission {
                await refreshWindows()
            }
        }
    }

    // MARK: - Permissions

    func refreshPermissions() {
        let screenBefore = hasScreenPermission
        hasScreenPermission = Permissions.hasScreenRecording
        hasAccessibilityPermission = Permissions.hasAccessibility
        hasMicrophonePermission = Permissions.hasMicrophone

        if hasScreenPermission, !screenBefore, windows.isEmpty, !isLoadingWindows {
            Task { await refreshWindows() }
        }
        if !hasScreenPermission, !windows.isEmpty {
            windows = []
            thumbnails = [:]
            selectedScreenshotWindowID = nil
            selectedRecordingWindowID = nil
        }
    }

    func requestScreenPermission() {
        let granted = Permissions.requestScreenRecording()
        hasScreenPermission = Permissions.hasScreenRecording
        if granted || hasScreenPermission {
            Task { await refreshWindows() }
        } else {
            alert = AppAlert(
                title: "请在系统设置中允许屏幕录制",
                message: "勾选“截录”后回到本应用即可刷新窗口列表。首次授权后，macOS 可能要求重新启动应用。"
            )
            Permissions.openSystemSettings(for: .screen)
        }
    }

    func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasMicrophonePermission = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                hasMicrophonePermission = granted || Permissions.hasMicrophone
                if !granted {
                    alert = AppAlert(
                        title: "麦克风未授权",
                        message: "录屏时仍可只录制系统声音。需要麦克风时，请在“系统设置 → 隐私与安全性 → 麦克风”中允许“截录”。"
                    )
                }
            }
        default:
            hasMicrophonePermission = false
            alert = AppAlert(
                title: "需要麦克风权限",
                message: "请在“系统设置 → 隐私与安全性 → 麦克风”中允许“截录”，或在录屏设置中关闭“录制麦克风”。"
            )
            Permissions.openSystemSettings(for: .microphone)
        }
    }

    func requestAccessibilityPermission() {
        Permissions.requestAccessibility()
        hasAccessibilityPermission = Permissions.hasAccessibility
        alert = AppAlert(
            title: "请允许辅助功能",
            message: "自动滚动需要“辅助功能”权限。在“系统设置 → 隐私与安全性 → 辅助功能”中打开“截录”，然后回到本应用。"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            Permissions.openSystemSettings(for: .accessibility)
        }
    }

    private func observeActivationIfNeeded() {
        guard !didObserveActivation else { return }
        didObserveActivation = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let wasGranted = self.hasScreenPermission
                self.refreshPermissions()
                if self.hasScreenPermission, !wasGranted, self.windows.isEmpty {
                    await self.refreshWindows()
                }
            }
        }
    }

    // MARK: - Media files

    func presentMediaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开图片或视频"
        panel.prompt = "打开"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openMediaURLs([url])
    }

    func openPendingMedia() {
        let urls = MediaOpenCenter.shared.consume()
        guard !urls.isEmpty else { return }
        openMediaURLs(urls)
    }

    func openMediaURLs(_ urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            let type = UTType(filenameExtension: standardized.pathExtension)

            if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
                NSApp.activate(ignoringOtherApps: true)
                openedMedia = OpenedMedia(url: standardized, kind: .video(standardized))
                return
            }

            if type?.conforms(to: .image) == true {
                guard let source = CGImageSourceCreateWithURL(standardized as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    alert = AppAlert(title: "无法打开图片", message: "无法读取这个图片文件。")
                    return
                }
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                do {
                    let image = try BGRAImage(cgImage: cgImage)
                    let directory = try RawImageFile.defaultDirectory()
                    let rawURL = directory.appendingPathComponent(
                        "external_\(UUID().uuidString).raw"
                    )
                    guard FileManager.default.createFile(atPath: rawURL.path, contents: nil) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                    try image.withUnsafeMutableBytes { buffer in
                        guard let base = buffer.baseAddress else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        let data = Data(
                            bytesNoCopy: base,
                            count: buffer.count,
                            deallocator: .none
                        )
                        try data.write(to: rawURL, options: .atomic)
                    }
                    let rawImage = try RawImageFile(
                        url: rawURL,
                        width: cgImage.width,
                        height: cgImage.height
                    )
                    NSApp.activate(ignoringOtherApps: true)
                    openedMedia = OpenedMedia(
                        url: standardized,
                        kind: .image(rawImage, pixelSize: size)
                    )
                    return
                } catch {
                    alert = AppAlert(
                        title: "无法打开图片",
                        message: "图片解码或临时文件写入失败：\(error.localizedDescription)"
                    )
                    return
                }
            }
        }

        alert = AppAlert(
            title: "不支持的文件",
            message: "截录可以打开常见图片（PNG、JPEG、HEIC、TIFF 等）和视频（MP4、MOV 等）。"
        )
    }

    // MARK: - Window list

    func refreshWindows() async {
        guard !isLoadingWindows else { return }
        guard Permissions.hasScreenRecording else {
            hasScreenPermission = false
            return
        }

        isLoadingWindows = true
        defer { isLoadingWindows = false }

        do {
            let discovered = try await WindowDiscovery.discover()
            hasScreenPermission = true
            let previousScreenshot = selectedScreenshotWindowID
            let previousRecording = selectedRecordingWindowID
            windows = discovered.map(\.target)
            thumbnails = thumbnails.filter { key, _ in
                windows.contains { $0.id == key }
            }

            if let previousScreenshot, windows.contains(where: { $0.id == previousScreenshot }) {
                selectedScreenshotWindowID = previousScreenshot
            } else {
                selectedScreenshotWindowID = windows.first?.id
            }
            if let previousRecording, windows.contains(where: { $0.id == previousRecording }) {
                selectedRecordingWindowID = previousRecording
            } else {
                selectedRecordingWindowID = nil
            }

            for item in discovered where thumbnails[item.target.id] == nil {
                let id = item.target.id
                let scWindow = item.window
                Task { [weak self] in
                    guard let image = await WindowDiscovery.thumbnail(for: scWindow) else { return }
                    await MainActor.run {
                        guard let self, self.windows.contains(where: { $0.id == id }) else { return }
                        self.thumbnails[id] = image
                    }
                }
            }
        } catch {
            if !Permissions.hasScreenRecording {
                hasScreenPermission = false
            } else {
                alert = AppAlert(title: "无法读取窗口列表", message: error.localizedDescription)
            }
        }
    }

    func selectScreenshotWindow(_ window: WindowTarget) {
        guard !isCapturing else { return }
        selectedScreenshotWindowID = window.id
    }

    func selectRecordingWindow(_ window: WindowTarget) {
        guard !isRecording else { return }
        selectedRecordingWindowID = window.id
        recordSourceChoice = .window
    }

    func showSection(_ newSection: AppSection) {
        guard !isCapturing, !isRecording, !isSelectingRegion else { return }
        section = newSection
    }

    // MARK: - Capture

    func startScreenshot() {
        section = .screenshot
        guard Permissions.hasScreenRecording else {
            requestScreenPermission()
            return
        }
        if screenshotMode == .long, !Permissions.hasAccessibility {
            hasAccessibilityPermission = false
            requestAccessibilityPermission()
            return
        }

        if screenshotSource == .region {
            guard let region = screenshotRegion else {
                startScreenshotRegionSelection()
                return
            }
            hasScreenPermission = true
            if screenshotMode == .long { hasAccessibilityPermission = true }
            beginCapture(source: .region(region), mode: screenshotMode)
            return
        }

        guard let target = selectedScreenshotWindow else {
            alert = AppAlert(title: "请先选择一个窗口", message: "在“截屏”页点“选择窗口”来指定要截取的窗口。")
            return
        }
        hasScreenPermission = true
        if screenshotMode == .long { hasAccessibilityPermission = true }
        beginCapture(source: .window(target), mode: screenshotMode)
    }

    func startScreenshotRegionSelection() {
        guard canSelectRegion else { return }
        section = .screenshot
        guard Permissions.hasScreenRecording else {
            requestScreenPermission()
            return
        }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
            alert = AppAlert(title: "无法框选", message: "没有找到可用的显示器。")
            return
        }

        isSelectingRegion = true
        hideMainWindows()
        regionSelector.begin(on: screen, confirmTitle: "确认区域") { [weak self] selection in
            guard let self else { return }
            self.isSelectingRegion = false
            guard let selection else {
                self.showMainWindow()
                return
            }
            let center = CGPoint(
                x: selection.rectOnScreen.midX,
                y: (NSScreen.screens.first?.frame.maxY ?? 0) - selection.rectOnScreen.midY
            )
            guard let region = self.makeRegionTarget(
                selection,
                scrollTarget: RegionResolver.window(under: center)
            ) else {
                self.alert = AppAlert(title: "无法框选", message: "无法读取所选显示器的标识。")
                self.showMainWindow()
                return
            }
            self.screenshotRegion = region
            self.showMainWindow()
        }
    }

    private func makeRegionTarget(
        _ selection: RegionSelection,
        scrollTarget: WindowTarget?
    ) -> RegionTarget? {
        guard let displayID = selection.displayID else { return nil }
        let mainMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        let screenRect = selection.rectOnScreen
        let screenFrame = selection.screen.frame
        let rect = CGRect(
            x: screenRect.minX,
            y: mainMaxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        )
        let displayFrame = CGRect(
            x: screenFrame.minX,
            y: mainMaxY - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
        return RegionTarget(
            rect: rect,
            displayID: displayID,
            displayFrame: displayFrame,
            scrollTarget: scrollTarget
        )
    }

    func beginCapture(source: CaptureSource, mode: ScreenshotMode) {
        guard !isRecording, !recordingStarting else { return }
        phase = .capturing
        result = nil
        hud.show(
            title: mode == .long ? "正在长截屏" : "正在截屏",
            label: source.hudLabel,
            frame: source.hudFrame
        ) { [weak self] in
            self?.stopCapture()
        }
        hideMainWindows()

        let engine = CaptureEngine(source: source, settings: settings, mode: mode) { [weak self] value in
            self?.hud.update(value)
        }
        self.engine = engine

        captureTask = Task { [weak self] in
            do {
                let output = try await engine.run()
                await self?.finishCapture(output)
            } catch {
                await self?.failCapture(error)
            }
        }
    }

    func stopCapture() {
        guard phase == .capturing else { return }
        engine?.cancel()
        hud.showStopping()
    }

    private func finishCapture(_ output: CaptureOutput) async {
        guard phase == .capturing else { return }
        hud.showFinishing(pixelHeight: output.height)

        var warning = output.warning
        let raw = output.rawImage
        let scale = output.backingScale
        let hud = self.hud
        let saved = await Task.detached(priority: .userInitiated) { () -> (URL?, String?) in
            var url: URL?
            var saveError: String?
            do {
                url = try ImageWriter.saveToPictures(raw, backingScale: scale) { progress in
                    Task { @MainActor in
                        hud.updateFinishing(progress: progress, pixelHeight: output.height)
                    }
                }
            } catch {
                saveError = error.localizedDescription
            }
            return (url, saveError)
        }.value
        let fileURL = saved.0
        if let saveError = saved.1 {
            let prefix = warning.map { "\($0)\n" } ?? ""
            warning = "\(prefix)自动保存失败：\(saveError)"
        }
        let result = CaptureResult(
            rawImage: raw,
            fileURL: fileURL,
            width: output.width,
            height: output.height,
            screens: output.screens,
            backingScale: output.backingScale,
            isSingleShot: output.isSingleShot,
            warning: warning
        )

        self.result = result
        self.screenshotSaveURL = result.fileURL
        self.phase = .result
        self.engine = nil
        self.captureTask = nil

        showMainWindow()
        hud.showDone(title: output.isSingleShot ? "截图完成" : "长截图完成", pixelHeight: output.height)
    }

    private func failCapture(_ error: Error) async {
        guard phase == .capturing else { return }
        phase = .idle
        engine = nil
        captureTask = nil
        hud.hide()
        showMainWindow()
        alert = AppAlert(
            title: "截屏未完成",
            message: error.localizedDescription
        )
    }

    // MARK: - Screen recording

    func startRecordingWindow() {
        section = .record
        recordSourceChoice = .window
        guard let target = selectedRecordingWindow else {
            alert = AppAlert(title: "请先选择一个窗口", message: "在录屏页点击“选择窗口”来指定要录制的窗口。")
            return
        }
        startRecording(source: .window(target), label: target.appName)
    }

    func startRecordingScreen() {
        section = .record
        recordSourceChoice = .screen
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else {
            alert = AppAlert(title: "无法开始录屏", message: "没有找到可用的显示器。")
            return
        }
        startRecording(source: .display(displayID: displayID), label: "\(screen.localizedName) · 全屏")
    }

    func startRecordingRegionSelection() {
        guard canRecord else { return }
        guard Permissions.hasScreenRecording else {
            requestScreenPermission()
            return
        }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
            alert = AppAlert(title: "无法框选", message: "没有找到可用的显示器。")
            return
        }
        section = .record
        recordSourceChoice = .region
        isSelectingRegion = true
        hideMainWindows()
        regionSelector.begin(on: screen, confirmTitle: "确认区域") { [weak self] selection in
            guard let self else { return }
            self.isSelectingRegion = false
            guard let selection, let region = self.makeRegionTarget(selection, scrollTarget: nil) else {
                self.showMainWindow()
                return
            }
            self.recordingRegion = region
            self.recordSourceChoice = .region
            self.showMainWindow()
        }
    }

    func startRecordingRegion() {
        section = .record
        recordSourceChoice = .region
        guard let region = recordingRegion else {
            startRecordingRegionSelection()
            return
        }
        startRecording(source: .region(region), label: region.label)
    }

    private func startRecording(source: RecordingSource, label: String) {
        guard canRecord else { return }

        if settings.recordingMicrophone {
            if #available(macOS 15.0, *) {
                switch AVCaptureDevice.authorizationStatus(for: .audio) {
                case .authorized:
                    break
                case .notDetermined:
                    guard !microphoneRequestInFlight else { return }
                    microphoneRequestInFlight = true
                    Task {
                        let granted = await AVCaptureDevice.requestAccess(for: .audio)
                        self.microphoneRequestInFlight = false
                        self.hasMicrophonePermission = granted || Permissions.hasMicrophone
                        if granted {
                            self.startRecordingNow(source: source, label: label)
                        } else {
                            self.handleMicrophonePermissionDenied()
                        }
                    }
                    return
                default:
                    handleMicrophonePermissionDenied()
                    return
                }
            } else {
                alert = AppAlert(
                    title: "无法录制麦克风",
                    message: "麦克风录制需要 macOS 15 或更高版本。"
                )
                return
            }
        }

        startRecordingNow(source: source, label: label)
    }

    private func handleMicrophonePermissionDenied() {
        hasMicrophonePermission = false
        alert = AppAlert(
            title: "需要麦克风权限",
            message: "请在“系统设置 → 隐私与安全性 → 麦克风”中允许“截录”，或关闭“录制麦克风”开关。"
        )
        Permissions.openSystemSettings(for: .microphone)
    }

    private func startRecordingNow(source: RecordingSource, label: String) {
        guard canRecord else { return }
        guard Permissions.hasScreenRecording else {
            requestScreenPermission()
            return
        }
        hasScreenPermission = true
        let outputURL: URL
        do {
            outputURL = try ScreenRecorder.makeOutputURL()
        } catch {
            alert = AppAlert(title: "无法开始录屏", message: error.localizedDescription)
            return
        }

        if case .window(let target) = source {
            WindowActivator.activate(target)
        }

        recordingResult = nil
        recordingLabel = label
        recordingStarting = true
        hideMainWindows()
        hud.showRecording(label: label, frame: hudFrame(for: source)) { [weak self] in
            self?.stopRecording()
        }

        let recorder = ScreenRecorder(
            source: source,
            fps: settings.recordingFPS,
            capturesAudio: settings.recordingAudio,
            capturesMicrophone: settings.recordingMicrophone,
            outputURL: outputURL
        )
        recorder.onError = { [weak self] error in
            Task { @MainActor in self?.handleRecordingError(error) }
        }
        self.recorder = recorder

        Task {
            do {
                try await recorder.start()
                recordingStarting = false
                isRecording = true
                recordingStartedAt = Date()
                startRecordingTimer()
                hud.updateRecording(elapsed: 0, label: label)
            } catch {
                recordingStarting = false
                failRecording(error)
            }
        }
    }

    func stopRecording() {
        guard isRecording, let recorder else { return }
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        hud.showRecordingSaving()
        Task {
            do {
                let result = try await recorder.stop()
                let thumbnail = await Self.recordingThumbnail(url: result.url)
                let withThumbnail = RecordingResult(
                    url: result.url,
                    duration: result.duration,
                    width: result.width,
                    height: result.height,
                    fileSize: result.fileSize,
                    thumbnail: thumbnail
                )
                self.recorder = nil
                self.recordingResult = withThumbnail
                self.recordingSaveURL = withThumbnail.url
                self.showMainWindow()
                self.hud.showRecordingDone(fileName: result.url.lastPathComponent)
            } catch {
                self.recorder = nil
                self.hud.hide()
                self.showMainWindow()
                self.alert = AppAlert(title: "录屏未保存", message: error.localizedDescription)
            }
        }
    }

    nonisolated private static func recordingThumbnail(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1200, height: 800)
        do {
            let (image, _) = try await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600))
            return NSImage(
                cgImage: image,
                size: NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
            )
        } catch {
            return nil
        }
    }

    private func failRecording(_ error: Error) {
        isRecording = false
        recordingStarting = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recorder = nil
        hud.hide()
        showMainWindow()
        alert = AppAlert(title: "无法开始录屏", message: error.localizedDescription)
    }

    private func handleRecordingError(_ error: Error) {
        guard isRecording else { return }
        stopRecording()
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording, let start = self.recordingStartedAt else { return }
                self.hud.updateRecording(
                    elapsed: Date().timeIntervalSince(start),
                    label: self.recordingLabel
                )
            }
        }
        recordingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func hudFrame(for source: RecordingSource) -> CGRect {
        switch source {
        case .window(let target):
            return target.frame
        case .display(let displayID):
            if let screen = NSScreen.screens.first(where: {
                (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value) == displayID
            }) {
                let mainMaxY = NSScreen.screens.first?.frame.maxY ?? 0
                return CGRect(
                    x: screen.frame.minX,
                    y: mainMaxY - screen.frame.maxY,
                    width: screen.frame.width,
                    height: screen.frame.height
                )
            }
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        case .region(let region):
            return region.rect
        }
    }

    func dismissRecordingResult() {
        recordingResult = nil
        recordingSaveURL = nil
        section = .record
    }

    // MARK: - Result actions

    func restart() {
        result = nil
        screenshotSaveURL = nil
        phase = .idle
        toast = nil
        Task { await refreshWindows() }
    }

    func goHome() {
        guard !isCapturing, !isRecording, !isSelectingRegion else { return }
        result = nil
        recordingResult = nil
        screenshotSaveURL = nil
        recordingSaveURL = nil
        phase = .idle
        toast = nil
        section = .home
        Task { await refreshWindows() }
    }

    func quickSaveScreenshot() {
        guard let result else { return }
        guard let directory = try? ImageWriter.outputDirectory() else {
            alert = AppAlert(title: "保存失败", message: "无法访问默认保存目录。")
            return
        }

        if let source = result.fileURL,
           FileManager.default.fileExists(atPath: source.path),
           Self.isInside(source, directory: directory) {
            screenshotSaveURL = source
            flashToast("已保存到默认位置：图片/长截屏")
            return
        }

        let source = result.fileURL
        let raw = result.rawImage
        let scale = result.backingScale
        let filename = source?.lastPathComponent ?? Self.defaultSaveName(extension: "png")
        let destination = Self.uniqueDestination(in: directory, filename: filename)
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if let source, FileManager.default.fileExists(atPath: source.path) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    } else {
                        try ImageWriter.writePNG(raw, to: destination, backingScale: scale)
                    }
                }.value
                screenshotSaveURL = destination
                flashToast("已保存到默认位置：图片/长截屏")
            } catch {
                alert = AppAlert(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    func quickSaveRecording() {
        guard let result = recordingResult else { return }
        guard let directory = try? ScreenRecorder.outputDirectory() else {
            alert = AppAlert(title: "保存失败", message: "无法访问默认保存目录。")
            return
        }

        if FileManager.default.fileExists(atPath: result.url.path),
           Self.isInside(result.url, directory: directory) {
            recordingSaveURL = result.url
            flashToast("已保存到默认位置：影片/长截屏")
            return
        }

        let destination = Self.uniqueDestination(
            in: directory,
            filename: result.url.lastPathComponent
        )
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.copyItem(at: result.url, to: destination)
                }.value
                recordingSaveURL = destination
                flashToast("已保存到默认位置：影片/长截屏")
            } catch {
                alert = AppAlert(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    func quickSaveCurrentResult() {
        if result != nil {
            quickSaveScreenshot()
        } else if recordingResult != nil {
            quickSaveRecording()
        }
    }

    func saveCurrentResultCopy() {
        if result != nil {
            saveCopy()
        } else if recordingResult != nil {
            saveRecordingCopy()
        }
    }

    func saveRecordingCopy() {
        guard let result = recordingResult else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.directoryURL = (recordingSaveURL ?? result.url).deletingLastPathComponent()
        panel.nameFieldStringValue = (recordingSaveURL ?? result.url).lastPathComponent
        panel.title = "选择保存位置"
        panel.prompt = "保存"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if url.standardizedFileURL == result.url.standardizedFileURL {
            recordingSaveURL = url
            flashToast("已保存到 \(url.lastPathComponent)")
            return
        }

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.copyItem(at: result.url, to: url)
                }.value
                recordingSaveURL = url
                flashToast("已保存到 \(url.lastPathComponent)")
            } catch {
                alert = AppAlert(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    func saveCopy() {
        guard let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = (screenshotSaveURL ?? result.fileURL)?.deletingLastPathComponent()
        panel.nameFieldStringValue = (screenshotSaveURL ?? result.fileURL)?.lastPathComponent
            ?? "截屏.png"
        panel.title = "选择保存位置"
        panel.prompt = "保存"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        if let source = result.fileURL,
           url.standardizedFileURL == source.standardizedFileURL {
            screenshotSaveURL = url
            flashToast("已保存到 \(url.lastPathComponent)")
            return
        }

        if let source = result.fileURL {
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        if FileManager.default.fileExists(atPath: url.path) {
                            try FileManager.default.removeItem(at: url)
                        }
                        try FileManager.default.copyItem(at: source, to: url)
                    }.value
                    screenshotSaveURL = url
                    flashToast("已保存到 \(url.lastPathComponent)")
                } catch {
                    alert = AppAlert(title: "保存失败", message: error.localizedDescription)
                }
            }
            return
        }

        let raw = result.rawImage
        let scale = result.backingScale
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try ImageWriter.writePNG(raw, to: url, backingScale: scale)
                }.value
                screenshotSaveURL = url
                flashToast("已保存到 \(url.lastPathComponent)")
            } catch {
                alert = AppAlert(title: "保存失败", message: error.localizedDescription)
            }
        }
    }

    func exportSegments() {
        guard let result, !isExportingSegments else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "导出到这里"
        panel.message = "选择保存位置，应用会在其中创建“_上传分段”文件夹"
        panel.title = "选择分段导出位置"

        let remembered = UserDefaults.standard.string(forKey: "lastSegmentExportDirectory")
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let remembered, FileManager.default.fileExists(atPath: remembered.path) {
            panel.directoryURL = remembered
        } else if let source = result.fileURL {
            panel.directoryURL = source.deletingLastPathComponent()
        } else {
            panel.directoryURL = try? ImageWriter.outputDirectory()
        }

        guard panel.runModal() == .OK, let parentDirectory = panel.url else { return }
        UserDefaults.standard.set(parentDirectory.path, forKey: "lastSegmentExportDirectory")

        isExportingSegments = true
        segmentExportProgress = 0
        let raw = result.rawImage
        let sourceURL = result.fileURL
        let scale = result.backingScale
        Task {
            do {
                let export = try await Task.detached(priority: .userInitiated) {
                    try ImageWriter.exportSegments(
                        raw,
                        sourceURL: sourceURL,
                        parentDirectory: parentDirectory,
                        backingScale: scale
                    ) { progress, _ in
                        Task { @MainActor in
                            self.segmentExportProgress = progress
                        }
                    }
                }.value
                isExportingSegments = false
                segmentExportProgress = 1
                toast = "已导出 \(export.count) 段，每段约 \(export.segmentHeight) px 高"
                NSWorkspace.shared.activateFileViewerSelecting([export.directory])
            } catch {
                isExportingSegments = false
                alert = AppAlert(title: "分段导出失败", message: error.localizedDescription)
            }
        }
    }

    func copyToClipboard() {
        guard let result else { return }
        guard let url = screenshotSaveURL ?? result.fileURL else {
            alert = AppAlert(
                title: "无法复制",
                message: "当前图片文件不存在。请使用“浏览…”重新保存后再复制。"
            )
            return
        }
        let maxBytes: Int64 = 600 * 1024 * 1024
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size <= maxBytes else {
            alert = AppAlert(
                title: "图片过大，未复制",
                message: "这张长图约 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))，剪贴板无法可靠承载。请使用“浏览…”或直接分享 PNG 文件。"
            )
            return
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            flashToast("已复制到剪贴板")
        } catch {
            alert = AppAlert(title: "复制失败", message: error.localizedDescription)
        }
    }

    func revealInFinder() {
        guard let url = screenshotSaveURL ?? result?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openOutputFolder() {
        if let url = result?.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        if let recording = recordingResult {
            NSWorkspace.shared.activateFileViewerSelecting([recording.url])
            return
        }
        if let directory = try? ImageWriter.outputDirectory() {
            NSWorkspace.shared.open(directory)
        }
    }

    func dismissAlert() {
        alert = nil
    }

    private static func isInside(_ url: URL, directory: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let directoryPath = directory.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    private static func uniqueDestination(in directory: URL, filename: String) -> URL {
        let ext = URL(fileURLWithPath: filename).pathExtension
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        var candidate = directory.appendingPathComponent(filename)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
    }

    private static func defaultSaveName(extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return "截录_\(formatter.string(from: Date())).\(ext)"
    }

    private func flashToast(_ text: String) {
        toast = text
        let current = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self, self.toast == current else { return }
            self.toast = nil
        }
    }

    // MARK: - Window visibility

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow()?.makeKeyAndOrderFront(nil)
    }

    private func mainWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter {
            !($0 is NSPanel) && ($0.title == "截录" || $0.canBecomeMain)
        }
        if let titled = candidates.first(where: { $0.title == "截录" }) { return titled }
        return candidates.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private func hideMainWindows() {
        for window in NSApp.windows where !(window is NSPanel) && window.isVisible {
            window.orderOut(nil)
        }
    }

    // MARK: - Persistence

    private func persistSettings() {
        let defaults = UserDefaults.standard
        defaults.set(settings.overlapFraction, forKey: "overlapFraction")
        defaults.set(settings.scrollDelay, forKey: "scrollDelay")
        defaults.set(settings.recordingFPS, forKey: "recordingFPS")
        defaults.set(settings.recordingAudio, forKey: "recordingAudio")
        defaults.set(settings.recordingMicrophone, forKey: "recordingMicrophone")
        defaults.set(settings.allowCompatibilityScroll, forKey: "allowCompatibilityScroll")
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        var loaded = CaptureSettings()
        if defaults.object(forKey: "overlapFraction") != nil {
            loaded.overlapFraction = min(0.75, max(0.45, defaults.double(forKey: "overlapFraction")))
        }
        if defaults.object(forKey: "scrollDelay") != nil {
            loaded.scrollDelay = min(1.2, max(0.30, defaults.double(forKey: "scrollDelay")))
        }
        if defaults.object(forKey: "recordingFPS") != nil {
            loaded.recordingFPS = defaults.integer(forKey: "recordingFPS") == 60 ? 60 : 30
        }
        if defaults.object(forKey: "recordingAudio") != nil {
            loaded.recordingAudio = defaults.bool(forKey: "recordingAudio")
        }
        if defaults.object(forKey: "recordingMicrophone") != nil {
            loaded.recordingMicrophone = defaults.bool(forKey: "recordingMicrophone")
        }
        if defaults.object(forKey: "allowCompatibilityScroll") != nil {
            loaded.allowCompatibilityScroll = defaults.bool(forKey: "allowCompatibilityScroll")
        }
        settings = loaded
    }
}
