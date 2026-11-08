import SwiftUI

enum WindowPickerPurpose {
    case screenshot
    case recording

    var title: String {
        self == .screenshot ? "选择截取窗口" : "选择录制窗口"
    }

    var subtitle: String {
        self == .screenshot
            ? "此选择只用于截屏，不会影响录屏的窗口。"
            : "此选择只用于录屏，不会影响截屏的窗口。"
    }

    var accent: Color {
        self == .screenshot ? .accentColor : .red
    }

    var icon: String {
        self == .screenshot ? "camera.viewfinder" : "record.circle"
    }
}

struct WindowPickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let purpose: WindowPickerPurpose
    let selectedID: CGWindowID?
    let onSelect: (WindowTarget) -> Void
    @State private var query = ""

    private var windows: [WindowTarget] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.windows }
        return model.windows.filter {
            $0.appName.localizedCaseInsensitiveContains(needle)
                || $0.title.localizedCaseInsensitiveContains(needle)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(purpose.accent.opacity(0.11))
                            .frame(width: 36, height: 36)
                        Image(systemName: purpose.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(purpose.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(purpose.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(purpose.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await model.refreshWindows() }
                } label: {
                    if model.isLoadingWindows {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.isLoadingWindows)
                .help("刷新窗口列表")

                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)

            HStack {
                Text("\(model.windows.count) 个可见窗口")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    TextField("搜索", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .frame(width: 180, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)

            Divider().opacity(0.5)

            ScrollView(.vertical) {
                if model.isLoadingWindows, windows.isEmpty {
                    VStack(spacing: 10) {
                        Spacer(minLength: 90)
                        ProgressView("正在读取窗口…")
                            .controlSize(.small)
                        Spacer(minLength: 90)
                    }
                    .frame(maxWidth: .infinity)
                } else if windows.isEmpty {
                    VStack(spacing: 10) {
                        Spacer(minLength: 90)
                        Image(systemName: "macwindow.badge.plus")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("没有可用窗口")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("打开一个应用窗口，然后点右上角刷新。")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 90)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(windows) { target in
                            Button {
                                onSelect(target)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.black.opacity(0.13))
                                            .frame(width: 112, height: 72)
                                        if let thumbnail = model.thumbnails[target.id] {
                                            Image(nsImage: thumbnail)
                                                .resizable()
                                                .interpolation(.high)
                                                .scaledToFit()
                                                .padding(4)
                                        } else {
                                            Image(nsImage: AppIconProvider.icon(for: target))
                                                .resizable()
                                                .frame(width: 26, height: 26)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(target.displayTitle)
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .lineLimit(1)
                                        Text(target.subtitle)
                                            .font(.system(size: 9.2))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(selectedID == target.id ? "当前已选择" : "点击选择")
                                            .font(.system(size: 8.8))
                                            .foregroundStyle(
                                                selectedID == target.id
                                                    ? purpose.accent
                                                    : Color(nsColor: .tertiaryLabelColor)
                                            )
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: purpose.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(purpose.accent.opacity(0.65))
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            selectedID == target.id
                                                ? purpose.accent.opacity(0.55)
                                                : Color.primary.opacity(0.07),
                                            lineWidth: selectedID == target.id ? 1.5 : 0.8
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .frame(width: 720, height: 560)
    }
}
