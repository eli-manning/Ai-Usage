import Foundation

enum OAuthUsageError: Error, LocalizedError {
    case badStatus(String, Int, String)
    case invalidResponse(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .badStatus(let provider, let status, let detail):
            return "\(provider) usage request failed (HTTP \(status))\(detail.isEmpty ? "" : ": \(detail)")"
        case .invalidResponse(let provider): return "\(provider) returned an unexpected usage response."
        case .unavailable(let detail): return detail
        }
    }
}

/// Converts account OAuth responses into the existing `UsageService` data
/// structures. Keeping those structures stable is what lets both visual
/// styles switch from CLI scraping to OAuth without duplicating UI state.
enum OAuthUsageClient {
    static func fetchClaude(session: AuthSession) async throws -> ClaudeUsage {
        let request = try makeRequest(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            token: session.accessToken,
            headers: [
                "anthropic-beta": "oauth-2025-04-20",
                "anthropic-version": "2023-06-01",
            ]
        )
        let data = try await responseData(for: request, provider: "Claude")
        let response: ClaudeOAuthUsageResponse
        do { response = try JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data) }
        catch { throw OAuthUsageError.invalidResponse("Claude") }

        return ClaudeUsage(
            session: response.fiveHour?.utilization.map { Int($0.rounded()) },
            weekly: response.sevenDay?.utilization.map { Int($0.rounded()) },
            sessionReset: response.fiveHour?.resetsAt,
            weeklyReset: response.sevenDay?.resetsAt,
            lastUpdated: Date()
        )
    }

    static func fetchChatGPT(session: AuthSession) async throws -> CodexUsage {
        var headers: [String: String] = [:]
        if let claims = chatGPTClaims(from: session.idToken),
           let accountID = claims["chatgpt_account_id"] as? String {
            headers["ChatGPT-Account-Id"] = accountID
        }
        if chatGPTClaims(from: session.idToken)?["chatgpt_account_is_fedramp"] as? Bool == true {
            headers["X-OpenAI-Fedramp"] = "true"
        }

        let request = try makeRequest(
            url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
            token: session.accessToken,
            headers: headers
        )
        let data = try await responseData(for: request, provider: "ChatGPT")
        let response: ChatGPTUsageResponse
        do { response = try JSONDecoder().decode(ChatGPTUsageResponse.self, from: data) }
        catch { throw OAuthUsageError.invalidResponse("ChatGPT") }
        guard let rateLimit = response.rateLimit else { throw OAuthUsageError.invalidResponse("ChatGPT") }

        let windows = [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap { $0 }
        let limits = windows.enumerated().map { index, window in
            CodexLimit(
                name: windowLabel(seconds: window.limitWindowSeconds, fallback: index == 0 ? "Primary" : "Secondary"),
                pctUsed: Int((window.usedPercent ?? 0).rounded()),
                reset: window.resetAt.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) }
            )
        }
        guard !limits.isEmpty else { throw OAuthUsageError.invalidResponse("ChatGPT") }
        return CodexUsage(signedIn: true, plan: response.planType, limits: limits)
    }

    static func fetchGemini(session: AuthSession) async throws -> GeminiUsage {
        let project = try await resolveCodeAssistProject(token: session.accessToken)
        let request = try makeRequest(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
            method: "POST",
            token: session.accessToken,
            body: ["project": project]
        )
        let data = try await responseData(for: request, provider: "Gemini")
        let response: GeminiQuotaResponse
        do { response = try JSONDecoder().decode(GeminiQuotaResponse.self, from: data) }
        catch { throw OAuthUsageError.invalidResponse("Gemini") }

        let usable = response.buckets.filter { $0.modelID != nil && $0.remainingFraction != nil }
        guard !usable.isEmpty else { throw OAuthUsageError.invalidResponse("Gemini") }
        let grouped = Dictionary(grouping: usable) { modelFamily($0.modelID!) }
        let families = grouped.compactMap { family, buckets -> (String, GeminiQuotaResponse.Bucket)? in
            buckets.min(by: { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }).map { (family, $0) }
        }
        .sorted { familyPriority($0.0) < familyPriority($1.0) }

        let primary = families.first?.1
        let secondary = families.dropFirst().first?.1
        return GeminiUsage(
            signedIn: true,
            weeklyPct: secondary?.remainingFraction.map { Int(((1 - $0) * 100).rounded()) },
            fiveHourPct: primary?.remainingFraction.map { Int(((1 - $0) * 100).rounded()) },
            weeklyReset: secondary?.resetTime,
            fiveHourReset: primary?.resetTime
        )
    }

    private static func resolveCodeAssistProject(token: String) async throws -> String {
        let request = try makeRequest(
            url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!,
            method: "POST",
            token: token,
            body: [
                "metadata": [
                    "ideType": "IDE_UNSPECIFIED",
                    "platform": "PLATFORM_UNSPECIFIED",
                    "pluginType": "GEMINI",
                ]
            ]
        )
        let data = try await responseData(for: request, provider: "Gemini")
        let response: LoadCodeAssistResponse
        do { response = try JSONDecoder().decode(LoadCodeAssistResponse.self, from: data) }
        catch { throw OAuthUsageError.invalidResponse("Gemini") }
        guard let project = response.cloudAICompanionProject, !project.isEmpty else {
            throw OAuthUsageError.unavailable("Gemini Code Assist isn't initialized for this Google account.")
        }
        return project
    }

    private static func makeRequest(
        url: URL,
        method: String = "GET",
        token: String,
        headers: [String: String] = [:],
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AiUsage/0.1", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func responseData(for request: URLRequest, provider: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OAuthUsageError.invalidResponse(provider) }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String((String(data: data, encoding: .utf8) ?? "").prefix(160))
            throw OAuthUsageError.badStatus(provider, http.statusCode, detail)
        }
        return data
    }

    private static func chatGPTClaims(from idToken: String?) -> [String: Any]? {
        guard let idToken, let payload = JWTDecoding.payload(from: idToken) else { return nil }
        return payload["https://api.openai.com/auth"] as? [String: Any]
    }

    private static func windowLabel(seconds: Int?, fallback: String) -> String {
        switch seconds {
        case .some(17_000...19_000): return "5-hour"
        case .some(590_000...620_000): return "Weekly"
        case .some(let seconds) where seconds > 0 && seconds.isMultiple(of: 86_400): return "\(seconds / 86_400)-day"
        case .some(let seconds) where seconds > 0 && seconds.isMultiple(of: 3_600): return "\(seconds / 3_600)-hour"
        default: return fallback
        }
    }

    private static func familyPriority(_ family: String) -> Int {
        if family == "Pro" { return 0 }
        if family == "Flash" { return 1 }
        return 2
    }

    private static func modelFamily(_ id: String) -> String {
        let value = id.lowercased()
        if value.contains("pro") { return "Pro" }
        if value.contains("flash") { return "Flash" }
        return id
    }
}

private struct ClaudeOAuthUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey { case utilization; case resetsAt = "resets_at" }
    }
    let fiveHour: Window?
    let sevenDay: Window?
    enum CodingKeys: String, CodingKey { case fiveHour = "five_hour"; case sevenDay = "seven_day" }
}

private struct ChatGPTUsageResponse: Decodable {
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?
        enum CodingKeys: String, CodingKey { case primaryWindow = "primary_window"; case secondaryWindow = "secondary_window" }
    }
    struct Window: Decodable {
        let usedPercent: Double?
        let limitWindowSeconds: Int?
        let resetAt: Double?
        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }
    let planType: String?
    let rateLimit: RateLimit?
    enum CodingKeys: String, CodingKey { case planType = "plan_type"; case rateLimit = "rate_limit" }
}

private struct LoadCodeAssistResponse: Decodable {
    let cloudAICompanionProject: String?
    enum CodingKeys: String, CodingKey { case cloudAICompanionProject = "cloudaicompanionProject" }
}

private struct GeminiQuotaResponse: Decodable {
    struct Bucket: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelID: String?
        enum CodingKeys: String, CodingKey { case remainingFraction, resetTime; case modelID = "modelId" }
    }
    let buckets: [Bucket]
}
