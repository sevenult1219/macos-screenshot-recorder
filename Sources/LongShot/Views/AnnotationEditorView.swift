import AppKit
import SwiftUI

struct AnnotationEditorView: View {
    let result: CaptureResult
    let onSaved: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cgImage: CGImage?
    @State private var previewImage: NSImage?
    @State private var tool: AnnotationTool = .arrow
    @State private var ink: AnnotationInk = .red
    @State private var lineWidth: CGFloat = 4
    @State private var annotations: [ImageAnnotation] = []
    @State private var undoStack: [[ImageAnnotation]] = []
    @State private var redoStack: [[ImageAnnotation]] = []
    @State private var draft: AnnotationDraft?
    @State private var textDraft = "请输入文字"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().opacity(0.55)
            toolBar
            Divider().opacity(0.55)
            canvasArea
            footer
        }
        .frame(width: 1_120, height: 800)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: loadImage)
        .overlay {
            if isSaving {
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView("正在生成原始像素 PNG…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert("标注保存失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Button("取消") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)

            VStack(alignment: .leading, spacing: 1) {
                Text("标注截图")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(result.dimensionsText) · 拖动绘制，标注以原始像素导出")
                    .font(.system(size: 9.8))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(undoStack.isEmpty)
            .help("撤销")

            Button {
                redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(redoStack.isEmpty)
            .help("重做")

            Button {
                clearAll()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(annotations.isEmpty)
            .help("清空标注")

            Button {
                save()
            } label: {
                Label("保存标注副本", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(GradientButtonStyle(verticalPadding: 7))
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(cgImage == nil || isSaving)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 11)
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            ForEach(Array(AnnotationTool.allCases.filter { $0 != .text }.enumerated()), id: \.element) { index, item in
                Button {
                    tool = item
                    draft = nil
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 8.5, weight: .medium))
                    }
                    .frame(width: 43, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tool == item ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(
                                tool == item ? Color.accentColor.opacity(0.40) : Color.primary.opacity(0.06),
                                lineWidth: 0.8
                            )
                    )
                    .foregroundStyle(tool == item ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(
                    KeyEquivalent(Character("\(index + 1)")),
                    modifiers: [.command]
                )
                .help("\(item.title)（⌘\(index + 1)）")
            }

            Divider().frame(height: 24).opacity(0.55)

            HStack(spacing: 5) {
                ForEach(AnnotationInk.allCases) { item in
                    Button {
                        ink = item
                    } label: {
                        Circle()
                            .fill(Color(nsColor: item.color))
                            .frame(width: 15, height: 15)
                            .overlay(
                                Circle().strokeBorder(
                                    ink == item ? Color.primary.opacity(0.9) : Color.primary.opacity(0.16),
                                    lineWidth: ink == item ? 1.6 : 0.7
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(item.label)
                }
            }

            Divider().frame(height: 24).opacity(0.55)

            HStack(spacing: 7) {
                Image(systemName: "lineweight")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 2...12, step: 1)
                    .frame(width: 78)
                    .controlSize(.mini)
                Text("\(Int(lineWidth))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 17)
            }

            Spacer()

            Text("原图像素")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    private var canvasArea: some View {
        GeometryReader { proxy in
            let availableWidth = max(320, proxy.size.width - 48)
            let scale = min(1, availableWidth / CGFloat(max(1, result.width)))
            let displayWidth = CGFloat(result.width) * scale
            let displayHeight = CGFloat(result.height) * scale

            ScrollView([.vertical, .horizontal]) {
                ZStack(alignment: .topLeading) {
                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: displayWidth, height: displayHeight)
                    } else {
                        ProgressView("正在加载图片…")
                            .frame(width: displayWidth, height: min(displayHeight, 400))
                    }

                    Canvas { context, _ in
                        for annotation in annotations {
                            drawPreview(annotation, in: &context, scale: scale)
                        }
                        if let draft,
                           let preview = draftAnnotation(draft) {
                            drawPreview(preview, in: &context, scale: scale)
                        }
                    }
                    .frame(width: displayWidth, height: displayHeight)
                    .contentShape(Rectangle())
                    .gesture(drawingGesture(scale: scale))
                }
                .frame(width: displayWidth, height: displayHeight)
                .padding(24)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
            Text("箭头/矩形/遮挡/画笔：在图片上拖动绘制。遮挡使用不透明黑色覆盖。")
            Spacer()
            Text("\(annotations.count) 个标注")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 9.6))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private func loadImage() {
        guard cgImage == nil else { return }
        guard let image = try? result.rawImage.cgImage() else { return }
        cgImage = image
        previewImage = NSImage(
            cgImage: image,
            size: NSSize(width: result.width, height: result.height)
        )
    }

    private func drawingGesture(scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard cgImage != nil else { return }
                let point = imagePoint(value.location, scale: scale)
                if draft == nil {
                    draft = AnnotationDraft(
                        tool: tool,
                        start: point,
                        current: point,
                        points: [point]
                    )
                } else {
                    draft?.current = point
                    if draft?.tool == .pen {
                        draft?.points.append(point)
                    }
                }
            }
            .onEnded { value in
                let point = imagePoint(value.location, scale: scale)
                let endedTool = draft?.tool ?? tool
                if endedTool == .text {
                    let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        add(ImageAnnotation(
                            kind: .text(point, text),
                            ink: ink,
                            lineWidth: lineWidth
                        ))
                    }
                    self.draft = nil
                    return
                }
                guard var draft else { return }
                draft.current = point
                if draft.tool == .pen, draft.points.count > 1 {
                    add(ImageAnnotation(
                        kind: .pen(draft.points),
                        ink: ink,
                        lineWidth: lineWidth
                    ))
                } else if draft.rect.width > 3 || draft.rect.height > 3 {
                    switch draft.tool {
                    case .arrow:
                        add(ImageAnnotation(
                            kind: .arrow(from: draft.start, to: draft.current),
                            ink: ink,
                            lineWidth: lineWidth
                        ))
                    case .rectangle:
                        add(ImageAnnotation(
                            kind: .rectangle(draft.rect),
                            ink: ink,
                            lineWidth: lineWidth
                        ))
                    case .redact:
                        add(ImageAnnotation(
                            kind: .redact(draft.rect),
                            ink: .black,
                            lineWidth: lineWidth
                        ))
                    default:
                        break
                    }
                }
                self.draft = nil
            }
    }

    private func imagePoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        let safeScale = max(0.0001, scale)
        return CGPoint(
            x: min(max(0, point.x / safeScale), CGFloat(result.width)),
            y: min(max(0, point.y / safeScale), CGFloat(result.height))
        )
    }

    private func add(_ annotation: ImageAnnotation) {
        undoStack.append(annotations)
        annotations.append(annotation)
        redoStack.removeAll()
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    private func clearAll() {
        guard !annotations.isEmpty else { return }
        undoStack.append(annotations)
        annotations = []
        redoStack.removeAll()
    }

    private func draftAnnotation(_ draft: AnnotationDraft) -> ImageAnnotation? {
        switch draft.tool {
        case .arrow:
            return ImageAnnotation(
                kind: .arrow(from: draft.start, to: draft.current),
                ink: ink,
                lineWidth: lineWidth
            )
        case .rectangle:
            return ImageAnnotation(
                kind: .rectangle(draft.rect),
                ink: ink,
                lineWidth: lineWidth
            )
        case .redact:
            return ImageAnnotation(
                kind: .redact(draft.rect),
                ink: .black,
                lineWidth: lineWidth
            )
        case .pen:
            guard draft.points.count > 1 else { return nil }
            return ImageAnnotation(
                kind: .pen(draft.points),
                ink: ink,
                lineWidth: lineWidth
            )
        case .text:
            return nil
        }
    }

    private func drawPreview(
        _ annotation: ImageAnnotation,
        in context: inout GraphicsContext,
        scale: CGFloat
    ) {
        let color = annotation.ink == .black && isRedact(annotation)
            ? Color.black
            : Color(nsColor: annotation.ink.color)
        let width = max(1, annotation.lineWidth * scale)

        switch annotation.kind {
        case .arrow(let start, let end):
            var path = Path()
            path.move(to: previewPoint(start, scale: scale))
            path.addLine(to: previewPoint(end, scale: scale))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )

            let from = previewPoint(start, scale: scale)
            let to = previewPoint(end, scale: scale)
            let angle = atan2(to.y - from.y, to.x - from.x)
            let headLength = max(8, width * 3.8)
            let headAngle = CGFloat.pi / 7
            var head = Path()
            head.move(to: CGPoint(
                x: to.x - headLength * cos(angle - headAngle),
                y: to.y - headLength * sin(angle - headAngle)
            ))
            head.addLine(to: to)
            head.addLine(to: CGPoint(
                x: to.x - headLength * cos(angle + headAngle),
                y: to.y - headLength * sin(angle + headAngle)
            ))
            context.stroke(
                head,
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )

        case .rectangle(let rect):
            let display = previewRect(rect, scale: scale)
            context.stroke(
                Path(display),
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineJoin: .round)
            )

        case .redact(let rect):
            context.fill(Path(previewRect(rect, scale: scale)), with: .color(.black))

        case .pen(let points):
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: previewPoint(first, scale: scale))
            for point in points.dropFirst() {
                path.addLine(to: previewPoint(point, scale: scale))
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            )

        case .text(let point, let text):
            guard !text.isEmpty else { return }
            context.draw(
                Text(text)
                    .font(.system(size: annotation.fontSize * scale, weight: .semibold))
                    .foregroundColor(color),
                at: previewPoint(point, scale: scale),
                anchor: .topLeading
            )
        }
    }

    private func isRedact(_ annotation: ImageAnnotation) -> Bool {
        if case .redact = annotation.kind { return true }
        return false
    }

    private func previewPoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    private func previewRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func save() {
        guard let cgImage else { return }
        let directory: URL
        do {
            directory = try ImageWriter.outputDirectory()
        } catch {
            errorMessage = "无法访问“图片/长截屏”目录：\(error.localizedDescription)"
            return
        }

        let base = result.fileURL?.deletingPathExtension().lastPathComponent ?? "截图"
        var url = directory.appendingPathComponent("\(base)_标注.png")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)_标注_\(suffix).png")
            suffix += 1
        }

        isSaving = true
        let annotations = self.annotations
        let size = CGSize(width: result.width, height: result.height)
        DispatchQueue.main.async {
            do {
                let data = try AnnotationRenderer.pngData(
                    image: cgImage,
                    pixelSize: size,
                    annotations: annotations
                )
                try data.write(to: url, options: .atomic)
                isSaving = false
                onSaved(url)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
