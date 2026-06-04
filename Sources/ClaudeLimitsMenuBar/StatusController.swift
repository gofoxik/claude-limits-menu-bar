import AppKit
import ServiceManagement

/// Owns the menu bar item: the ring icon, the dropdown, and the refresh timer.
final class StatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var timer: Timer?
    private var retryTimer: Timer?

    // The usage windows change slowly, and the endpoint rate-limits aggressive polling,
    // so we refresh gently and lean on the cached value between fetches.
    private let refreshInterval: TimeInterval = 180        // 3 minutes
    private let menuOpenMinInterval: TimeInterval = 90     // throttle refresh-on-open

    private var lastGoodUsage: UsageResponse?
    private var lastFetchAt: Date?
    private var rateLimitedUntil: Date?
    private var isFetching = false

    // Reused across rebuilds so its "last updated" suffix can be refreshed in place.
    private lazy var refreshItem: NSMenuItem = {
        let item = NSMenuItem(title: "Refresh now", action: #selector(refreshFromMenu), keyEquivalent: "r")
        item.target = self
        return item
    }()

    override init() {
        super.init()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.image = RingImage.make(fraction: nil)
        statusItem.button?.font = NSFont.systemFont(ofSize: 11, weight: .medium)

        menu.delegate = self
        menu.autoenablesItems = false   // keep info rows in full-contrast label color
        statusItem.menu = menu
        rebuildMenu(with: nil, error: "Loading…")

        startTimer()
        performRefresh(force: true)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.performRefresh(force: false)
        }
    }

    // MARK: Refresh

    /// Triggered by the "Refresh now" menu item — always fetches.
    @objc private func refreshFromMenu() {
        performRefresh(force: true)
    }

    /// `force` bypasses the rate-limit backoff window (user-initiated only).
    private func performRefresh(force: Bool) {
        if isFetching { return }
        if !force, let until = rateLimitedUntil, Date() < until { return }
        isFetching = true
        Task {
            do {
                let usage = try await UsageClient.fetch()
                await MainActor.run {
                    self.isFetching = false
                    self.rateLimitedUntil = nil
                    self.lastFetchAt = Date()
                    self.lastGoodUsage = usage
                    self.apply(usage, note: nil)
                }
            } catch {
                await MainActor.run {
                    self.isFetching = false
                    self.handle(error)
                }
            }
        }
    }

    private func handle(_ error: Error) {
        if case UsageError.rateLimited(let retryAfter) = error {
            rateLimitedUntil = Date().addingTimeInterval(retryAfter)
            // Auto-retry just after the backoff window, rather than waiting a full interval.
            retryTimer?.invalidate()
            retryTimer = Timer.scheduledTimer(withTimeInterval: retryAfter + 2, repeats: false) { [weak self] _ in
                self?.performRefresh(force: true)
            }
        }
        // Keep the last known reading visible instead of blanking the ring.
        if let usage = lastGoodUsage {
            apply(usage, note: "\(String(describing: error)) — showing last known")
        } else {
            applyError(error)
        }
    }

    private func apply(_ usage: UsageResponse, note: String?) {
        let session = usage.five_hour
        let fraction = session?.fraction
        statusItem.button?.image = RingImage.make(fraction: fraction)
        if let pct = session?.utilization {
            statusItem.button?.title = " \(Int(pct.rounded()))%"
        } else {
            statusItem.button?.title = ""
        }
        statusItem.button?.toolTip = note ?? sessionLine(usage)
        rebuildMenu(with: usage, error: nil)
    }

    private func applyError(_ error: Error) {
        statusItem.button?.image = RingImage.make(fraction: nil)
        statusItem.button?.title = " –"
        let msg = String(describing: error)
        statusItem.button?.toolTip = msg
        rebuildMenu(with: nil, error: msg)
    }

    // MARK: Menu

    private func rebuildMenu(with usage: UsageResponse?, error: String?) {
        menu.removeAllItems()

        if let error {
            menu.addItem(disabled(error))
        } else if let usage {
            addUsageRow("Current session", usage.five_hour, relative: true)
            addUsageRow("Current week (all models)", usage.seven_day, relative: false)
            addUsageRow("Current week (Opus)", usage.seven_day_opus, relative: false)
            addUsageRow("Current week (Sonnet)", usage.seven_day_sonnet, relative: false)
        }

        menu.addItem(.separator())

        updateRefreshSubtitle()
        menu.addItem(refreshItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func updateRefreshSubtitle() {
        guard let last = lastFetchAt else {
            refreshItem.title = "Refresh now"
            return
        }
        let s = Int(Date().timeIntervalSince(last))
        let rel: String
        if s < 10        { rel = "just now" }
        else if s < 60   { rel = "\(s)s ago" }
        else if s < 3600 { rel = "\(s / 60)m ago" }
        else             { rel = "\(s / 3600)h ago" }
        refreshItem.title = "Refresh now (last updated: \(rel))"
    }

    private func addUsageRow(_ title: String, _ window: UsageWindow?, relative: Bool) {
        guard let window else { return }   // skip windows that don't apply to the plan
        let item = NSMenuItem()
        item.view = UsageRowView(title: title,
                                 percent: window.utilization,
                                 resetText: resetText(window.resetDate, relative: relative))
        menu.addItem(item)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func line(_ label: String, _ window: UsageWindow?, relative: Bool) -> String {
        guard let window else { return "\(label): —" }
        let pct = Int(window.utilization.rounded())
        let reset = resetText(window.resetDate, relative: relative)
        return "\(label): \(pct)%\(reset.isEmpty ? "" : "  ·  \(reset)")"
    }

    private func sessionLine(_ usage: UsageResponse) -> String {
        line("Session (5h)", usage.five_hour, relative: true)
    }

    private func resetText(_ date: Date?, relative: Bool) -> String {
        guard let date else { return "" }
        if relative {
            let secs = date.timeIntervalSinceNow
            if secs <= 0 { return "resetting…" }
            let h = Int(secs) / 3600
            let m = (Int(secs) % 3600) / 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        } else {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEE MMM d"
            return "resets \(fmt.string(from: date))"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateRefreshSubtitle()   // keep the "last updated" label accurate on every open
        // Only refresh on open if the data is getting stale; otherwise show the cache.
        if let last = lastFetchAt, Date().timeIntervalSince(last) < menuOpenMinInterval { return }
        performRefresh(force: false)
    }

    // MARK: Launch at Login

    private var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ClaudeLimits: launch-at-login toggle failed: \(error)")
        }
    }
}
