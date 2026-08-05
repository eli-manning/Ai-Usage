import Foundation
import Network

/// A minimal, single-shot local HTTP server used to receive the OAuth
/// redirect from the system browser (the "loopback" flow used by installed
/// apps). It accepts exactly one valid callback request, replies with a
/// small HTML page, and shuts itself down.
final class LoopbackOAuthServer {
    enum ServerError: Error, LocalizedError {
        case allPortsUnavailable
        case invalidRequest
        case stateMismatch
        case providerError(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .allPortsUnavailable: return "Could not open a local port for sign-in. Is another sign-in already in progress?"
            case .invalidRequest: return "The sign-in redirect was missing required data."
            case .stateMismatch: return "The sign-in response did not match the request. Please try again."
            case .providerError(let message): return message
            case .timedOut: return "Sign-in timed out."
            }
        }
    }

    struct CallbackResult {
        let code: String
        let state: String
    }

    private var listener: NWListener?

    /// Binds the exact redirect port, signals readiness, then waits for one
    /// matching callback request on `path`.
    func waitForCallback(
        port: UInt16,
        path: String,
        expectedState: String,
        timeout: TimeInterval = 300,
        onReady: @escaping @Sendable () -> Void
    ) async throws -> CallbackResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.allPortsUnavailable
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        // Listen on IPv4 and IPv6 so both `127.0.0.1` and `localhost` work.
        // The random OAuth state prevents callbacks from other hosts from
        // completing the flow.
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        return try await withCheckedThrowingContinuation { continuation in
            // Only ever touched from `queue`, which serializes all access.
            nonisolated(unsafe) var resumed = false
            nonisolated(unsafe) var signaledReady = false
            let queue = DispatchQueue(label: "aiusage.oauth.loopback")

            @Sendable func finish(_ result: Result<CallbackResult, Error>) {
                queue.async {
                    guard !resumed else { return }
                    resumed = true
                    listener.cancel()
                    switch result {
                    case .success(let value): continuation.resume(returning: value)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                Self.readRequestLine(on: connection, queue: queue) { requestLine in
                    guard
                        let requestLine,
                        let url = Self.parseRequestURL(requestLine)
                    else {
                        Self.respond(connection, status: "400 Bad Request", html: Self.page(title: "Sign-in failed", message: "Malformed request."))
                        return
                    }

                    guard url.path == path else {
                        Self.respond(connection, status: "404 Not Found", html: Self.page(title: "Not found", message: "Unexpected callback path."))
                        return
                    }

                    let query = Self.queryItems(from: url)
                    if let errorValue = query["error"] {
                        let description = query["error_description"] ?? errorValue
                        Self.respond(connection, status: "200 OK", html: Self.page(title: "Sign-in failed", message: description))
                        finish(.failure(ServerError.providerError(description)))
                        return
                    }

                    guard let code = query["code"], let state = query["state"] else {
                        Self.respond(connection, status: "400 Bad Request", html: Self.page(title: "Sign-in failed", message: "Missing authorization code."))
                        finish(.failure(ServerError.invalidRequest))
                        return
                    }

                    guard state == expectedState else {
                        Self.respond(connection, status: "400 Bad Request", html: Self.page(title: "Sign-in failed", message: "State mismatch."))
                        finish(.failure(ServerError.stateMismatch))
                        return
                    }

                    Self.respond(connection, status: "200 OK", html: Self.page(title: "Signed in", message: "You can close this tab and return to Ai Usage."))
                    finish(.success(CallbackResult(code: code, state: state)))
                }
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard !signaledReady else { return }
                    signaledReady = true
                    onReady()
                case .failed:
                    finish(.failure(ServerError.allPortsUnavailable))
                default:
                    break
                }
            }

            listener.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.failure(ServerError.timedOut))
            }
        }
    }

    // MARK: - Raw HTTP handling

    private static func readRequestLine(on connection: NWConnection, queue: DispatchQueue, accumulated: Data = Data(), completion: @escaping (String?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let text = String(data: buffer, encoding: .utf8), let firstLine = text.split(separator: "\r\n").first {
                completion(String(firstLine))
                return
            }

            if isComplete || error != nil || buffer.count > 64 * 1024 {
                completion(nil)
                return
            }

            readRequestLine(on: connection, queue: queue, accumulated: buffer, completion: completion)
        }
    }

    private static func parseRequestURL(_ requestLine: String) -> URL? {
        // e.g. "GET /oauth2callback?code=...&state=... HTTP/1.1"
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return URL(string: "http://127.0.0.1\(parts[1])")
    }

    private static func queryItems(from url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var result: [String: String] = [:]
        for item in items {
            result[item.name] = item.value
        }
        return result
    }

    private static func respond(_ connection: NWConnection, status: String, html: String) {
        let body = html.data(using: .utf8) ?? Data()
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var data = Data(response.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func page(title: String, message: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>\(title)</title>
        <style>
        body { font-family: -apple-system, sans-serif; background: #0b0b0d; color: #f2f2f2; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
        .card { text-align: center; padding: 32px; }
        h1 { font-size: 20px; margin-bottom: 8px; }
        p { color: #a1a1aa; }
        </style>
        </head>
        <body><div class="card"><h1>\(title)</h1><p>\(message)</p></div></body>
        </html>
        """
    }
}
