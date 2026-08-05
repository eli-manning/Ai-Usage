import Foundation

enum OAuthHTTPError: Error, LocalizedError {
    case badStatus(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let body):
            return "Request failed (\(code)): \(body.prefix(200))"
        case .malformedResponse:
            return "The server returned an unexpected response."
        }
    }
}

enum OAuthHTTP {
    static func postForm(url: URL, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(form)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OAuthHTTPError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1, bodyText)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthHTTPError.malformedResponse
        }
        return json
    }

    static func postJSON(url: URL, body: [String: Any], extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OAuthHTTPError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1, bodyText)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthHTTPError.malformedResponse
        }
        return json
    }

    static func getJSON(url: URL, bearerToken: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OAuthHTTPError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1, bodyText)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthHTTPError.malformedResponse
        }
        return json
    }

    private static func formBody(_ form: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        let encoded = components.percentEncodedQuery ?? ""
        return Data(encoded.utf8)
    }
}

enum JWTDecoding {
    static func payload(from jwt: String) -> [String: Any]? {
        let segments = jwt.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var base64 = String(segments[1])
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
