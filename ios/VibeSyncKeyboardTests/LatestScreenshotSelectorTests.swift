import UIKit
import XCTest

final class LatestScreenshotSelectorTests: XCTestCase {
    func testConsentMissingDoesNotQueryPhotoLibrary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let library = FakeScreenshotLibrary(status: .authorized, candidates: [])
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: false
        ) { result in
            guard case .failure(let error) = result else {
                return XCTFail("Expected consent failure")
            }
            XCTAssertEqual(error, .consentRequired)
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(library.fetchCount, 0)
    }

    func testCapabilityMissingDoesNotInspectAuthorizationOrFetchPhotos() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let library = FakeScreenshotLibrary(status: .authorized, candidates: [])
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: nil,
            ownerUserId: "user-a",
            userAuthorizedDetection: true
        ) { result in
            guard case .failure(.capabilityRequired) = result else {
                return XCTFail("Expected capability failure")
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(library.fetchCount, 0)
    }

    func testSelectsNewestScreenshotInsideThreeMinuteWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIImage()
        let library = FakeScreenshotLibrary(
            status: .limited,
            candidates: [
                ScreenshotLibraryCandidate(
                    assetIdentifier: "old",
                    creationDate: now.addingTimeInterval(-181),
                    thumbnail: image
                ),
                ScreenshotLibraryCandidate(
                    assetIdentifier: "newer",
                    creationDate: now.addingTimeInterval(-10),
                    thumbnail: image
                ),
                ScreenshotLibraryCandidate(
                    assetIdentifier: "new",
                    creationDate: now.addingTimeInterval(-30),
                    thumbnail: image
                ),
            ]
        )
        let provider = LatestScreenshotProvider(library: library, now: { now })
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true
        ) { result in
            guard case .success(let screenshot) = result else {
                return XCTFail("Expected a recent screenshot")
            }
            XCTAssertEqual(screenshot.assetIdentifier, "newer")
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(library.fetchCount, 1)
    }

    func testDeniedAndNotDeterminedNeverRequestPermissionOrFetch() {
        for status in [
            KeyboardPhotoAuthorization.denied,
            .restricted,
            .notDetermined,
        ] {
            let library = FakeScreenshotLibrary(status: status, candidates: [])
            let now = Date()
            let provider = LatestScreenshotProvider(
                library: library,
                now: { now }
            )
            let finished = expectation(description: "\(status)")

            provider.fetchLatest(
                capability: screenshotCapability(now: now),
                ownerUserId: "user-a",
                userAuthorizedDetection: true
            ) { result in
                guard case .failure(let error) = result else {
                    return XCTFail("Expected permission failure")
                }
                XCTAssertEqual(error, .permissionRequired(status))
                finished.fulfill()
            }

            wait(for: [finished], timeout: 0.2)
            XCTAssertEqual(library.fetchCount, 0)
        }
    }

    func testFetchesTheExactPendingAssetWithoutApplyingRecencyWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = ScreenshotLibraryCandidate(
            assetIdentifier: "pending-asset",
            creationDate: now.addingTimeInterval(-3_600),
            thumbnail: UIImage()
        )
        let library = FakeScreenshotLibrary(
            status: .authorized,
            candidates: [],
            exactCandidate: expected
        )
        let provider = LatestScreenshotProvider(library: library, now: { now })
        let finished = expectation(description: "exact pending asset")

        provider.fetch(
            assetIdentifier: expected.assetIdentifier,
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true
        ) { result in
            guard case .success(let screenshot) = result else {
                return XCTFail("Expected exact pending asset")
            }
            XCTAssertEqual(
                screenshot.assetIdentifier,
                expected.assetIdentifier
            )
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
        XCTAssertEqual(library.exactFetchIdentifiers, ["pending-asset"])
        XCTAssertEqual(library.fetchCount, 0)
    }

    /// Opening the keyboard is not consent to spend a charge on whatever is
    /// already in the camera roll. Only a capture taken after the keyboard came
    /// up counts, even when an older one is still inside the recency window.
    func testCapturesFromBeforeThisKeyboardSessionAreIgnored() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIImage()
        let library = FakeScreenshotLibrary(
            status: .authorized,
            candidates: [
                ScreenshotLibraryCandidate(
                    assetIdentifier: "before-keyboard",
                    creationDate: now.addingTimeInterval(-40),
                    thumbnail: image
                ),
            ]
        )
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now },
            sessionStartedAt: { now.addingTimeInterval(-20) }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true
        ) { result in
            guard case .failure(.noRecentScreenshot) = result else {
                return XCTFail("A pre-session capture must not be analysed")
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
    }

    /// The explicit tap is the only way past the session floor, and it still
    /// obeys the recency window.
    func testExplicitTapMayReachACaptureFromBeforeTheSession() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIImage()
        let library = FakeScreenshotLibrary(
            status: .authorized,
            candidates: [
                ScreenshotLibraryCandidate(
                    assetIdentifier: "before-keyboard",
                    creationDate: now.addingTimeInterval(-40),
                    thumbnail: image
                ),
            ]
        )
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now },
            sessionStartedAt: { now.addingTimeInterval(-20) }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true,
            ignoringSessionFloor: true
        ) { result in
            guard case .success(let screenshot) = result else {
                return XCTFail("An explicit tap may use the earlier capture")
            }
            XCTAssertEqual(screenshot.assetIdentifier, "before-keyboard")
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
    }

    func testExplicitTapStillObeysTheRecencyWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIImage()
        let library = FakeScreenshotLibrary(
            status: .authorized,
            candidates: [
                ScreenshotLibraryCandidate(
                    assetIdentifier: "yesterday",
                    creationDate: now.addingTimeInterval(-4000),
                    thumbnail: image
                ),
            ]
        )
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now },
            sessionStartedAt: { now.addingTimeInterval(-20) }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true,
            ignoringSessionFloor: true
        ) { result in
            guard case .failure(.noRecentScreenshot) = result else {
                return XCTFail("A stale capture is never in scope")
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
    }

    func testCaptureTakenWhileTheKeyboardIsOpenIsAccepted() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let image = UIImage()
        let library = FakeScreenshotLibrary(
            status: .authorized,
            candidates: [
                ScreenshotLibraryCandidate(
                    assetIdentifier: "before-keyboard",
                    creationDate: now.addingTimeInterval(-40),
                    thumbnail: image
                ),
                ScreenshotLibraryCandidate(
                    assetIdentifier: "during-keyboard",
                    creationDate: now.addingTimeInterval(-5),
                    thumbnail: image
                ),
            ]
        )
        let provider = LatestScreenshotProvider(
            library: library,
            now: { now },
            sessionStartedAt: { now.addingTimeInterval(-20) }
        )
        let finished = expectation(description: "completion")

        provider.fetchLatest(
            capability: screenshotCapability(now: now),
            ownerUserId: "user-a",
            userAuthorizedDetection: true
        ) { result in
            guard case .success(let screenshot) = result else {
                return XCTFail("Expected the in-session capture")
            }
            XCTAssertEqual(screenshot.assetIdentifier, "during-keyboard")
            finished.fulfill()
        }

        wait(for: [finished], timeout: 0.2)
    }
}

