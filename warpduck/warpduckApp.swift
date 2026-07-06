import SwiftUI
import AppKit
import SQLite3

@main
struct WarpduckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var isOn = false
    private var isConnecting = false
    private var statusTimer: Timer?
    private var animationTimer: Timer?
    private var animationFrame = 0
    private var cachedSubscriptionInfo: [String] = []
    private let loadingFrames = ["vpn_loading_1", "vpn_loading_2", "vpn_loading_3", "vpn_loading_4", "vpn_loading_5", "vpn_loading_6", "vpn_loading_7", "vpn_loading_8"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatus()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateStatus()
        }
        refreshSubscriptionInfo()
        showStartupAlert()
    }

    private func showStartupAlert() {
        let w: CGFloat = 200
        let h: CGFloat = 160
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 20
        blur.layer?.masksToBounds = true

        let imgW: CGFloat = 130
        let imgH: CGFloat = 94
        let imageView = NSImageView(frame: NSRect(x: (w - imgW) / 2, y: 45, width: imgW, height: imgH))
        imageView.image = NSImage(named: "launch_logo")
        imageView.imageScaling = .scaleProportionallyUpOrDown
        blur.addSubview(imageView)

        let label = NSTextField(labelWithString: "lives in the menu bar")
        label.textColor = NSColor(white: 1.0, alpha: 0.7)
        label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 16, width: w, height: 20)
        blur.addSubview(label)

        panel.contentView?.addSubview(blur)

        if let screen = NSScreen.main {
            let x = (screen.frame.width - w) / 2
            let y = (screen.frame.height - h) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.close()
            }
        }
    }

    private func refreshSubscriptionInfo() {
        guard let url = getSubscriptionURL() else { return }
        fetchSubscriptionInfo(url: url) { [weak self] info in
            DispatchQueue.main.async {
                self?.cachedSubscriptionInfo = info
            }
        }
    }

    private func updateStatus() {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--nc", "list"]
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let connected = output.components(separatedBy: "\n")
                                  .filter { $0.contains("Happ") }
                                  .first?.contains("(Connected)") == true
            DispatchQueue.main.async {
                self.isOn = connected
                if self.isConnecting {
                    if connected == self.isOn {
                        self.stopAnimation()
                        self.isConnecting = false
                        self.render()
                    }
                } else {
                    self.render()
                }
            }
        } catch {
            NSLog("scutil error: \(error)")
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let name = isOn ? "vpn_on" : "vpn_off"
        if let img = NSImage(named: name) {
            img.size = NSSize(width: 18, height: 18)
            button.image = img
            button.image?.isTemplate = true
        }
        button.alphaValue = isOn ? 1.0 : 0.5
    }

    private func startAnimation() {
        animationFrame = 0
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let button = self.statusItem.button else { return }
            let name = self.loadingFrames[self.animationFrame % self.loadingFrames.count]
            if let img = NSImage(named: name) {
                img.size = NSSize(width: 18, height: 18)
                button.image = img
                button.image?.isTemplate = true
            }
            button.alphaValue = 0.3
            self.animationFrame += 1
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        isConnecting = true
        startAnimation()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--nc", isOn ? "stop" : "start", "Happ"]
        do {
            try task.run()
        } catch {
            NSLog("Не смог переключить VPN: \(error)")
            isConnecting = false
            stopAnimation()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let info = cachedSubscriptionInfo.isEmpty ? ["Loading..."] : cachedSubscriptionInfo
        for (index, item) in info.enumerated() {
            let menuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            if index == 0 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.boldSystemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
                menuItem.attributedTitle = NSAttributedString(string: item, attributes: attrs)
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
                menuItem.attributedTitle = NSAttributedString(string: item, attributes: attrs)
            }
            menu.addItem(menuItem)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func getSubscriptionURL() -> String? {
        let dbPath = NSHomeDirectory() + "/Library/Containers/su.ffg.happ/Data/Library/Caches/su.ffg.happ/Cache.db"
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_close(db) }

        let query = "SELECT request_key FROM cfurl_cache_response WHERE request_key LIKE 'https://sub.%' ORDER BY time_stamp DESC LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW,
           let cString = sqlite3_column_text(stmt, 0) {
            return String(cString: cString)
        }
        return nil
    }

    private func fetchSubscriptionInfo(url: String, completion: @escaping ([String]) -> Void) {
        guard let requestURL = URL(string: url) else {
            completion(["Invalid URL"])
            return
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "HEAD"

        URLSession.shared.dataTask(with: request) { _, response, _ in
            guard let http = response as? HTTPURLResponse else {
                completion(["No response"])
                return
            }

            var items: [String] = []

            if let info = http.value(forHTTPHeaderField: "subscription-userinfo") {
                let parts = info.components(separatedBy: "; ")
                var download: Int64 = 0
                var total: Int64 = 0
                var expire: Int64 = 0

                for part in parts {
                    let kv = part.components(separatedBy: "=")
                    guard kv.count == 2 else { continue }
                    switch kv[0].trimmingCharacters(in: .whitespaces) {
                    case "download": download = Int64(kv[1]) ?? 0
                    case "upload":   download += Int64(kv[1]) ?? 0
                    case "total":    total = Int64(kv[1]) ?? 0
                    case "expire":   expire = Int64(kv[1]) ?? 0
                    default: break
                    }
                }

                let used = self.formatBytes(download)
                let totalStr = self.formatBytes(total)
                let remaining = self.formatBytes(max(0, total - download))
                items.append("\(used) / \(totalStr)")
                items.append("Remaining: \(remaining)")

                if expire > 0 {
                    let date = Date(timeIntervalSince1970: TimeInterval(expire))
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none
                    items.append("Expires: \(formatter.string(from: date))")
                }
            } else {
                items.append("No subscription info")
            }

            completion(items)
        }.resume()
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let tb = Double(bytes) / 1_000_000_000_000
        if tb >= 1 {
            return String(format: "%.0f TB", tb)
        }
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}
