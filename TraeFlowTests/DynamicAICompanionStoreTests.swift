import XCTest
@testable import TRAE_FLOW

final class DynamicAICompanionStoreTests: XCTestCase {
    func testMemoryExtractorCreatesPreferenceCandidate() throws {
        let candidate = try XCTUnwrap(
            DynamicAIMemoryExtractor.candidates(from: "我喜欢在晚上听轻音乐").first
        )

        XCTAssertEqual(candidate.category, "偏好")
        XCTAssertEqual(candidate.content, "我喜欢在晚上听轻音乐")
        XCTAssertEqual(candidate.confidence, 0.90, accuracy: 0.001)
    }

    func testMemoryExtractorIgnoresOrdinaryConversation() {
        XCTAssertTrue(
            DynamicAIMemoryExtractor.candidates(from: "今天的天气看起来不错").isEmpty
        )
    }

    func testMemoryExtractorCreatesConfirmedCareerIdentityCandidate() throws {
        let candidate = try XCTUnwrap(
            DynamicAIMemoryExtractor.candidates(from: "我是一个 AI 产品经理").first
        )

        XCTAssertEqual(candidate.category, "职业身份")
        XCTAssertEqual(candidate.content, "我是一个 AI 产品经理")
        XCTAssertEqual(candidate.confidence, 0.96, accuracy: 0.001)
    }

    func testSafetyRouterInterceptsHighRiskContentLocally() {
        let response = DynamicAISafetyRouter.response(for: "我不想活了，也不知道找谁")

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.contains("110") == true)
        XCTAssertTrue(response?.contains("立即危险") == true)
    }

    func testSafetyRouterDoesNotInterceptOrdinaryNegativeMood() {
        XCTAssertNil(DynamicAISafetyRouter.response(for: "今天工作有一点烦"))
    }

    func testTextRankingPrefersRelevantChineseContent() {
        let relevant = DynamicAITextRanking.score(
            query: "我喜欢什么音乐",
            text: "用户喜欢晚上听轻音乐"
        )
        let unrelated = DynamicAITextRanking.score(
            query: "我喜欢什么音乐",
            text: "用户计划周末整理房间"
        )

        XCTAssertGreaterThan(relevant, unrelated)
    }

    func testContextBuilderIncludesMemoryAndDocumentSources() {
        let source = DynamicAIMemorySource(
            kind: "conversation",
            title: "会话：晚间陪伴",
            referenceID: "message-1",
            createdAt: .distantPast
        )
        let memory = DynamicAIMemory(
            id: "memory-1",
            content: "我喜欢晚上听轻音乐",
            category: "偏好",
            confidence: 0.9,
            status: .confirmed,
            source: source,
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
        let document = DynamicAIKnowledgeDocument(
            id: "document-1",
            name: "我的日记.md",
            localPath: "/tmp/my-diary.md",
            fileSize: 128,
            importedAt: .distantPast,
            status: .ready,
            content: "今天完成了项目复盘。",
            errorMessage: nil
        )
        let match = DynamicAIKnowledgeMatch(
            document: document,
            snippet: "今天完成了项目复盘。",
            score: 2
        )

        let context = DynamicAIContextBuilder.build(
            mode: .review,
            query: "帮我复盘今天",
            memories: [memory],
            knowledge: [match],
            blockedRules: ["银行卡密码"]
        )

        XCTAssertTrue(context.contains("来源：会话：晚间陪伴"))
        XCTAssertTrue(context.contains("文档《我的日记.md》"))
        XCTAssertTrue(context.contains("禁止记忆或复述"))
    }
}
