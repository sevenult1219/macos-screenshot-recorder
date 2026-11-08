import SwiftUI

struct ScreenshotWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var showWindowPicker = false
    @State private var showSettings = false

    private let sourceOptions = [
        TaskSourceOption(id: ScreenshotSource.window.rawValue, title: "窗口", icon: "macwindow"),
        TaskSourceOption(id: ScreenshotSource.region.rawValue, title: "框选区域", icon: "viewfinder")
    ]

    private var actionTitle: String {
        if model.screenshotSource == .window, model.selectedScreenshotWindow == nil {
            return "先选择窗口"
        }
        if model.screenshotSource == .region, model.screenshotRegion == nil {
            return "先框选区域"
        }
        if model.screenshotMode == .normal {
            return model.screenshotSource == .window ? "截取窗口" : "截取区域"
        }
        return "开始长截屏"
    }

    private var actionIcon: String {
        model.screenshotMode == .normal ? "camera" : "arrow.down.to.line"
    }

    private var actionEnabled: Bool {
        guard model.hasScreenPermission,
              !model.isCapturing,
              !model.isRecording,
              !model.isSelectingRegion else { return false }
        if model.screenshotMode == .long, !model.hasAccessibilityPermission { return false }
        return true
    }

    private var targetSummary: String {
        switch model.screenshotSource {
        case .window:
            return model.selectedScreenshotWindow?.displayTitle ?? "尚未选择窗口"
        case .region:
            guard let region = model.screenshotRegion else { return "尚未框选区域" }
            return "\(region.widthInPoints) × \(region.heightInPoints) pt 区域"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "截屏",
                subtitle: "选择范围、目标和截取方式，然后点击右下角开始。",
                onBack: { model.showSection(.home) }
            )

            if model.screenshotMode == .long, !model.hasAccessibilityPermission {
                AccessPermissionBanner()
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 15) {
                    TaskStepHeader(number: 1, title: "选择范围")
                    SourceChoiceBar(
                        options: sourceOptions,
                        selectedID: model.screenshotSource.rawValue,
                        accent: .accentColor
                    ) { id in
                        if let source = ScreenshotSource(rawValue: id) {
                            model.screenshotSource = source
                        }
                    }

                    TaskStepHeader(number: 2, title: "选择目标")
                    targetCard

                    TaskStepHeader(number: 3, title: "设置选项")
                    optionsCard
                }
                .padding(.horizontal, 26)
                .padding(.top, 2)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.automatic)

            TaskActionBar(
                summary: targetSummary,
                detail: "\(model.screenshotMode.title) · 保存到 图片/长截屏",
                actionTitle: actionTitle,
                actionIcon: actionIcon,
                enabled: actionEnabled,
                colors: [
                    Color(red: 0.16, green: 0.46, blue: 1.0),
                    Color(red: 0.45, green: 0.30, blue: 0.96)
                ],
                action: performAction
            )
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerSheet(
                purpose: .screenshot,
                selectedID: model.selectedScreenshotWindowID
            ) { target in
                model.selectScreenshotWindow(target)
            }
            .environmentObject(model)
        }
    }

    private var targetCard: some View {
        switch model.screenshotSource {
        case .window:
            let target = model.selectedScreenshotWindow
            return TaskTargetCard(
                systemIcon: "macwindow",
                image: target.map { AppIconProvider.icon(for: $0) },
                title: target?.displayTitle ?? "尚未选择窗口",
                detail: target?.subtitle ?? "打开窗口选择器，选择一个可见窗口",
                actionTitle: target == nil ? "选择窗口" : "更换",
                accent: .accentColor
            ) {
                showWindowPicker = true
            }
        case .region:
            let region = model.screenshotRegion
            return TaskTargetCard(
                systemIcon: "viewfinder",
                image: nil,
                title: region == nil ? "尚未框选区域" : "\(region!.widthInPoints) × \(region!.heightInPoints) pt 区域",
                detail: region == nil
                    ? "在当前显示器上拖出要截取的范围"
                    : "普通截屏截取这一块；长截屏会从这一块自动滚动",
                actionTitle: region == nil ? "框选区域" : "重新框选",
                accent: .purple
            ) {
                model.startScreenshotRegionSelection()
            }
        }
    }

    private var optionsCard: some View {
        TaskOptionsCard {
            HStack(spacing: 14) {
                Text("截取方式")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $model.screenshotMode) {
                    ForEach(ScreenshotMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .controlSize(.small)
                Spacer()
            }

            if model.screenshotMode == .long {
                Divider().opacity(0.55)
                HStack(spacing: 8) {
                    Text("重叠 \(Int((model.settings.overlapFraction * 100).rounded()))%")
                        .font(.system(size: 9.8, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(String(format: "等待 %.2f 秒", model.settings.scrollDelay))
                        .font(.system(size: 9.8, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("调整…") {
                        showSettings.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                        ScreenshotSettingsPopover()
                            .environmentObject(model)
                    }
                }

                HStack(spacing: 5) {
                    Image(systemName: "cursorarrow")
                    Text("长截屏优先定向滚动；必要时使用兼容滚动，不会移动鼠标")
                }
                .font(.system(size: 9.2))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func performAction() {
        if model.screenshotSource == .window, model.selectedScreenshotWindow == nil {
            showWindowPicker = true
            return
        }
        if model.screenshotSource == .region, model.screenshotRegion == nil {
            model.startScreenshotRegionSelection()
            return
        }
        model.startScreenshot()
    }
}
