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

typealias DownloadResult = Result<ImageLoadingResult, NeoImageError>

public final class ImageDownloader: Sendable  {
    public static let `default` = ImageDownloader(name: "default")
    
    private let downloadTimeout: TimeInterval = 15.0
    private let name: String
    private let session: URLSession
    
    private let requestsUsePipelining: Bool
    private let sessionDelegate: SessionDelegate
    
    public init(
        name: String,
        requestsUsePipelining: Bool = true
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
    public func downloadImageData(with url: URL) async throws -> (DownloadTask, Data) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: downloadTimeout)
        request.httpShouldUsePipelining = requestsUsePipelining
        
        guard let url = request.url, !url.absoluteString.isEmpty else {
            throw NeoImageError.requestError(reason: .invalidURL(request: request))
        }
        
        return try await createDownloadTaskWithData(context: DownloadingContext(
            url: url,
            request: request)
        )
    }
}

extension ImageDownloader {
    private func createDownloadTaskWithData(context: DownloadingContext) async throws -> (DownloadTask, Data) {
        // 여러 요청이 동시에 실행될 경우를 위한 액터 또는 동기화 메커니즘 필요
        return try await withCheckedThrowingContinuation { continuation in
            // 기존 태스크 확인 (중복 다운로드 방지)
            if let existingTask = sessionDelegate.task(for: context.url) {
                existingTask.onTaskDone.delegate(on: self) { (_, values) in
                    let (result, callbacks) = values
                    let downloadResult: DownloadResult
                    
                    switch result {
                    case .success(let (data, _)):
                        if let image = UIImage(data: data) {
                            let imageResult = ImageLoadingResult(
                                image: image,
                                url: context.url,
                                originalData: data
                            )
                            
                            downloadResult = .success(imageResult)
                        } else {
                            downloadResult = .failure(NeoImageError.responseError(reason: .invalidImageData))
                        }
                    case .failure(let error):
                        downloadResult = .failure(error)
                    }
                    
                    // 모든 콜백 호출
                    for callbackItem in callbacks {
                        callbackItem.onCompleted?.call(downloadResult)
                    }
                }
                
                let downloadTask = DownloadTask()
                
                let onCompleted = Delegate<DownloadResult, Void>()
                
                onCompleted.delegate(on: self) { (self, result) in
                    switch result {
                    case .success(let imageResult):
                        continuation.resume(returning: (downloadTask, imageResult.originalData))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                let callback = SessionDataTask.TaskCallback(onCompleted: onCompleted)
                let task = sessionDelegate.append(existingTask, callback: callback)
                
                Task {
                    await downloadTask.linkToTask(task)
                }
            } else {
                let sessionDataTask = session.dataTask(with: context.request)
                let onCompleted = Delegate<DownloadResult, Void>()
                let callback = SessionDataTask.TaskCallback(onCompleted: onCompleted)
                
                let downloadTask = sessionDelegate.add(sessionDataTask, url: context.url, callback: callback)
                Task {
                   await downloadTask.sessionTask?.onTaskDone.delegate(on: self) { (_, values) in
                        let (result, callbacks) = values
                        
                        // 결과를 DownloadResult로 변환
                        let downloadResult: DownloadResult
                        switch result {
                        case .success(let (data, _)):
                            if let image = UIImage(data: data) {
                                let imageResult = ImageLoadingResult(
                                    image: image,
                                    url: context.url,
                                    originalData: data
                                )
                                downloadResult = .success(imageResult)
                            } else {
                                downloadResult = .failure(NeoImageError.responseError(reason: .invalidImageData))
                            }
                        case .failure(let error):
                            downloadResult = .failure(error)
                        }
                        
                        // 모든 콜백 호출
                        for callbackItem in callbacks {
                            callbackItem.onCompleted?.call(downloadResult)
                        }
                    }
                }
                
                onCompleted.delegate(on: self) { (self, result) in
                    switch result {
                    case .success(let imageResult):
                        continuation.resume(returning: (downloadTask, imageResult.originalData))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                sessionDataTask.resume()
            }
        }
    }
}

extension ImageDownloader {
    struct DownloadingContext {
        let url: URL
        let request: URLRequest
    }
}
