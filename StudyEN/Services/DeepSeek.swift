import Foundation
import Security

/// DeepSeek 密钥：只存在本机钥匙串，不进代码、不进仓库
enum AIKey {
    private static let service = "studyen.deepseek"
    private static let account = "apiKey"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var value: String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func set(_ key: String?) {
        SecItemDelete(query as CFDictionary)
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// DeepSeek 对话接口（OpenAI 兼容）
enum DeepSeek {
    enum Failure: LocalizedError {
        case noKey, badKey, noBalance, http(Int), empty, format

        var errorDescription: String? {
            switch self {
            case .noKey: return "还没有填 DeepSeek 密钥"
            case .badKey: return "密钥无效，检查一下是否复制完整"
            case .noBalance: return "DeepSeek 账户余额不足"
            case .http(let code): return "请求失败（\(code)），稍后再试"
            case .empty: return "AI 没有返回内容，再试一次"
            case .format: return "AI 返回的格式不对，再试一次"
            }
        }
    }

    private struct Message: Codable {
        let role: String
        let content: String
    }

    private struct Response: Decodable {
        struct Choice: Decodable { let message: Message }
        let choices: [Choice]
    }

    /// json = true 时要求只返回 JSON 对象（提示词里必须出现 json 字样）
    static func chat(system: String, user: String, json: Bool = false, temperature: Double = 1.0) async throws -> String {
        guard let key = AIKey.value else { throw Failure.noKey }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": "deepseek-chat",
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": temperature,
            "stream": false,
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: break
        case 401: throw Failure.badKey
        case 402: throw Failure.noBalance
        default: throw Failure.http(code)
        }
        let text = try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content ?? ""
        guard !text.isEmpty else { throw Failure.empty }
        return text
    }
}
