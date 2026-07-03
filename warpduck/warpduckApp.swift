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
    private let shortcutName = "VPN"   // ← точное имя твоего Siri Shortcut

    private var statusItem: NSStatusItem!
    private var isOn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let symbol = isOn ? "lock.shield.fill" : "lock.shield"
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: isOn ? "VPN on" : "VPN off")
        button.image?.isTemplate = true
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
        isOn.toggle()
        render()
        runShortcut()
    }

    private func runShortcut() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        task.arguments = ["run", shortcutName]
        do {
            try task.run()
        } catch {
            NSLog("Не смог запустить Shortcut '\(shortcutName)': \(error)")
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
