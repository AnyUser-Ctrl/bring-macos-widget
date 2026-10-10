import AppKit
import SwiftUI

@main
struct BringWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Bring Widget") {
            ContentView()
                .frame(minWidth: 420, idealWidth: 460, minHeight: 520, idealHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}

private extension NSAppleEventDescriptor {
    var isOpenApplication: Bool {
        eventClass == kCoreEventClass && eventID == kAEOpenApplication
    }

    /// "Open at Login" (System Settings or SMAppService.mainApp): loginwindow
    /// sends 'oapp' with keyAEPropData = keyAELaunchedAsLogInItem.
    var isLoginItemLaunch: Bool {
        isOpenApplication
            && paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// "Reopen windows when logging back in": 'oapp' with keyAERestoreAppState.
    var isSystemRestoreLaunch: Bool {
        isOpenApplication
            && paramDescriptor(forKeyword: AEKeyword(keyAERestoreAppState))?.enumCodeValue == OSType(kAEYes)
    }
}

/// App-window lifecycle (agent app without Dock icon, normally started as a
/// login item):
///  - Login-item launch, or launched only to forward a widget link: stay in
///    the background without a window — unless signed out, then show the
///    login window.
///  - Any other launch (Spotlight, Finder, `open`): show the window.
///  - Opened again while running: bring the existing window back instead of
///    letting SwiftUI create a second one.
/// If macOS ever stops sending the login-item flag, the window simply shows
/// at login — a visible but harmless failure.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunching = false
    private var launchedOnlyForURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Handle URLs ourselves: the widget header links to web.getbring.com,
        // and SwiftUI would open a new app window for every incoming URL.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    /// On a cold launch this runs before applicationDidFinishLaunching.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor,
                                    withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        if !didFinishLaunching { launchedOnlyForURL = true }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Must be read synchronously here: the launch event is gone one
        // run-loop tick later.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let backgroundLaunch = event?.isLoginItemLaunch == true
            || event?.isSystemRestoreLaunch == true
            || launchedOnlyForURL
        didFinishLaunching = true

        if backgroundLaunch && BringStore.shared.isAuthenticated {
            // Usually a no-op (AppKit opens no window for login items), but a
            // restore launch can bring one back.
            hideWindows()
            DispatchQueue.main.async { self.hideWindows() }
        } else {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else {
            NSApp.activate()
            return true
        }
        if let window = mainWindow {
            // Reuse the hidden window; returning true would add a second one.
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return false
        }
        NSApp.activate()
        return true // no window yet (e.g. after a login launch) → SwiftUI creates it
    }

    /// The SwiftUI content window, visible or not.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }

    private func hideWindows() {
        NSApp.windows.forEach { $0.orderOut(nil) }
    }

    private func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // SwiftUI's app delegate opens a new WindowGroup window here.
            _ = NSApp.delegate?.applicationOpenUntitledFile?(NSApp)
        }
        NSApp.activate()
    }
}
