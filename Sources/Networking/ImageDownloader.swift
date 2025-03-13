import Foundation
import UIKit

public struct ImageLoadingResult: Sendable {
    public let image: UIImage
    public let url: URL?
    public let originalData: Data

    public init(image: UIImage, url: URL? = nil, originalData: Data) {
        self.image = image
        self.url = url
        self.originalData = originalData
    }
}

public final class ImageDownloader: Sendable  {
    public static let `default` = ImageDownloader(name: "default")
    
    private let downloadTimeout: TimeInterval = 15.0
    private let name: String
    private let session: URLSession
    
    private let requestsUsePipelining: Bool
    private let sessionDelegate: SessionDelegate
    
    public init(
        name: String,
        requestsUsePipelining: Bool = false
    ) {
        self.name = name
        self.requestsUsePipelining = requestsUsePipelining
        self.sessionDelegate = SessionDelegate()
        
        self.session = URLSession(
            configuration: URLSessionConfiguration.ephemeral,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
    }
    
    deinit { session.invalidateAndCancel() }
    
    @discardableResult
    public func downloadImage(with url: URL, options: NeoImageOptions? = nil) async throws -> ImageLoadingResult {
        let cacheKey = url.absoluteString
        
        if let cachedData = try? await ImageCache.shared.retrieveImage(forKey: cacheKey),
           let cachedImage = UIImage(data: cachedData) {
            return ImageLoadingResult(
                image: cachedImage,
                url: url,
                originalData: cachedData
            )
        }
        
        let (_, imageData) = try await downloadImageData(with: url)
        
        guard let image = UIImage(data: imageData) else {
            throw NeoImageError.responseError(reason: .invalidImageData)
        }
        
        // 다운로드 결과 캐싱
        try? await ImageCache.shared.store(imageData, forKey: cacheKey)
        
        return ImageLoadingResult(
            image: image,
            url: url,
            originalData: imageData
        )
    }
}

extension ImageDownloader {
    private func downloadImageData(with url: URL) async throws -> (DownloadTask, Data) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: downloadTimeout)
        request.httpShouldUsePipelining = requestsUsePipelining
        
        guard let url = request.url, !url.absoluteString.isEmpty else {
            throw NeoImageError.requestError(reason: .invalidURL(request: request))
        }
        
        // SessionDataTask link 완료된 DownloadTask 생성
        let downloadTask = await sessionDelegate.createTask(with: url, using: session)
        
        do {
            // TODO: Kingfisher에서는 콜백패턴을 통해 선행 다운로드 작업이 진행중일때 스레드를 비울 수 있었으나, await 패턴을 도입하게 되면서, 백그라운드 스레드를 지속적으로 점유하고 있습니다. 이에 대한 대안을 모색해야합니다.
            let (data, _) = try await downloadTask.sessionTask.result()
            
            guard UIImage(data: data) != nil else { // 이미지 유효성 검사
                throw NeoImageError.responseError(reason: .invalidImageData)
            }
            
            return (downloadTask, data)
        } catch {
            if let neoError = error as? NeoImageError {
                throw neoError
            } else {
                throw NeoImageError.responseError(reason: .URLSessionError(description: error.localizedDescription))
            }
        }
    }
}
