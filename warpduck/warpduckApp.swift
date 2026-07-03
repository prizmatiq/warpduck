import SwiftUI
import AppKit

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
                    // ждём пока статус изменится
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
        menu.addItem(withTitle: "Quit",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
