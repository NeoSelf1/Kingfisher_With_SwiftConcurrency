import Foundation

public final actor DownloadTask: Sendable {
    private(set) var sessionTask: SessionDataTask
    
    init(
        sessionTask: SessionDataTask
    ) {
        self.sessionTask = sessionTask
    }
    
    /// 이 다운로드 작업이 실행 중인 경우 취소합니다.
    public func cancel() async {
        await sessionTask.cancel()
    }
}
