import AppKit
import SwiftUI

struct RecordWorkspace: View {
    @EnvironmentObject private var model: AppModel
    @State private var showWindowPicker = false

    private let sourceOptions = [
        TaskSourceOption(id: RecordSourceChoice.window.rawValue, title: "窗口", icon: "macwindow"),
        TaskSourceOption(id: RecordSourceChoice.screen.rawValue, title: "整个屏幕", icon: "display"),
        TaskSourceOption(id: RecordSourceChoice.region.rawValue, title: "框选区域", icon: "viewfinder")
    ]

    private var screenName: String {
        NSApp.keyWindow?.screen?.localizedName ?? NSScreen.main?.localizedName ?? "当前屏幕"
    }

    private var microphoneSupported: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }

    private var actionTitle: String {
        switch model.recordSourceChoice {
        case .window:
            return model.selectedRecordingWindow == nil ? "先选择窗口" : "开始录制"
        case .screen:
            return "开始录制"
        case .region:
            return model.recordingRegion == nil ? "先框选区域" : "开始录制"
        }
    }

    private var targetSummary: String {
        switch model.recordSourceChoice {
        case .window:
            return model.selectedRecordingWindow?.displayTitle ?? "尚未选择窗口"
        case .screen:
            return screenName
        case .region:
            guard let region = model.recordingRegion else { return "尚未框选区域" }
            return "\(region.widthInPoints) × \(region.heightInPoints) pt 区域"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(
                title: "录屏",
                subtitle: "选择范围、目标和录制选项，然后点击右下角开始。",
                onBack: { model.showSection(.home) }
            )

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 15) {
                    TaskStepHeader(number: 1, title: "选择范围", accent: .red)
                    SourceChoiceBar(
                        options: sourceOptions,
                        selectedID: model.recordSourceChoice.rawValue,
                        accent: .red
                    ) { id in
                        if let choice = RecordSourceChoice(rawValue: id) {
                            model.recordSourceChoice = choice
                        }
                    }

                    TaskStepHeader(number: 2, title: "选择目标", accent: .red)
                    targetCard

                    TaskStepHeader(number: 3, title: "设置选项", accent: .red)
                    optionsCard
                }
                .padding(.horizontal, 26)
                .padding(.top, 2)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.automatic)

            TaskActionBar(
                summary: targetSummary,
                detail: "MP4 · 保存到 影片/长截屏",
                actionTitle: actionTitle,
                actionIcon: "record.circle",
                enabled: model.canRecord,
                colors: [
                    Color(red: 0.98, green: 0.25, blue: 0.23),
                    Color(red: 0.90, green: 0.16, blue: 0.35)
                ],
                action: performAction
            )
        }
        .onAppear {
            if model.recordSourceChoice == .window,
               model.selectedRecordingWindow == nil,
               model.recordingRegion == nil {
                model.recordSourceChoice = .screen
            }
        }
        .sheet(isPresented: $showWindowPicker) {
            WindowPickerSheet(
                purpose: .recording,
                selectedID: model.selectedRecordingWindowID
            ) { target in
                model.selectRecordingWindow(target)
            }
            .environmentObject(model)
        }
    }

    private var targetCard: some View {
        switch model.recordSourceChoice {
        case .window:
            let target = model.selectedRecordingWindow
            return TaskTargetCard(
                systemIcon: "macwindow",
                image: target.map { AppIconProvider.icon(for: $0) },
                title: target?.displayTitle ?? "尚未选择窗口",
                detail: target?.subtitle ?? "打开录制窗口选择器，选择一个可见窗口",
                actionTitle: target == nil ? "选择窗口" : "更换",
                accent: .red
            ) {
                showWindowPicker = true
            }

        case .screen:
            return TaskTargetCard(
                systemIcon: "display",
                image: nil,
                title: screenName,
                detail: "包含菜单栏与 Dock",
                badge: "当前屏幕",
                accent: .red
            )

        case .region:
            let region = model.recordingRegion
            return TaskTargetCard(
                systemIcon: "viewfinder",
                image: nil,
                title: region == nil ? "尚未框选区域" : "\(region!.widthInPoints) × \(region!.heightInPoints) pt 区域",
                detail: region == nil
                    ? "在当前显示器上拖出要录制的范围"
                    : "只录制屏幕上这个范围内实际可见的内容",
                actionTitle: region == nil ? "框选区域" : "重新框选",
                accent: .purple
            ) {
                model.startRecordingRegionSelection()
            }
        }
    }

    private var optionsCard: some View {
        TaskOptionsCard {
            HStack(spacing: 18) {
                Text("帧率")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { model.settings.recordingFPS },
                    set: { model.settings.recordingFPS = $0 }
                )) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .controlSize(.small)
                .tint(.red)

                Divider()
                    .frame(height: 26)
                    .opacity(0.55)

                Toggle(isOn: Binding(
                    get: { model.settings.recordingAudio },
                    set: { model.settings.recordingAudio = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("录制系统声音")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("电脑播放的声音")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.red)

                Divider()
                    .frame(height: 26)
                    .opacity(0.55)

                Toggle(isOn: Binding(
                    get: { model.settings.recordingMicrophone },
                    set: { model.settings.recordingMicrophone = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("录制麦克风")
                            .font(.system(size: 10.5, weight: .medium))
                        Text("你说话的声音")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.red)
                .disabled(!microphoneSupported)
                .opacity(microphoneSupported ? 1 : 0.45)
                .help(microphoneSupported ? "同时录制麦克风声音" : "麦克风录制需要 macOS 15 或更高版本")

                Divider()
                    .frame(height: 26)
                    .opacity(0.55)

                HStack(spacing: 6) {
                    Text("倒计时")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { model.settings.recordingCountdown },
                        set: { model.settings.recordingCountdown = $0 }
                    )) {
                        Text("关闭").tag(0)
                        Text("3 秒").tag(3)
                        Text("5 秒").tag(5)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 84)
                    .tint(.red)
                }

                Spacer()
            }
        }
    }

    private func performAction() {
        switch model.recordSourceChoice {
        case .window:
            if model.selectedRecordingWindow == nil {
                showWindowPicker = true
            } else {
                model.startRecordingWindow()
            }
        case .screen:
            model.startRecordingScreen()
        case .region:
            if model.recordingRegion == nil {
                model.startRecordingRegionSelection()
            } else {
                model.startRecordingRegion()
            }
        }
    }
}
