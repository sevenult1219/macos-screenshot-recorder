import AppKit
import SwiftUI

struct RecordingResultView: View {
    @EnvironmentObject private var model: AppModel
    let result: RecordingResult

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(alignment: .top, spacing: 18) {
                VideoPlayerPanel(
                    url: result.url,
                    thumbnail: result.thumbnail,
                    mixesAudioTracks: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                sidebar
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 22)
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Button {
                model.goHome()
            } label: {
                Label("完成", systemImage: "house")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("录屏已保存")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("\(result.durationText) · \(result.dimensionsText) px · \(result.fileSizeText)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                model.quickSaveRecording()
            } label: {
                Label("快速保存", systemImage: "arrow.down.circle")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .help("立即保存一份到“下载”文件夹")

            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("已自动保存")
            }
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.green.opacity(0.09)))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("视频信息")
                    .font(.system(size: 12.5, weight: .semibold))

                VStack(spacing: 9) {
                    RecordingInfoRow(label: "时长", value: result.durationText, mono: true)
                    RecordingInfoRow(label: "尺寸", value: "\(result.dimensionsText) px", mono: true)
                    RecordingInfoRow(label: "体积", value: result.fileSizeText, mono: false)
                    RecordingInfoRow(label: "格式", value: "MP4 · H.264", mono: false)
                    RecordingInfoRow(label: "文件", value: result.url.lastPathComponent, mono: false)
                }

                Divider().opacity(0.6)

                VStack(spacing: 8) {
                    Button {
                        model.quickSaveRecording()
                    } label: {
                        Label("快速保存到下载", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TaskPrimaryButtonStyle(colors: [
                        Color(red: 0.98, green: 0.25, blue: 0.23),
                        Color(red: 0.90, green: 0.16, blue: 0.35)
                    ]))

                    Button {
                        model.saveRecordingCopy()
                    } label: {
                        Label("另存为…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([result.url])
                    } label: {
                        Label("在 Finder 中显示", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        NSWorkspace.shared.open(result.url)
                    } label: {
                        Label("用默认播放器打开", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("录屏已保存到", systemImage: "film")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("影片/长截屏")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Button("打开输出文件夹") {
                        model.openOutputFolder()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10.5))
                }

                Button {
                    model.dismissRecordingResult()
                } label: {
                    Label("再录一段", systemImage: "record.circle")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.red)
                .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct RecordingInfoRow: View {
    let label: String
    let value: String
    let mono: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: mono ? .monospaced : .default))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
