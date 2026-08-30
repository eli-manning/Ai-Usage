import Darwin
import Foundation

/// Checked before spawning `claude` at all — a DNS lookup is faster than
/// waiting out a doomed PTY call, and (unlike parsing claude's own error text)
/// doesn't depend on guessing what wording a given failure mode prints.
///
/// Uses `getaddrinfo` directly rather than `Network.framework`: this needs a
/// synchronous yes/no with a hard 3-second ceiling from a background queue,
/// which is exactly what a plain resolver call gives.
public enum Reachability {

    public static func isOnline(host: String = "anthropic.com", timeout: TimeInterval = 3) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var reachable = false

        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo(
                ai_flags: 0,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil)
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &result)
            if status == 0 {
                reachable = true
                if let result { freeaddrinfo(result) }
            }
            semaphore.signal()
        }

        // A resolver call that outruns the ceiling is treated as offline; the
        // stray background lookup is harmless and finishes on its own.
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { return false }
        return reachable
    }
}
