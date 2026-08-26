import Foundation
import XCTest
@testable import TRAE_FLOW

final class DynamicDifyChatStoreTests: XCTestCase {
    func testDecodesAgentMessageStreamEvent() throws {
        let data = Data(#"{"event":"agent_message","answer":"你好","conversation_id":"conversation-1"}"#.utf8)

        let event = try JSONDecoder().decode(DynamicDifyStreamEvent.self, from: data)

        XCTAssertEqual(event.event, "agent_message")
        XCTAssertEqual(event.answer, "你好")
        XCTAssertEqual(event.conversationID, "conversation-1")
    }

    func testDecodesConversationUnixTimestamps() throws {
        let data = Data(#"{"id":"conversation-1","name":"需求梳理","created_at":1705407629,"updated_at":1705411229}"#.utf8)

        let conversation = try JSONDecoder().decode(DynamicAIConversation.self, from: data)

        XCTAssertEqual(conversation.id, "conversation-1")
        XCTAssertEqual(conversation.name, "需求梳理")
        XCTAssertEqual(conversation.createdAt.timeIntervalSince1970, 1_705_407_629, accuracy: 0.001)
        XCTAssertEqual(conversation.updatedAt.timeIntervalSince1970, 1_705_411_229, accuracy: 0.001)
    }

    func testInfersDeepSeekProviderFromExistingBaseURL() {
        XCTAssertEqual(
            DynamicAIProvider.inferred(from: "https://api.deepseek.com/v1"),
            .deepSeek
        )
    }

    func testDecodesOpenAICompatibleStreamingChunk() throws {
        let data = Data(#"{"choices":[{"delta":{"content":"你好","reasoning_content":null}}]}"#.utf8)

        let chunk = try JSONDecoder().decode(DynamicOpenAIStreamChunk.self, from: data)

        XCTAssertEqual(chunk.choices.first?.delta.content, "你好")
    }
}
