import AppKit
import SwiftUI

@MainActor
final class ProjectCloseGuard: NSObject, NSApplicationDelegate {
    var confirmDiscardingChanges: (() -> Bool)?
    var prepareForTermination: (() -> Void)?

    private var isConfirming = false
    private var hasConfirmedWindowClose = false

    func confirmClose() -> Bool {
        guard !isConfirming, NSApp?.modalWindow == nil else { return false }
        isConfirming = true
        defer { isConfirming = false }
        return confirmDiscardingChanges?() ?? true
    }

    func projectWindowDidOpen() {
        hasConfirmedWindowClose = false
    }

    func projectWindowDidClose() {
        hasConfirmedWindowClose = true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Closing the single main window can immediately trigger app termination.
        // Do not ask twice after its close has already been approved.
        hasConfirmedWindowClose || confirmClose() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        prepareForTermination?()
    }
}

struct ProjectWindowCloseGuard: NSViewRepresentable {
    let closeGuard: ProjectCloseGuard

    func makeCoordinator() -> Coordinator {
        Coordinator(closeGuard: closeGuard)
    }

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        context.coordinator.attach(to: nsView.window)
    }

    static func dismantleNSView(_ nsView: WindowObserverView, coordinator: Coordinator) {
        nsView.onWindowChange = nil
        coordinator.detach()
    }

    final class WindowObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let closeGuard: ProjectCloseGuard
        private weak var window: NSWindow?
        private weak var forwardedDelegate: NSWindowDelegate?
        private var closeWasApproved = false

        init(closeGuard: ProjectCloseGuard) {
            self.closeGuard = closeGuard
        }

        @MainActor
        func attach(to window: NSWindow?) {
            guard self.window !== window || window?.delegate !== self else { return }
            detach()
            guard let window else { return }

            self.window = window
            // A recreated representable must forward to SwiftUI, not an expiring proxy.
            if let previousProxy = window.delegate as? Coordinator {
                forwardedDelegate = previousProxy.forwardedDelegate
            } else {
                forwardedDelegate = window.delegate
            }
            closeWasApproved = false
            closeGuard.projectWindowDidOpen()
            window.delegate = self
        }

        @MainActor
        func detach() {
            if let window, window.delegate === self {
                window.delegate = forwardedDelegate
            }
            window = nil
            forwardedDelegate = nil
        }

        @MainActor
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            closeWasApproved = false
            guard closeGuard.confirmClose() else { return false }
            closeWasApproved = forwardedDelegate?.windowShouldClose?(sender) ?? true
            return closeWasApproved
        }

        @MainActor
        func windowWillClose(_ notification: Notification) {
            if closeWasApproved {
                closeGuard.projectWindowDidClose()
            }
            forwardedDelegate?.windowWillClose?(notification)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || forwardedDelegate?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let forwardedDelegate, forwardedDelegate.responds(to: aSelector) {
                return forwardedDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
