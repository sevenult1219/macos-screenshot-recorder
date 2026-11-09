import SwiftUI

struct ResultView: View {
    @EnvironmentObject private var model: AppModel
    let result: CaptureResult
    @State private var showImagePreview = false
    @State private var showAnnotationEditor = false
    @State private var showOCR = false
    @State private var previewMode: PreviewMode = .fitWidth

    var body: some View {
        VStack(spacing: 0) {
            header

            if shouldSuggestSegments {
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: "rectangle.split.3x1.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("整张上传会被压缩到约 \(scaledForChatGPTWidth) × 2,047 px")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("ChatGPT 等平台会按最长边缩放。使用“导出上传分段”可保持 \(result.width) px 原始宽度和文字清晰度。")
                            .font(.system(size: 10.2))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(model.isExportingSegments ? "正在导出…" : "导出分段") {
                        model.exportSegments()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.isExportingSegments)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 0.8)
                        )
                )
                .padding(.horizontal, 26)
                .padding(.bottom, 4)
            }

            if let warning = result.warning {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.16), lineWidth: 0.8)
                        )
                )
                .padding(.horizontal, 26)
                .padding(.bottom, 4)
            }

            HStack(alignment: .top, spacing: 18) {
                preview
                sidebar
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .sheet(isPresented: $showImagePreview) {
            ImagePreviewSheet(result: result)
        }
        .sheet(isPresented: $showAnnotationEditor) {
            AnnotationEditorView(result: result) { url in
                model.showToast("已保存标注副本：\(url.lastPathComponent)")
            }
        }
        .sheet(isPresented: $showOCR) {
            OCRResultView(result: result)
        }
    }

    private var shouldSuggestSegments: Bool {
        !result.isSingleShot && result.height > 4_096
    }

    private var scaledForChatGPTWidth: Int {
        max(1, Int((Double(result.width) * 2_047.0 / Double(result.height)).rounded()))
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
                Text(result.isSingleShot ? "截图已保存" : "长截图已生成")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(result.isSingleShot
                     ? "\(result.dimensionsText) · 无损 PNG · 原始像素"
                     : "\(result.dimensionsText) · \(result.screens) 屏 · 无损 PNG · 原始像素")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showAnnotationEditor = true
            } label: {
                Label("标注", systemImage: "pencil.tip.crop.circle")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("e", modifiers: [.command])

            Button {
                showOCR = true
            } label: {
                Label("文字", systemImage: "text.viewfinder")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                showImagePreview = true
            } label: {
                Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if result.fileURL != nil {
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
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("预览")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.7)
                Spacer()
                Picker("", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 210)
                .help("“100%”按屏幕像素 1:1 显示；“200%”可进一步检查文字锐度")
            }

            TiledImagePreview(rawImage: result.rawImage, mode: previewMode)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
            Text("图片信息")
                .font(.system(size: 12.5, weight: .semibold))

            VStack(spacing: 9) {
                InfoRow(label: "尺寸", value: result.dimensionsText, mono: true)
                InfoRow(label: "包含", value: result.isSingleShot ? "1 张" : "\(result.screens) 屏", mono: false)
                InfoRow(label: "画质", value: "原始像素 · 无损", mono: false)
                InfoRow(label: "格式", value: "PNG", mono: false)
                if !result.fileSizeText.isEmpty {
                    InfoRow(label: "体积", value: result.fileSizeText, mono: false)
                }
                if let url = result.fileURL {
                    InfoRow(label: "文件", value: url.lastPathComponent, mono: false)
                }
            }

            if let url = result.fileURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(url.deletingLastPathComponent().lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 9.8))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    )
                }
                .buttonStyle(.plain)
                .help("在 Finder 中显示")
            }

            Divider().opacity(0.6)

            VStack(spacing: 8) {
                Button {
                    model.quickSaveScreenshot()
                } label: {
                    Label("快速保存", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GradientButtonStyle(verticalPadding: 10))
                .help("保存到默认目录：图片/长截屏")

                Button {
                    model.saveCopy()
                } label: {
                    Label("浏览…", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("显示并更改文件位置")

                VStack(alignment: .leading, spacing: 4) {
                    Text("文件位置")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(model.screenshotSaveURL?.path ?? "尚未保存")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.vertical, 2)

                if !result.isSingleShot {
                    Button {
                        model.exportSegments()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.split.3x1")
                            Text(model.isExportingSegments
                                 ? "正在导出 \(Int((model.segmentExportProgress * 100).rounded()))%…"
                                 : "导出上传分段")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(model.isExportingSegments)
                    .help("选择保存位置，按约 2000 px 高度拆分为多张原始宽度 PNG，适合上传 ChatGPT 等平台")
                }

                Button {
                    model.pinCurrentScreenshot()
                } label: {
                    Label("贴图到屏幕", systemImage: "pin")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .help("将截图固定在屏幕上，始终置顶（⌘⇧P）")

                Button {
                    model.copyToClipboard()
                } label: {
                    Label("拷贝到剪贴板", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    model.revealInFinder()
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(model.screenshotSaveURL == nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("默认输出目录", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("图片/长截屏")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Button("打开输出文件夹") {
                    model.openOutputFolder()
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }

            Button {
                model.restart()
            } label: {
                Label("再截一张", systemImage: "plus.viewfinder")
                    .font(.system(size: 11.5, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
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

private struct InfoRow: View {
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
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}
