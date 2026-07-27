import Foundation
import Photos
import UIKit

enum KeyboardPhotoAuthorization: Equatable {
    case authorized
    case limited
    case denied
    case restricted
    case notDetermined
}

struct ScreenshotLibraryCandidate {
    let assetIdentifier: String
    let creationDate: Date
    let thumbnail: UIImage
}

/// Optional capability: a library that can tell us when its contents change.
/// Kept separate from `ScreenshotLibrary` so a test double can stay a plain
/// fetcher without pretending to observe anything.
protocol ScreenshotLibraryObserving: AnyObject {
    func startObservingChanges(_ onChange: @escaping () -> Void)
    func stopObservingChanges()
}

protocol ScreenshotLibrary: AnyObject {
    var authorizationStatus: KeyboardPhotoAuthorization { get }

    func fetchRecentScreenshotCandidates(
        limit: Int,
        maximumPixelSize: CGFloat,
        completion: @escaping (
            Result<[ScreenshotLibraryCandidate], Error>
        ) -> Void
    )

    func fetchScreenshotCandidate(
        assetIdentifier: String,
        maximumPixelSize: CGFloat,
        completion: @escaping (
            Result<ScreenshotLibraryCandidate?, Error>
        ) -> Void
    )
}

struct LatestScreenshot: Equatable {
    let assetIdentifier: String
    let creationDate: Date
    let thumbnail: UIImage

    static func == (
        lhs: LatestScreenshot,
        rhs: LatestScreenshot
    ) -> Bool {
        lhs.assetIdentifier == rhs.assetIdentifier &&
            lhs.creationDate == rhs.creationDate
    }
}

enum LatestScreenshotError: Error, Equatable {
    case capabilityRequired
    case consentRequired
    case permissionRequired(KeyboardPhotoAuthorization)
    case noRecentScreenshot
    case photoLibraryFailed
}

final class LatestScreenshotProvider {
    private let library: ScreenshotLibrary
    private let now: () -> Date
    private let recencyWindow: TimeInterval

    init(
        library: ScreenshotLibrary = PhotoKitScreenshotLibrary(),
        now: @escaping () -> Date = Date.init,
        recencyWindow: TimeInterval =
            KeyboardSharedConfig.screenshotRecencyWindow
    ) {
        self.library = library
        self.now = now
        self.recencyWindow = recencyWindow
    }

    func startObservingLibraryChanges(_ onChange: @escaping () -> Void) {
        (library as? ScreenshotLibraryObserving)?
            .startObservingChanges(onChange)
    }

    func stopObservingLibraryChanges() {
        (library as? ScreenshotLibraryObserving)?.stopObservingChanges()
    }

    func fetchLatest(
        capability: KeyboardAssistCapabilityReceipt?,
        ownerUserId: String,
        userAuthorizedDetection: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    ) {
        let currentTime = now()
        guard capability?.isUsable(
            ownerUserId: ownerUserId,
            now: currentTime
        ) == true else {
            completion(.failure(.capabilityRequired))
            return
        }
        guard userAuthorizedDetection else {
            completion(.failure(.consentRequired))
            return
        }
        let status = library.authorizationStatus
        guard status == .authorized || status == .limited else {
            // The extension never requests permission. The containing app owns
            // the system prompt and the associated privacy disclosure.
            completion(.failure(.permissionRequired(status)))
            return
        }

        library.fetchRecentScreenshotCandidates(
            limit: 8,
            maximumPixelSize: 960
        ) { [now, recencyWindow] result in
            switch result {
            case .failure:
                completion(.failure(.photoLibraryFailed))
            case .success(let candidates):
                let reference = now()
                let earliest = reference.addingTimeInterval(-recencyWindow)
                let latestAllowed = reference.addingTimeInterval(
                    KeyboardSharedConfig.futureClockSkewAllowance
                )
                let recentCandidates = candidates.filter { candidate in
                    candidate.creationDate >= earliest &&
                        candidate.creationDate <= latestAllowed
                }
                guard let latest = recentCandidates.max(
                    by: { lhs, rhs in
                        lhs.creationDate < rhs.creationDate
                    }
                ) else {
                    completion(.failure(.noRecentScreenshot))
                    return
                }
                completion(
                    .success(
                        LatestScreenshot(
                            assetIdentifier: latest.assetIdentifier,
                            creationDate: latest.creationDate,
                            thumbnail: latest.thumbnail
                        )
                    )
                )
            }
        }
    }

    func fetch(
        assetIdentifier: String,
        capability: KeyboardAssistCapabilityReceipt?,
        ownerUserId: String,
        userAuthorizedDetection: Bool,
        completion: @escaping (
            Result<LatestScreenshot, LatestScreenshotError>
        ) -> Void
    ) {
        let currentTime = now()
        guard capability?.isUsable(
            ownerUserId: ownerUserId,
            now: currentTime
        ) == true else {
            completion(.failure(.capabilityRequired))
            return
        }
        guard userAuthorizedDetection else {
            completion(.failure(.consentRequired))
            return
        }
        let status = library.authorizationStatus
        guard status == .authorized || status == .limited else {
            completion(.failure(.permissionRequired(status)))
            return
        }

        library.fetchScreenshotCandidate(
            assetIdentifier: assetIdentifier,
            maximumPixelSize: 960
        ) { result in
            switch result {
            case .failure:
                completion(.failure(.photoLibraryFailed))
            case .success(nil):
                completion(.failure(.noRecentScreenshot))
            case .success(let candidate?):
                completion(
                    .success(
                        LatestScreenshot(
                            assetIdentifier: candidate.assetIdentifier,
                            creationDate: candidate.creationDate,
                            thumbnail: candidate.thumbnail
                        )
                    )
                )
            }
        }
    }
}

