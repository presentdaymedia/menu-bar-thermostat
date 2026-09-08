import Foundation
import Alamofire

/// Utility helpers for logging sensitive values without leaking the full token.
func redactedToken(_ token: String, prefixCount: Int = 6, suffixCount: Int = 4) -> String {
    guard !token.isEmpty else { return "<empty>" }
    if token.count <= prefixCount {
        return "\(token)…"
    }
    let prefix = token.prefix(prefixCount)
    guard token.count > prefixCount + suffixCount else {
        return "\(prefix)…"
    }
    let suffix = token.suffix(suffixCount)
    return "\(prefix)…\(suffix)"
}

/// Obscures an email address while keeping the domain visible for debugging.
func redactedEmail(_ email: String) -> String {
    guard let at = email.firstIndex(of: "@") else {
        return "\(email.prefix(2))***"
    }
    let name = email[..<at]
    let domain = email[email.index(after: at)...]
    let visibleChars = max(1, min(2, name.count))
    return "\(name.prefix(visibleChars))***@\(domain)"
}

import OSLog

/// A small local history independent of stdout. Only fixed event names, numeric status codes,
/// known error domains and allowlisted OAuth reasons belong here; never tokens or response bodies.
enum AuthenticationDiagnostics {
    private static let queue = DispatchQueue(label: "thermostat.authentication-log")
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MenuBarThermostat", category: "Authentication")
    static var logURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Menu Bar Thermostat/authentication.log")
    }

    static func safeErrorSummary(_ error: Error) -> String {
        let allowedDomains = ["NSURLErrorDomain", "NSOSStatusErrorDomain", "com.google.GIDSignIn",
                              "org.openid.appauth.oauth_token", "org.openid.appauth.general",
                              "org.openid.appauth.oauth_authorization", "org.alamofire.error"]
        let allowedReasons = ["invalid_grant", "invalid_client", "unauthorized_client", "invalid_scope",
                              "access_denied", "temporarily_unavailable", "server_error", "invalid_request"]
        // Alamofire's NSError bridge does not consistently expose NSUnderlyingErrorKey.
        let root = (error as? AFError)?.underlyingError ?? error
        var current = root as NSError
        var parts: [String] = []
        for _ in 0..<6 {
            let domain = allowedDomains.contains(current.domain) ? current.domain : "other"
            var part = "domain=\(domain) code=\(current.code)"
            if let response = current.userInfo["OIDOAuthErrorResponseErrorKey"] as? [String: Any],
               let reason = response["error"] as? String, allowedReasons.contains(reason) {
                part += " oauth=\(reason)"
            }
            parts.append(part)
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return parts.joined(separator: " underlying:")
    }

    static func record(_ event: String, error: Error? = nil) {
        let detail = event + (error.map { " " + safeErrorSummary($0) } ?? "")
        logger.notice("\(detail, privacy: .public)")
        queue.async {
            let url = logURL
            do {
                try append(detail, to: url)
            } catch {
                logger.error("Unable to write authentication history")
            }
        }
    }

    static func append(_ detail: String, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        if size > 512 * 1024 {
            let previous = url.deletingLastPathComponent().appendingPathComponent("authentication.previous.log")
            if manager.fileExists(atPath: previous.path) { try manager.removeItem(at: previous) }
            try manager.moveItem(at: url, to: previous)
        }
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(detail)\n"
        try handle.write(contentsOf: Data(line.utf8))
    }

}
