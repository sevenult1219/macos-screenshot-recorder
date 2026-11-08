import AppKit
import SwiftUI

struct OpenedMediaViewer: View {
    let media: OpenedMedia
    @Environment(\.dismiss) private var dismiss
    @State private var imageMode: PreviewMode = .fitWidth

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(width: media.isVideo ? 920 : 1_040, height: media.isVideo ? 680 : 740)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((media.isVideo ? Color.red : Color.accentColor).opacity(0.11))
                    .frame(width: 36, height: 36)
                Image(systemName: media.isVideo ? "film" : "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(media.isVideo ? Color.red : Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(media.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(media.url.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(media.detailText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !media.isVideo {
                Picker("", selection: $imageMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 210)
            }

            Button("完成") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch media.kind {
        case .image(let rawImage, _):
            TiledImagePreview(rawImage: rawImage, mode: imageMode)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 22)
        case .video(let url):
            VideoPlayerPanel(url: url, thumbnail: nil)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 22)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([media.url])
            } label: {
                Label("在 Finder 中显示", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                NSWorkspace.shared.open(media.url)
            } label: {
                Label(media.isVideo ? "用默认播放器打开" : "用默认应用打开", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Text(media.url.deletingLastPathComponent().path)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }
}
