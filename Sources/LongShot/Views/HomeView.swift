import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    private var grantedCount: Int {
        (model.hasScreenPermission ? 1 : 0) + (model.hasAccessibilityPermission ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                LogoMark()
                    .frame(width: 44, height: 44)
                Text("截录")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Spacer()

                Button {
                    model.presentMediaOpenPanel()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                        Text("打开媒体")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.primary.opacity(0.045)))
                }
                .buttonStyle(.plain)
                .help("打开图片或视频")

                PermissionSummaryButton(grantedCount: grantedCount)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)

            Spacer(minLength: 26)

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("你想做什么？")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("选择一个任务。下一步只显示需要的选项，完成后可以随时返回这里。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    HomeTaskCard(
                        icon: "camera.viewfinder",
                        color: .blue,
                        title: "截屏",
                        detail: "截取一个窗口或框选区域，支持普通截屏和自动滚动长截图。",
                        bullets: ["窗口 / 框选区域", "普通截屏 / 长截屏", "无损 PNG"],
                        actionTitle: "打开截屏"
                    ) {
                        model.showSection(.screenshot)
                    }

                    HomeTaskCard(
                        icon: "record.circle",
                        color: .red,
                        title: "录屏",
                        detail: "录制一个窗口、整个屏幕，或只录框选的区域。",
                        bullets: ["窗口 / 全屏 / 区域", "30 / 60 fps", "MP4"],
                        actionTitle: "打开录屏"
                    ) {
                        model.showSection(.record)
                    }
                }
                .frame(maxWidth: 920)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)
        }
        .padding(.bottom, 22)
    }
}

private struct HomeTaskCard: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let bullets: [String]
    let actionTitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.11))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.top, 16)

                Text(detail)
                    .font(.system(size: 10.8))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)

                VStack(alignment: .leading, spacing: 5) {
                    ForEach(bullets, id: \.self) { bullet in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(color.opacity(0.55))
                                .frame(width: 3.5, height: 3.5)
                            Text(bullet)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 10)

                HStack(spacing: 5) {
                    Text(actionTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9.5, weight: .bold))
                }
                .foregroundStyle(color)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .frame(height: 310, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 0.95 : 0.70))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        hovering ? color.opacity(0.30) : Color.primary.opacity(0.065),
                        lineWidth: hovering ? 1.2 : 0.8
                    )
            )
            .shadow(
                color: color.opacity(hovering ? 0.10 : 0.0),
                radius: 12,
                y: 6
            )
            .scaleEffect(hovering ? 1.004 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct PermissionSummaryButton: View {
    @EnvironmentObject private var model: AppModel
    let grantedCount: Int
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: grantedCount == 2 ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(grantedCount == 2 ? Color.green : Color.orange)
                Text(grantedCount == 2 ? "权限正常" : "权限 \(grantedCount)/2")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.045)))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            PermissionPopover()
                .environmentObject(model)
        }
    }
}

private struct PermissionPopover: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("权限设置")
                .font(.system(size: 14, weight: .semibold))
            Text("屏幕录制用于读取窗口画面；辅助功能用于自动滚动。麦克风为可选权限，仅在开启麦克风录制时使用。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            PermissionRow(
                title: "屏幕录制",
                detail: "读取窗口与屏幕",
                granted: model.hasScreenPermission
            ) {
                model.requestScreenPermission()
            }
            PermissionRow(
                title: "辅助功能",
                detail: "自动滚动窗口",
                granted: model.hasAccessibilityPermission
            ) {
                model.requestAccessibilityPermission()
            }
            PermissionRow(
                title: "麦克风",
                detail: "录屏时录制你的声音（可选）",
                granted: model.hasMicrophonePermission
            ) {
                model.requestMicrophonePermission()
            }
        }
        .padding(18)
        .frame(width: 300)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if granted {
                Text("已开启")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            } else {
                Button("授权") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
