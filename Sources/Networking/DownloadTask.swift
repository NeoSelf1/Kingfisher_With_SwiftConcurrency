import Foundation

public final actor DownloadTask: Sendable {
    private(set) var sessionTask: SessionDataTask?
    
    init(
        sessionTask: SessionDataTask? = nil
    ) {
        self.sessionTask = sessionTask
    }
    
    /// 이 다운로드 작업이 실행 중인 경우 취소합니다.
    public func cancel() async {
        await sessionTask?.cancel()
    }
    
    func setSessionTask(_ task: SessionDataTask) async {
        self.sessionTask = task
    }
    
    /// 다른 SessionDataTask에 링크
    func linkToSessionTask(_ task: SessionDataTask) async {
        self.sessionTask = task
    }
    
    /// 작업 결과를 기다림
    public func result() async throws -> (Data, URLResponse?) {
        /// 본래 linkToSessionTask를 통해 sessionTask가 연결되어있어야 함 -> 이거 관련해서 체크
        guard let sessionTask = sessionTask else {
            throw NeoImageError.requestError(reason: .emptyRequest)
        }
        
        return try await sessionTask.result()
    }
}
