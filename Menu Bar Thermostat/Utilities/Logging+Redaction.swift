import Foundation

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
