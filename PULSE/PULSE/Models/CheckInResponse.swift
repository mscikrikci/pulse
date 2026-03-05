import Foundation

struct CheckInResponse: Codable {
    let headline: String
    let observation: String
    let suggestion: String
    let protocolId: String?
    let chatPrompt: String

    enum CodingKeys: String, CodingKey {
        case headline
        case observation
        case suggestion
        case protocolId = "protocol_id"
        case chatPrompt = "chat_prompt"
    }
}
