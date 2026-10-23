import AppKit
import WebKit

/// The app's pages (Resources/web): every surface is one, in Mochi's pixel look, so they all share one stylesheet.
enum Web {

    /// The pages' folder. Not `Bundle.module`: its generated accessor looks beside the .app rather than in
    /// Contents/Resources (where `make app` puts the bundle), and fatal-errors when it isn't found.
    static let dir: URL? = {
        // A release build lays the bundle out macOS-style (Contents/Resources); a debug one flat.
        let names = ["AiUsage_AiUsage.bundle/Contents/Resources/Resources/web", "AiUsage_AiUsage.bundle/Resources/web"]
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        return roots.compactMap { $0 }.flatMap { root in names.map { root.appendingPathComponent($0) } }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("ui.css").path) }
    }()

    static func load(_ page: String, in web: WKWebView) {
        guard let dir else { return NSLog("[web] pages not found") }
        web.loadFileURL(dir.appendingPathComponent(page), allowingReadAccessTo: dir)
    }

    static func json(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Takes the first click even when its window isn't key, so a page in a non-activating panel answers at once.
    final class View: WKWebView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// WKUserContentController holds its handlers strongly; this breaks the cycle.
    final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: (WKScriptMessageHandler & AnyObject)?
        init(_ target: WKScriptMessageHandler & AnyObject) { self.target = target }
        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(c, didReceive: message)
        }
    }
}
