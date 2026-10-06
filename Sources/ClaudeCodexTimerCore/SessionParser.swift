import Foundation

public enum SessionResult: Equatable {
    case waiting
    case success
    case failure(String)
}

public enum SessionParser {
    public static func parse(_ data: Data, sessionID: String) -> SessionResult {
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  row["sessionId"] as? String == sessionID,
                  row["type"] as? String == "assistant",
                  let message = row["message"] as? [String: Any] else { continue }
            let content = message["content"]
            let reply: String
            if let plain = content as? String { reply = plain }
            else { reply = (content as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined() }
            if row["isApiErrorMessage"] as? Bool == true || row["error"] != nil || message["error"] != nil {
                return .failure(String(reply.prefix(600)).isEmpty ? "Claude returned an API error." : String(reply.prefix(600)))
            }
            guard row["entrypoint"] as? String == "cli" else { return .failure("Claude did not record an interactive CLI session.") }
            // Transcript writes can precede stream completion. Do not tear down a live response.
            guard message["stop_reason"] as? String == "end_turn" else { continue }
            guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard reply.trimmingCharacters(in: .whitespacesAndNewlines) == "pong" else {
                return .failure("Claude replied, but did not return the expected pong. Open Claude setup to check your account or model.")
            }
            return .success
        }
        return .waiting
    }
}
