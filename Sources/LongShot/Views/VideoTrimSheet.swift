import AppKit
import SwiftUI

struct VideoTrimSheet: View {
    let result: RecordingResult
    let onExported: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start: Double = 0
    @State private var end: Double = 0
    @State private var isExporting = false
    @State private var errorMessage: String?

    private var duration: Double {
        max(0.2, result.duration)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.red.opacity(0.10))
                        .frame(width: 36, height: 36)
                    Image(systemName: "scissors")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("裁剪视频")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("只导出选中区间，原视频不会被修改")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 16) {
                if let thumbnail = result.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                rangeRow(
                    title: "开始",
                    binding: $start,
                    range: 0...max(0.1, duration - 0.2)
                )
                rangeRow(
                    title: "结束",
                    binding: $end,
                    range: min(0.2, duration)...duration
                )

                HStack {
                    Text("导出区间")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(timeText(start)) – \(timeText(end))  ·  \(timeText(max(0, end - start)))")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text("导出到 影片/长截屏")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        Task { await export() }
                    } label: {
                        Label(isExporting ? "正在导出…" : "导出裁剪副本", systemImage: "scissors")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .buttonStyle(GradientButtonStyle(verticalPadding: 8))
                    .disabled(isExporting)
                }
            }
            .padding(22)
        }
        .frame(width: 580, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            start = 0
            end = duration
        }
        .onChange(of: start) { _, newValue in
            if newValue > end - 0.2 { start = max(0, end - 0.2) }
        }
        .onChange(of: end) { _, newValue in
            if newValue < start + 0.2 { end = min(duration, start + 0.2) }
        }
    }

    private func rangeRow(
        title: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Text(timeText(binding.wrappedValue))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range)
                .tint(.red)
                .controlSize(.small)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func export() async {
        isExporting = true
        errorMessage = nil
        do {
            let url = try await VideoTrimmer.export(
                source: result.url,
                start: start,
                end: end
            )
            isExporting = false
            onExported(url)
            dismiss()
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }
}
