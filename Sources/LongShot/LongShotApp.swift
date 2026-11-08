import AppKit
import LongShotCore
import SwiftUI

@main
struct LongShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("截录", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .defaultSize(width: 1_180, height: 800)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .newItem) {
                Button("打开图片或视频…") {
                    model.presentMediaOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("截屏") {
                Button("执行截屏") {
                    model.startScreenshot()
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!model.canStartScreenshot)

                Button("选择框选区域") {
                    model.screenshotSource = .region
                    model.startScreenshotRegionSelection()
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])
                .disabled(!model.canSelectRegion)

                Divider()

                Button("录制所选窗口") {
                    model.startRecordingWindow()
                }
                .keyboardShortcut("3", modifiers: [.command, .shift])
                .disabled(!model.canRecord || model.selectedRecordingWindow == nil)

                Button("录制整个屏幕") {
                    model.startRecordingScreen()
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])
                .disabled(!model.canRecord)

                Button("框选录制区域") {
                    model.startRecordingRegionSelection()
                }
                .keyboardShortcut("5", modifiers: [.command, .shift])
                .disabled(!model.canRecord)

                Divider()

                Button("停止截屏") {
                    model.stopCapture()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.isCapturing)

                Button("停止录屏") {
                    model.stopRecording()
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .disabled(!model.isRecording)

                Divider()

                Button("刷新窗口列表") {
                    Task { await model.refreshWindows() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isCapturing)

                Button("快速保存到默认位置") {
                    model.quickSaveCurrentResult()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(model.result == nil && model.recordingResult == nil)

                Button("浏览…") {
                    model.saveCurrentResultCopy()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.result == nil && model.recordingResult == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MediaOpenCenter.shared.enqueue(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        RawImageFile.cleanupStaleTemporaryFiles()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            for window in NSApp.windows where window.canBecomeMain {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
                window.isOpaque = false
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        RawImageFile.cleanupAllTemporaryFiles()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            for window in sender.windows
            where !(window is NSPanel) && (window.title == "截录" || window.canBecomeMain) {
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
        return true
    }
}
