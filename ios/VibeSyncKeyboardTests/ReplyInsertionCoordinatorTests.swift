import XCTest

final class ReplyInsertionCoordinatorTests: XCTestCase {
    func testNetworkResultDoesNotInsertAndUserTapInsertsExactlyOnce() throws {
        let binding = KeyboardRequestBinding.fixture()
        let option = KeyboardAssistReadyResponse
            .fixture(requestID: binding.requestID)
            .options[0]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = KeyboardResultsPresentation(
            binding: binding,
            options: [option],
            presentedAt: now.addingTimeInterval(-1)
        )
        let proxy = FakeTextInserter()
        let coordinator = ReplyInsertionCoordinator(
            insertText: proxy.insertText
        )

        XCTAssertTrue(proxy.insertedTexts.isEmpty)

        let context = KeyboardInsertionContext(
            operationID: binding.operationID,
            requestID: binding.requestID,
            ownerUserID: binding.ownerUserID,
            documentIdentifier: binding.documentIdentifier,
            assetIdentifier: binding.assetIdentifier,
            screenshotHash: binding.screenshotHash,
            partnerID: binding.partnerID,
            contextRevision: binding.contextRevision,
            now: now
        )
        XCTAssertEqual(
            try coordinator.insert(
                option: option,
                presentation: presentation,
                context: context
            ),
            .inserted
        )
        XCTAssertEqual(proxy.insertedTexts, [option.text])

        XCTAssertEqual(
            try coordinator.insert(
                option: option,
                presentation: presentation,
                context: context
            ),
            .alreadyInserted
        )
        XCTAssertEqual(proxy.insertedTexts, [option.text])
    }

    func testWrongChatNeverInserts() {
        let binding = KeyboardRequestBinding.fixture()
        let option = KeyboardAssistReadyResponse
            .fixture(requestID: binding.requestID)
            .options[0]
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let presentation = KeyboardResultsPresentation(
            binding: binding,
            options: [option],
            presentedAt: now
        )
        let proxy = FakeTextInserter()
        let coordinator = ReplyInsertionCoordinator(insertText: proxy.insertText)
        let wrongContext = KeyboardInsertionContext(
            operationID: binding.operationID,
            requestID: binding.requestID,
            ownerUserID: binding.ownerUserID,
            documentIdentifier: UUID(),
            assetIdentifier: binding.assetIdentifier,
            screenshotHash: binding.screenshotHash,
            partnerID: binding.partnerID,
            contextRevision: binding.contextRevision,
            now: now
        )

        XCTAssertThrowsError(
            try coordinator.insert(
                option: option,
                presentation: presentation,
                context: wrongContext
            )
        )
        XCTAssertTrue(proxy.insertedTexts.isEmpty)
    }
}

private final class FakeTextInserter {
    private(set) var insertedTexts: [String] = []

    func insertText(_ text: String) {
        insertedTexts.append(text)
    }
}
