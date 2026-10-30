import AppKit
import SwiftUI

/// Live Screen Recording status, as Ice checks it: other apps' status item windows have readable titles
/// only with the permission. CGPreflightScreenCaptureAccess() keeps its answer from launch.
func screenRecordingGranted() -> Bool {
    let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    guard let item = list.first(where: {
        $0[kCGWindowLayer as String] as? Int == 25 && $0[kCGWindowOwnerPID as String] as? pid_t != getpid()
    }) else { return CGPreflightScreenCaptureAccess() }
    return item[kCGWindowName as String] != nil
}

/// SPEC §7: both permissions, each with its live status and a button to its System Settings pane. Shown
/// at launch while one is missing.
final class Onboarding {
    static var needed: Bool { !AXIsProcessTrusted() || !screenRecordingGranted() }

    private let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
    private let hosting = NSHostingView(rootView: OnboardingView(accessibility: false, screenRecording: false,
                                                                 needsRestart: false, actions: .none))
    /// macOS applies a Screen Recording grant only to a relaunched app.
    private let launchedWithScreenRecording = CGPreflightScreenCaptureAccess()
    private var timer: Timer?

    init() {
        window.title = "Tray"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
    }

    func show() {
        render()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.render() }
        log.info("onboarding shown")
    }

    private func render() {
        let screenRecording = screenRecordingGranted()
        let actions = OnboardingView.Actions(
            openAccessibility: {
                // Lists Tray in the pane (no "+" needed) and asks once; the pane covers a past "Deny".
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                openSettings("Privacy_Accessibility")
            },
            openScreenRecording: {
                CGRequestScreenCaptureAccess()
                openSettings("Privacy_ScreenCapture")
            },
            finish: { [weak self] in self?.finish() })
        hosting.rootView = OnboardingView(accessibility: AXIsProcessTrusted(), screenRecording: screenRecording,
                                          needsRestart: screenRecording && !launchedWithScreenRecording, actions: actions)
        window.setContentSize(hosting.fittingSize)
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        window.close()
        guard screenRecordingGranted(), !launchedWithScreenRecording else { return }
        // A new instance via `open`: macOS's own "Quit & Reopen" quit Tray without reopening it.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", Bundle.main.bundlePath]
        try? open.run()
        NSApp.terminate(nil)
    }
}

private func openSettings(_ pane: String) {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
        NSWorkspace.shared.open(url)
    }
}

struct OnboardingView: View {
    struct Actions {
        var openAccessibility: () -> Void
        var openScreenRecording: () -> Void
        var finish: () -> Void
        static let none = Actions(openAccessibility: {}, openScreenRecording: {}, finish: {})
    }

    let accessibility: Bool
    let screenRecording: Bool
    let needsRestart: Bool
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tray needs two permissions").font(.title2.bold())
            PermissionRow(title: "Accessibility",
                          detail: "To open tray items' menus and to move items.",
                          granted: accessibility, open: actions.openAccessibility)
            PermissionRow(title: "Screen & System Audio Recording",
                          detail: "To show tray items live, exactly as in the menu bar.",
                          granted: screenRecording, open: actions.openScreenRecording)
            HStack {
                Spacer()
                Button(needsRestart ? "Restart Tray" : "Done", action: actions.finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!(accessibility && screenRecording))
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Open System Settings", action: open)
                }
            }
        }
    }
}
