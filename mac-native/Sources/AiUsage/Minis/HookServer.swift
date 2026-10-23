import Foundation
import Network

/// A tiny HTTP listener on 127.0.0.1 that the hook scripts post to: one POST
/// per connection, `/hook/<provider>`, body = the CLI's hook JSON.
///
/// Its own port (Mochi's is 47833) so the two apps can run side by side.
final class HookServer {
    static let port: UInt16 = 47834

    struct Delivery {
        let provider: String
        let event: String?
        let session: String?
        let pid: Int32
        let json: [String: Any]
    }

    var onHook: ((Delivery) -> Void)?
    private(set) var listening = false
    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        guard let l = try? NWListener(using: params) else {
            NSLog("[minis] could not listen on %d", Self.port)
            return
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.listening = true
            case .failed(let e):
                self?.listening = false
                NSLog("[minis] listener failed: %@", "\(e)")
            default: break
            }
        }
        l.start(queue: .main)
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listening = false
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        var buf = Data()
        func reply(_ ok: Bool) {
            let text = ok ? "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
                          : "HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n"
            c.send(content: Data(text.utf8), completion: .contentProcessed { _ in c.cancel() })
        }
        func read() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] chunk, _, finished, error in
                guard let self else { return c.cancel() }
                if let chunk { buf.append(chunk) }
                if buf.count > 8 << 20 || error != nil { return c.cancel() }
                if let head = buf.range(of: Data("\r\n\r\n".utf8)) {
                    let lines = String(decoding: buf[..<head.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
                    var fields: [String: String] = [:]
                    for line in lines.dropFirst() {
                        guard let i = line.firstIndex(of: ":") else { continue }
                        fields[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
                    }
                    let length = Int(fields["content-length"] ?? "") ?? 0
                    let body = buf[head.upperBound...]
                    if body.count >= length {
                        // A custom header means a web page can't post here: browsers
                        // won't send one cross-site without a preflight we never answer.
                        guard fields["x-aiusage"] == "1",
                              let path = lines.first?.split(separator: " ").dropFirst().first,
                              path.hasPrefix("/hook/") else { return reply(false) }
                        let provider = String(path.dropFirst("/hook/".count))
                        let json = (try? JSONSerialization.jsonObject(with: Data(body.prefix(length)))) as? [String: Any] ?? [:]
                        let event = fields["x-event"].flatMap { $0.isEmpty ? nil : $0 }
                        let session = fields["x-session"].flatMap { $0.isEmpty ? nil : $0 }
                        self.onHook?(Delivery(provider: provider, event: event, session: session,
                                              pid: Int32(fields["x-pid"] ?? "") ?? 0, json: json))
                        return reply(true)
                    }
                }
                if finished { return c.cancel() }
                read()
            }
        }
        read()
    }
}
