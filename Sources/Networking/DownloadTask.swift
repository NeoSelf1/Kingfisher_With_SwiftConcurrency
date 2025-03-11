import Foundation

public final actor DownloadTask: Sendable {
    private(set) var sessionTask: SessionDataTask?
    private(set) var cancelToken: SessionDataTask.CancelToken?
    
    init(
        sessionTask: SessionDataTask? = nil,
        cancelToken: SessionDataTask.CancelToken? = nil
    ) {
        self.sessionTask = sessionTask
        self.cancelToken = cancelToken
        
        NeoLogger.shared.debug("initialized")
    }
    
    /// Cancel this single download task if it is running.
    public func cancel() {
        guard let sessionTask, let cancelToken else { return }
        sessionTask.cancel(token: cancelToken)
    }
    
    // DownloadTask가 제대로 초기화되었는지 확인하는 메서드
    public var isInitialized: Bool {
        sessionTask != nil && cancelToken != nil
    }
    
    // 다른 DownloadTask의 sessionTask와 cancelToken을 이 DownloadTask에 연결
    func linkToTask(_ task: DownloadTask) {
        Task {
            guard await task.isInitialized else { return }
            await sessionTask = task.sessionTask
            await cancelToken = task.cancelToken
        }
    }
}
