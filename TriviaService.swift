import FirebaseFunctions
import Foundation

@MainActor
final class TriviaService {

    private let functions: Functions

    init(region: String = "us-central1") {
        self.functions = Functions.functions(region: region)
    }

    /// Fetches trivia questions based on a topic
    func getTriviaPack(topic: String) async throws -> String {
        // 1. Ensure authenticated before calling Firebase to avoid 32Hz limit errors
        _ = try await AuthManager.shared.ensureAuthenticated() //

        let data: [String: Any] = ["topic": topic]

        do {
            let result = try await functions.httpsCallable("generateTriviaPack").call(data)

            // 2. Streamlined parsing
            if let dict = result.data as? [String: Any] {
                // If the backend wraps the response in a "pack" key
                if let pack = dict["pack"] {
                    return try Self.jsonString(from: pack)
                }
                return try Self.jsonString(from: dict)
            }

            if let str = result.data as? String {
                return str
            }

            return try Self.jsonString(from: result.data)

        } catch {
            print("❌ Trivia Generation Error: \(error.localizedDescription)")
            throw error
        }
    }

    private static func jsonString(from any: Any) throws -> String {
        // If it's already a String, don't re-serialize it
        if let alreadyString = any as? String { return alreadyString }
        
        let obj = JSONSerialization.isValidJSONObject(any) ? any : ["value": String(describing: any)]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
