import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isDropTarget = false

    var body: some View {
        ZStack {
            AppBackground()

            if model.phase == .result, let result = model.result {
                ResultView(result: result)
                    .transition(.opacity)
            } else if let recording = model.recordingResult {
                RecordingResultView(result: recording)
                    .transition(.opacity)
            } else if !model.hasScreenPermission && model.windows.isEmpty {
                PermissionOnboardingView()
            } else {
                WorkspaceView()
            }

            if let toast = model.toast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(toast)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .frame(minWidth: 1_080, minHeight: 720)
        .animation(.easeInOut(duration: 0.20), value: model.toast)
        .onAppear {
            model.onAppear()
            model.openPendingMedia()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaOpenRequested)) { _ in
            model.openPendingMedia()
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
            openDroppedFile(providers)
        }
        .overlay {
            if isDropTarget {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Color.accentColor)
                        Text("松开以查看图片或视频")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .padding(18)
                .allowsHitTesting(false)
            }
        }
        .sheet(item: $model.openedMedia) { media in
            OpenedMediaViewer(media: media)
        }
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("好")) {
                    model.dismissAlert()
                }
            )
        }
    }

    private func openDroppedFile(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            }
            guard let url else { return }
            Task { @MainActor in
                model.openMediaURLs([url])
            }
        }
        return true
    }
}
