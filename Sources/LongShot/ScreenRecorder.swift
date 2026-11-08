import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit

enum RecordingSource {
    case window(WindowTarget)
    case display(displayID: CGDirectDisplayID)
    case region(RegionTarget)
}

struct RecordingResult: Identifiable {
    let id = UUID()
    let url: URL
    let duration: TimeInterval
    let width: Int
    let height: Int
    let fileSize: Int64
    let thumbnail: NSImage?

    init(
        url: URL,
        duration: TimeInterval,
        width: Int,
        height: Int,
        fileSize: Int64,
        thumbnail: NSImage? = nil
    ) {
        self.url = url
        self.duration = duration
        self.width = width
        self.height = height
        self.fileSize = fileSize
        self.thumbnail = thumbnail
    }

    var durationText: String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var dimensionsText: String { "\(width) × \(height)" }

    var fileSizeText: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum RecordingError: Error, LocalizedError {
    case screenUnavailable
    case windowUnavailable
    case writerUnavailable
    case microphoneUnavailable
    case startFailed(String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .screenUnavailable: return "找不到要录制的显示器。"
        case .windowUnavailable: return "所选窗口已关闭或不可见。"
        case .writerUnavailable: return "无法创建录屏文件。"
        case .microphoneUnavailable: return "当前系统不支持麦克风录制，需要 macOS 15 或更高版本。"
        case .startFailed(let message): return "录屏启动失败：\(message)"
        case .noFrames: return "没有收到可编码的画面，录屏未保存。"
        }
    }
}

