import AppKit
import SwiftUI

struct OCRResultView: View {
    let result: CaptureResult
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var lineCount = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("识别文字")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(isLoading ? "正在使用本地 Vision 识别…" : "已识别 \(lineCount) 行 · \(text.count) 字")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isLoading, !text.isEmpty {
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                    } label: {
                        Label("复制全部", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button("完成") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().opacity(0.55)

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在识别图片中的文字…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Button("重试") {
                        Task { await recognize() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    Text(text)
                        .font(.system(size: 12.5, design: .default))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                Text("文字识别在本机完成，不会上传图片或文字。")
                Spacer()
                Text("可拖动选择部分文字")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
        .frame(width: 760, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            guard text.isEmpty, !isLoading || errorMessage == nil else { return }
            await recognize()
        }
    }

    private func recognize() async {
        isLoading = true
        errorMessage = nil
        text = ""
        lineCount = 0
        do {
            let image = try result.rawImage.cgImage()
            let recognized = try await OCRService.recognize(cgImage: image)
            text = recognized.text
            lineCount = recognized.lineCount
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
