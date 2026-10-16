import Foundation

// MARK: - Models

struct HydraList<T: Decodable>: Decodable {
    let members: [T]
    enum CodingKeys: String, CodingKey { case members = "hydra:member" }
}

struct MailDomain: Decodable {
    let id: String
    let domain: String
    let isActive: Bool
}

struct Account: Codable {
    let id: String
    let address: String
}

struct TokenResponse: Decodable {
    let token: String
    let id: String
}

struct Sender: Codable, Hashable {
    let address: String
    let name: String?
    var display: String { (name?.isEmpty == false ? name! : address) }
}

struct MessageSummary: Decodable, Identifiable, Hashable {
    let id: String
    let from: Sender
    let subject: String
    let intro: String?
    let seen: Bool
    let createdAt: Date
}

struct MessageDetail: Decodable {
    let id: String
    let from: Sender
    let subject: String
    let text: String?
    let html: [String]?
    let createdAt: Date
}

// MARK: - Errors

enum MailTMError: LocalizedError {
    case noDomains
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noDomains: return "ما فيه دومينات متاحة حالياً"
        case .http(let code, let body): return "خطأ من السيرفر (\(code)): \(body)"
        }
    }
}

// MARK: - Client

/// عميل بسيط لـ API حق mail.tm — https://docs.mail.tm
final class MailTMClient {
    static let shared = MailTMClient()
    private let base = URL(string: "https://api.mail.tm")!

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "تاريخ غير صالح: \(s)"))
        }
        return d
    }()

    private func request<T: Decodable>(_ path: String,
                                       method: String = "GET",
                                       body: [String: String]? = nil,
                                       token: String? = nil) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/ld+json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw MailTMError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func requestNoContent(_ path: String, method: String, token: String) async throws {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw MailTMError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: Endpoints

    func domains() async throws -> [MailDomain] {
        let list: HydraList<MailDomain> = try await request("domains")
        return list.members.filter(\.isActive)
    }

    func createAccount(address: String, password: String) async throws -> Account {
        try await request("accounts", method: "POST",
                          body: ["address": address, "password": password])
    }

    func token(address: String, password: String) async throws -> String {
        let r: TokenResponse = try await request("token", method: "POST",
                                                 body: ["address": address, "password": password])
        return r.token
    }

    func messages(token: String) async throws -> [MessageSummary] {
        let list: HydraList<MessageSummary> = try await request("messages", token: token)
        return list.members
    }

    func message(id: String, token: String) async throws -> MessageDetail {
        try await request("messages/\(id)", token: token)
    }

    func deleteMessage(id: String, token: String) async throws {
        try await requestNoContent("messages/\(id)", method: "DELETE", token: token)
    }

    func deleteAccount(id: String, token: String) async throws {
        try await requestNoContent("accounts/\(id)", method: "DELETE", token: token)
    }
}
