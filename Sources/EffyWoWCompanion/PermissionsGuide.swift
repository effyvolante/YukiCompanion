import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI

@MainActor
final class PermissionStatus: ObservableObject {
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    private var timer: Timer?

    init() { refresh() }

    func refresh() {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class PermissionsWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionsWindowController()
    let status = PermissionStatus()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let permissionsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            permissionsWindow.title = "Yuki Companion Permissions"
            permissionsWindow.isReleasedWhenClosed = false
            permissionsWindow.delegate = self
            permissionsWindow.contentView = NSHostingView(rootView: PermissionsGuideView(status: status))
            window = permissionsWindow
        }
        status.startMonitoring()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        status.stopMonitoring()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        status.stopMonitoring()
    }
}

@MainActor
private struct PermissionsGuideView: View {
    @ObservedObject var status: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Yuki Companion Permissions")
                .font(.largeTitle.bold())
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.78))
            Text("Yuki needs your approval before macOS will let her use these protected features. The checkboxes below update automatically while you change the settings.")
                .foregroundStyle(.secondary)

            PermissionRow(
                title: "Accessibility",
                detail: "Used for keyboard-assisted and legacy ChatGPT controls.",
                granted: status.accessibilityGranted,
                actionTitle: "Open Accessibility Settings",
                action: AppDelegate.requestAccessibilityPermission
            )
            PermissionRow(
                title: "Screen Recording",
                detail: "Used only when you ask Yuki to look at the selected application window.",
                granted: status.screenRecordingGranted,
                actionTitle: "Open Screen Recording Settings",
                action: AppDelegate.requestScreenRecordingPermission
            )

            Text("Yuki cannot enable these permissions or enter an administrator password for you. macOS requires you to make the final choice in System Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Button("Check again") { status.refresh() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Done") { PermissionsWindowController.shared.close() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
            }
        }
        .padding(24)
        .frame(width: 560, height: 470, alignment: .topLeading)
        .background(.black.opacity(0.92))
        .foregroundStyle(.white)
    }
}

@MainActor
private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundStyle(granted ? .green : .pink)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline)
                    Text(granted ? "Allowed" : "Needs approval")
                        .font(.caption.bold())
                        .foregroundStyle(granted ? .green : .pink)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if !granted {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderedProminent)
                        .tint(.pink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