private func screenshotCapability(
    now: Date
) -> KeyboardAssistCapabilityReceipt {
    KeyboardAssistCapabilityReceipt(
        contractVersion: .v1,
        ownerUserId: "user-a",
        enabled: true,
        pipelineVersion: "compiler-judge-v1",
        receivedAt: now,
        expiresAt: now.addingTimeInterval(300)
    )
}

private final class FakeScreenshotLibrary: ScreenshotLibrary {
    let authorizationStatus: KeyboardPhotoAuthorization
    let candidates: [ScreenshotLibraryCandidate]
    let exactCandidate: ScreenshotLibraryCandidate?
    private(set) var fetchCount = 0
    private(set) var exactFetchIdentifiers: [String] = []

    init(
        status: KeyboardPhotoAuthorization,
        candidates: [ScreenshotLibraryCandidate],
        exactCandidate: ScreenshotLibraryCandidate? = nil
    ) {
        authorizationStatus = status
        self.candidates = candidates
        self.exactCandidate = exactCandidate
    }

    func fetchRecentScreenshotCandidates(
        limit: Int,
        maximumPixelSize: CGFloat,
        completion: @escaping (Result<[ScreenshotLibraryCandidate], Error>) -> Void
    ) {
        fetchCount += 1
        completion(.success(Array(candidates.prefix(limit))))
    }

    func fetchScreenshotCandidate(
        assetIdentifier: String,
        maximumPixelSize _: CGFloat,
        completion: @escaping (
            Result<ScreenshotLibraryCandidate?, Error>
        ) -> Void
    ) {
        exactFetchIdentifiers.append(assetIdentifier)
        completion(
            .success(
                exactCandidate?.assetIdentifier == assetIdentifier
                    ? exactCandidate
                    : nil
            )
        )
    }
}
