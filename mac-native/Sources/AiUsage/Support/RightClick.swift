import AppKit
import SwiftUI

/// Calls `action` on a right-click (or control-click) over the view it overlays, and lets every other click through.
/// SwiftUI on macOS 13 has no right-click gesture short of a context menu, and the app's menus are Mochi panels.
struct RightClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let v = Catcher()
        v.action = action
        return v
    }

    func updateNSView(_ v: Catcher, context: Context) { v.action = action }

    final class Catcher: NSView {
        var action: () -> Void = {}

        /// Only claims the click when it's a right-click, so left clicks still reach the button underneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent else { return nil }
            let right = e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
            return right ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) { action() }   // control-click
    }
}