final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let source: RecordingSource
    private let fps: Int
    private let capturesAudio: Bool
    private let capturesMicrophone: Bool
    private let microphoneFormat: CMAudioFormatDescription?
    private let microphoneSampleRate: Double
    private let microphoneChannels: Int
    private let outputURL: URL
    private let sampleQueue = DispatchQueue(label: "com.seven.longshot.recorder.samples")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var stopping = false
    private let stateLock = NSLock()
    private var startPTS: CMTime?
    private var lastVideoPTS: CMTime?
    private var videoSize = CGSize.zero
    var onError: ((Error) -> Void)?

    init(
        source: RecordingSource,
        fps: Int,
        capturesAudio: Bool,
        capturesMicrophone: Bool,
        outputURL: URL
    ) {
        self.source = source
        self.fps = max(15, min(60, fps))
        self.capturesAudio = capturesAudio
        self.capturesMicrophone = capturesMicrophone
        let microphoneInfo = Self.defaultMicrophoneInfo()
        self.microphoneFormat = microphoneInfo.format
        self.microphoneSampleRate = microphoneInfo.sampleRate
        self.microphoneChannels = microphoneInfo.channels
        self.outputURL = outputURL
        super.init()
    }

    private static func defaultMicrophoneInfo() -> (
        format: CMAudioFormatDescription?,
        sampleRate: Double,
        channels: Int
    ) {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            return (nil, 48_000, 1)
        }
        let format = device.activeFormat.formatDescription
        guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
            return (nil, 48_000, 1)
        }
        let rate = description.mSampleRate > 0 ? description.mSampleRate : 48_000
        let channels = max(1, min(2, Int(description.mChannelsPerFrame)))
        return (format, rate, channels)
    }

    static func outputDirectory() throws -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = movies.appendingPathComponent("长截屏", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func makeOutputURL() throws -> URL {
        let directory = try outputDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let base = "录屏_\(formatter.string(from: Date()))"
        var url = directory.appendingPathComponent("\(base).mp4")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)_\(suffix).mp4")
            suffix += 1
        }
        return url
    }

    func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingError.startFailed(error.localizedDescription)
        }

        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()

        switch source {
        case .window(let target):
            guard let window = content.windows.first(where: { $0.windowID == target.id }) else {
                throw RecordingError.windowUnavailable
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            let width = evenDimension(window.frame.width * scale)
            let height = evenDimension(window.frame.height * scale)
            applyVideoConfiguration(configuration, width: width, height: height)
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true

        case .display(let displayID):
            guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
                throw RecordingError.screenUnavailable
            }
            filter = makeDisplayFilter(display: display, content: content)
            let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            let width = evenDimension(display.frame.width * scale)
            let height = evenDimension(display.frame.height * scale)
            applyVideoConfiguration(configuration, width: width, height: height)
            configuration.showsCursor = true

        case .region(let region):
            guard let display = content.displays.first(where: { $0.displayID == region.displayID })
                ?? content.displays.first(where: { $0.frame.intersects(region.rect) }) else {
                throw RecordingError.screenUnavailable
            }
            filter = makeDisplayFilter(display: display, content: content)
            let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            let relative = CGRect(
                x: max(0, region.rect.minX - display.frame.minX),
                y: max(0, region.rect.minY - display.frame.minY),
                width: min(region.rect.width, display.frame.width),
                height: min(region.rect.height, display.frame.height)
            )
            configuration.sourceRect = relative
            let width = evenDimension(relative.width * scale)
            let height = evenDimension(relative.height * scale)
            applyVideoConfiguration(configuration, width: width, height: height)
            configuration.showsCursor = true
        }

        if capturesAudio {
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            configuration.excludesCurrentProcessAudio = true
        }

        if capturesMicrophone {
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
            } else {
                throw RecordingError.microphoneUnavailable
            }
        }

        videoSize = CGSize(width: configuration.width, height: configuration.height)
        let writer = try makeWriter(
            width: configuration.width,
            height: configuration.height
        )
        guard writer.startWriting() else {
            throw RecordingError.startFailed(writer.error?.localizedDescription ?? "AVAssetWriter 启动失败")
        }
        self.writer = writer

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if capturesAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }
            if capturesMicrophone {
                if #available(macOS 15.0, *) {
                    try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
                }
            }
            try await stream.startCapture()
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw RecordingError.startFailed(error.localizedDescription)
        }
        self.stream = stream
    }

    func stop() async throws -> RecordingResult {
        setStopping()
        if let stream {
            try? await stream.stopCapture()
        }

        var sessionWasStarted = false
        sampleQueue.sync {
            sessionWasStarted = sessionStarted
            videoInput?.markAsFinished()
            if capturesAudio { audioInput?.markAsFinished() }
            if capturesMicrophone { microphoneInput?.markAsFinished() }
        }

        guard let writer else { throw RecordingError.writerUnavailable }
        guard sessionWasStarted else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw RecordingError.noFrames
        }

        if writer.status == .writing {
            await withCheckedContinuation { continuation in
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }
        guard writer.status == .completed else {
            throw RecordingError.startFailed(writer.error?.localizedDescription ?? "录屏写入失败")
        }

        if capturesAudio, capturesMicrophone {
            await AudioTrackMixer.mergeIfNeeded(url: outputURL)
        }

        let duration: TimeInterval
        if let startPTS, let lastVideoPTS {
            duration = max(0, CMTimeGetSeconds(CMTimeSubtract(lastVideoPTS, startPTS)))
        } else {
            duration = 0
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return RecordingResult(
            url: outputURL,
            duration: duration,
            width: Int(videoSize.width),
            height: Int(videoSize.height),
            fileSize: size
        )
    }

    // MARK: - SCStream

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !isStopping, CMSampleBufferIsValid(sampleBuffer) else { return }
        if type == .screen {
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
            if let statusRaw = CMGetAttachment(
                sampleBuffer,
                key: SCStreamFrameInfo.status.rawValue as CFString,
                attachmentModeOut: nil
            ) as? Int,
               let status = SCFrameStatus(rawValue: statusRaw),
               status != .complete {
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !sessionStarted {
                writer?.startSession(atSourceTime: pts)
                sessionStarted = true
                startPTS = pts
            }
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
                lastVideoPTS = pts
            }
        } else if type == .audio, capturesAudio, sessionStarted {
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }
        } else if #available(macOS 15.0, *), type == .microphone, capturesMicrophone, sessionStarted {
            if microphoneInput?.isReadyForMoreMediaData == true {
                microphoneInput?.append(sampleBuffer)
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    // MARK: - Writer

    private func makeDisplayFilter(
        display: SCDisplay,
        content: SCShareableContent
    ) -> SCContentFilter {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = content.applications.filter { $0.processID == ownPID }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == ownPID }
        if ownApplications.isEmpty {
            return SCContentFilter(display: display, excludingWindows: ownWindows)
        }
        return SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
    }

    private func applyVideoConfiguration(_ configuration: SCStreamConfiguration, width: Int, height: Int) {
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.queueDepth = 6
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.scalesToFit = false
    }

    private func makeWriter(width: Int, height: Int) throws -> AVAssetWriter {
        do {
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            let bitrate = max(
                6_000_000,
                min(80_000_000, Int(Double(width * height * fps) * 0.10))
            )
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoMaxKeyFrameIntervalKey: fps * 2,
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoAllowFrameReorderingKey: false
                ]
            ]
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else { throw RecordingError.writerUnavailable }
            writer.add(video)
            videoInput = video

            if capturesAudio {
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 160_000
                ]
                let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audio.expectsMediaDataInRealTime = true
                audio.metadata = [Self.trackTitle("系统声音")]
                if writer.canAdd(audio) {
                    writer.add(audio)
                    audioInput = audio
                }
            }

            if capturesMicrophone {
                let microphoneSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: microphoneSampleRate,
                    AVNumberOfChannelsKey: microphoneChannels,
                    AVEncoderBitRateKey: 96_000
                ]
                let microphone = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: microphoneSettings,
                    sourceFormatHint: microphoneFormat
                )
                microphone.expectsMediaDataInRealTime = true
                microphone.metadata = [Self.trackTitle("麦克风")]
                guard writer.canAdd(microphone) else {
                    throw RecordingError.writerUnavailable
                }
                writer.add(microphone)
                microphoneInput = microphone
            }
            return writer
        } catch let error as RecordingError {
            throw error
        } catch {
            throw RecordingError.startFailed(error.localizedDescription)
        }
    }

    private static func trackTitle(_ title: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = title as NSString
        item.extendedLanguageTag = "und"
        return item
    }

    private func evenDimension(_ value: CGFloat) -> Int {
        let value = max(2, Int(value.rounded()))
        return value - (value % 2)
    }

    private func setStopping() {
        stateLock.lock()
        stopping = true
        stateLock.unlock()
    }

    private var isStopping: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stopping
    }
}