private final class PhotoLibraryChangeRelay:
    NSObject,
    PHPhotoLibraryChangeObserver
{
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // PhotoKit delivers on a private queue; everything downstream touches
        // keyboard state, so hop before doing anything at all.
        DispatchQueue.main.async { [onChange] in
            onChange()
        }
    }
}

final class PhotoKitScreenshotLibrary:
    ScreenshotLibrary,
    ScreenshotLibraryObserving
{
    private let imageManager: PHImageManager
    private var changeRelay: PhotoLibraryChangeRelay?

    init(imageManager: PHImageManager = .default()) {
        self.imageManager = imageManager
    }

    deinit {
        stopObservingChanges()
    }

    func startObservingChanges(_ onChange: @escaping () -> Void) {
        guard changeRelay == nil else { return }
        let status = authorizationStatus
        guard status == .authorized || status == .limited else { return }
        let relay = PhotoLibraryChangeRelay(onChange: onChange)
        changeRelay = relay
        PHPhotoLibrary.shared().register(relay)
    }

    func stopObservingChanges() {
        guard let relay = changeRelay else { return }
        changeRelay = nil
        PHPhotoLibrary.shared().unregisterChangeObserver(relay)
    }

    var authorizationStatus: KeyboardPhotoAuthorization {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        if #available(iOS 14, *), status == .limited {
            return .limited
        }
        switch status {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        default:
            return .restricted
        }
    }

    func fetchRecentScreenshotCandidates(
        limit: Int,
        maximumPixelSize: CGFloat,
        completion: @escaping (
            Result<[ScreenshotLibraryCandidate], Error>
        ) -> Void
    ) {
        let options = PHFetchOptions()
        options.fetchLimit = max(1, min(limit, 16))
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false),
        ]
        options.predicate = NSPredicate(
            format: "(mediaSubtype & %lld) != 0",
            Int64(PHAssetMediaSubtype.photoScreenshot.rawValue)
        )
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var selected: PHAsset?
        assets.enumerateObjects { asset, _, stop in
            if asset.mediaSubtypes.contains(.photoScreenshot),
               asset.creationDate != nil
            {
                selected = asset
                stop.pointee = true
            }
        }
        guard let asset = selected else {
            completion(.success([]))
            return
        }

        requestCandidate(
            for: asset,
            maximumPixelSize: maximumPixelSize
        ) { result in
            completion(result.map { candidate in
                candidate.map { [$0] } ?? []
            })
        }
    }

    func fetchScreenshotCandidate(
        assetIdentifier: String,
        maximumPixelSize: CGFloat,
        completion: @escaping (
            Result<ScreenshotLibraryCandidate?, Error>
        ) -> Void
    ) {
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: [assetIdentifier],
            options: nil
        )
        guard let asset = assets.firstObject,
              asset.mediaType == .image,
              asset.mediaSubtypes.contains(.photoScreenshot),
              asset.creationDate != nil
        else {
            completion(.success(nil))
            return
        }
        requestCandidate(
            for: asset,
            maximumPixelSize: maximumPixelSize,
            completion: completion
        )
    }

    private func requestCandidate(
        for asset: PHAsset,
        maximumPixelSize: CGFloat,
        completion: @escaping (
            Result<ScreenshotLibraryCandidate?, Error>
        ) -> Void
    ) {
        let requestOptions = PHImageRequestOptions()
        requestOptions.isNetworkAccessAllowed = false
        // The pending hash is recomputed across separate PhotoKit reads.
        // Exact resizing keeps the raster dimensions deterministic for the
        // same asset, target size, content mode, and orientation.
        requestOptions.resizeMode = .exact
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isSynchronous = false

        imageManager.requestImage(
            for: asset,
            targetSize: CGSize(
                width: maximumPixelSize,
                height: maximumPixelSize * 2.2
            ),
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, info in
            let cancelled = info?[PHImageCancelledKey] as? Bool == true
            let degraded = info?[PHImageResultIsDegradedKey] as? Bool == true
            let error = info?[PHImageErrorKey] as? Error
            guard !degraded else { return }
            let result: Result<ScreenshotLibraryCandidate?, Error>
            if !cancelled,
               error == nil,
               let image,
               let creationDate = asset.creationDate
            {
                result = .success(
                    ScreenshotLibraryCandidate(
                        assetIdentifier: asset.localIdentifier,
                        creationDate: creationDate,
                        thumbnail: image
                    )
                )
            } else if let error {
                result = .failure(error)
            } else {
                result = .success(nil)
            }
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
