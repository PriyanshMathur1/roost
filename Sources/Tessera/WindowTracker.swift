import AppKit
import ApplicationServices
import os

/// Watches every regular app for window events and reports "something changed".
///
/// It does not try to keep an exact model from notifications alone: any event schedules
/// one debounced call to `onChange`, and the controller then re-reads the windows that are
/// actually on screen. A missed or out-of-order notification can't leave things wrong.
@MainActor
final class WindowTracker {
    var onChange: (() -> Void)?

    private let log = Logger(subsystem: "com.priyansh.tessera", category: "tracker")
    private var observers: [pid_t: AXObserver] = [:]
    private var watchedWindows: Set<WindowRef> = []
    private var pending: DispatchWorkItem?
    private var workspaceTokens: [NSObjectProtocol] = []

    /// Notifications on an app element.
    private let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    /// Notifications on each window element.
    private let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    func start() {
        for app in NSWorkspace.shared.runningApplications where Self.isTileable(app) {
            watch(app, attempt: 0)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.watch(app, attempt: 0) }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                MainActor.assumeIsolated { self?.unwatch(app.processIdentifier) }
            },
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            },
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed(after: 0.3) }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed(after: 1.5) }
            },
        ]
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed(after: 0.5) }
        }
    }

    /// Regular, visible apps other than Tessera itself.
    static func isTileable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    /// The windows that should be tiled right now: standard, movable, on screen, not
    /// minimised, not full screen, in apps that aren't hidden.
    func tileableWindows() -> [WindowRef] {
        var result: [WindowRef] = []
        for app in NSWorkspace.shared.runningApplications where Self.isTileable(app) && !app.isHidden {
            for window in WindowRef.windows(of: app.processIdentifier)
            where window.isStandard && !window.isMinimized && !window.isFullScreen && window.canMove {
                result.append(window)
                watchWindow(window)
            }
        }
        // Windows we stopped seeing no longer need their destroy notification.
        watchedWindows.formIntersection(result)
        return result
    }

    /// Coalesces bursts of events (an app opening five windows) into one re-check.
    func changed(after delay: TimeInterval = 0.06) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Observers

    private func watch(_ app: NSRunningApplication, attempt: Int) {
        guard Self.isTileable(app), observers[app.processIdentifier] == nil, !app.isTerminated else { return }
        let pid = app.processIdentifier
        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else { return }

        let element = AX.application(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var ok = true
        for name in appNotifications {
            let status = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if status != .success && status != .notificationAlreadyRegistered { ok = false }
        }
        // A just-launched app often isn't ready to answer yet; try again shortly.
        guard ok else {
            if attempt < 8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    MainActor.assumeIsolated { self?.watch(app, attempt: attempt + 1) }
                }
            } else {
                log.info("Gave up watching \(app.localizedName ?? "?", privacy: .public)")
            }
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        changed()
    }

    private func unwatch(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        watchedWindows = watchedWindows.filter { $0.pid != pid }
        changed()
    }

    private func watchWindow(_ window: WindowRef) {
        guard !watchedWindows.contains(window), let observer = observers[window.pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in windowNotifications {
            AXObserverAddNotification(observer, window.element, name as CFString, refcon)
        }
        watchedWindows.insert(window)
    }

    /// Runs on the main run loop, where the observer sources were added.
    private static let callback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated { tracker.changed() }
    }
}
