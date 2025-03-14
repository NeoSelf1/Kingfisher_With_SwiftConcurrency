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

public final class ImageDownloader: @unchecked Sendable  {
    public static let `default` = ImageDownloader(name: "default")
    
    private let downloadTimeout: TimeInterval = 15.0
    private let name: String
    private let session: URLSession
    
    private let sessionDelegate: SessionDelegate
    private var activeTasks: [URL: DownloadTask] = [:]
    
    public init(
        name: String
    ) {
        self.name = name
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
        
        let imageData = try await downloadImageData(with: url)
        print("downloadImage \(imageData)")

        guard let image = UIImage(data: imageData) else {
            throw NeoImageError.responseError(reason: .invalidImageData)
        }
        
        // 다운로드 결과 캐싱
        try? await ImageCache.shared.store(imageData, forKey: cacheKey)
        NeoLogger.shared.debug("Image stored in cache with key: \(cacheKey)")
        
        activeTasks[url] = nil
        
        return ImageLoadingResult(
            image: image,
            url: url,
            originalData: imageData
        )
    }
    
    /// 특정 URL의 다운로드를 취소합니다.
    /// - Parameter url: 취소할 다운로드 URL
    public func cancelDownload(for url: URL) async {
        if let task = activeTasks[url] {
            await task.cancel()
            activeTasks[url] = nil
            
            NeoLogger.shared.debug("Download canceled for URL: \(url.absoluteString)")
        }
    }
    
    /// 모든 다운로드를 취소합니다.
    public func cancelAllDownloads() async {
        let urls = Array(activeTasks.keys)
        for url in urls {
            await cancelDownload(for: url)
        }
        NeoLogger.shared.debug("All downloads canceled")
    }
}

extension ImageDownloader {
    /// 이미지 데이터를 다운로드합니다.
    /// - Parameter url: 다운로드할 URL
    /// - Returns: 다운로드 작업과 데이터 튜플
    private func downloadImageData(with url: URL) async throws -> Data {
        // URL 요청 생성
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: downloadTimeout
        )
        
        // URL 유효성 검사
        guard let url = request.url, !url.absoluteString.isEmpty else {
            throw NeoImageError.requestError(reason: .invalidURL(request: request))
        }
        // 다운로드 컨텍스트 생성
        let downloadTask = await createDownloadTask(url: url, request: request)
        activeTasks[url] = downloadTask
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            Task {
                guard let sessionTask = await downloadTask.sessionTask else {
                    continuation.resume(throwing: NeoImageError.responseError(reason: .URLSessionError(description: "Session task is nil")))
                    return
                }
                
                if await sessionTask.isCompleted,
                   let taskResult = await sessionTask.taskResult {
                    print("sessionTask is Completed")
                    switch taskResult {
                    case .success(let (data, _)):
                        if data.isEmpty {
                            continuation.resume(throwing: NeoImageError.responseError(reason: .invalidImageData))
                        } else {
                            continuation.resume(returning: data)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                await sessionTask.onCallbackTaskDone.delegate(on: self) { (self, value) in
                    let (result, _) = value
                    print("onCallbackTaskDone is Delegated")
                    
                    switch result {
                    case .success(let (data, _)):
                        if data.isEmpty {
                            continuation.resume(throwing: NeoImageError.responseError(reason: .invalidImageData))
                        } else {
                            continuation.resume(returning: data)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// 다운로드 작업을 생성하거나 기존 작업을 재사용합니다.
    /// - Parameters:
    ///   - url: 다운로드할 URL
    ///   - request: URL 요청
    /// - Returns: 다운로드 작업
    private func createDownloadTask(url: URL, request: URLRequest) async -> DownloadTask {
        // 기존 작업이 있는지 확인
        if let existingTask = await sessionDelegate.task(for: url) {
            return await sessionDelegate.append(existingTask)
        } else {
            // 새 작업 생성
            let sessionDataTask = session.dataTask(with: request)
            return await sessionDelegate.add(sessionDataTask, url: url)
        }
    }
}
