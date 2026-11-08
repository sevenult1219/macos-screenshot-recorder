import AVFoundation
import CoreMedia
import Darwin
import Foundation

/// Remuxes a recording with multiple audio tracks into one video track plus a
/// single mixed AAC track. Video samples are passed through without re-encoding.
enum AudioTrackMixer {
    static func mergeIfNeeded(url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
              audioTracks.count > 1,
              let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return
        }
        let videoFormat = (try? await videoTrack.load(.formatDescriptions))?.first

        await Task.detached(priority: .userInitiated) {
            _ = try? merge(
                url: url,
                asset: asset,
                videoTrack: videoTrack,
                videoFormat: videoFormat,
                audioTracks: audioTracks
            )
        }.value
    }

    private static func merge(
        url: URL,
        asset: AVURLAsset,
        videoTrack: AVAssetTrack,
        videoFormat: CMFormatDescription?,
        audioTracks: [AVAssetTrack]
    ) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".audio-mix-\(UUID().uuidString).mp4")
        defer {
            try? FileManager.default.removeItem(at: temporaryURL)
        }

        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw MixError.readerUnavailable }
        reader.add(videoOutput)

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0.9, at: .zero)
            return parameters
        }
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        )
        audioOutput.audioMix = audioMix
        audioOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(audioOutput) else { throw MixError.readerUnavailable }
        reader.add(audioOutput)

        let writer = try AVAssetWriter(outputURL: temporaryURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: videoFormat
        )
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw MixError.writerUnavailable }
        writer.add(videoInput)

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 160_000
            ]
        )
        audioInput.expectsMediaDataInRealTime = false
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = "系统声音 + 麦克风" as NSString
        title.extendedLanguageTag = "und"
        audioInput.metadata = [title]
        guard writer.canAdd(audioInput) else { throw MixError.writerUnavailable }
        writer.add(audioInput)

        guard reader.startReading(), writer.startWriting() else {
            throw MixError.startFailed
        }
        writer.startSession(atSourceTime: .zero)

        var videoDone = false
        var audioDone = false
        while !videoDone || !audioDone {
            var progressed = false

            if !videoDone, videoInput.isReadyForMoreMediaData {
                if let sample = videoOutput.copyNextSampleBuffer() {
                    guard videoInput.append(sample) else { throw MixError.appendFailed }
                    progressed = true
                } else {
                    videoInput.markAsFinished()
                    videoDone = true
                    progressed = true
                }
            }

            if !audioDone, audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    guard audioInput.append(sample) else { throw MixError.appendFailed }
                    progressed = true
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                    progressed = true
                }
            }

            if reader.status == .failed || writer.status == .failed {
                throw MixError.readWriteFailed
            }
            if !progressed {
                usleep(2_000)
            }
        }

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else { throw MixError.writeFailed }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
    }

    private enum MixError: Error {
        case readerUnavailable
        case writerUnavailable
        case startFailed
        case appendFailed
        case readWriteFailed
        case writeFailed
    }
}
