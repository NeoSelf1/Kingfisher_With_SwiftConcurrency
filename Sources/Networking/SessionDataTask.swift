import Foundation

/// 다운로드 작업의 현재 상태를 나타내는 열거형
public enum SessionTaskState: Sendable {
    case ready
    case running
    case completed(Data, URLResponse?)
    case failed(Error)
    case cancelled
}

/// `ImageDownloader`에서 사용되는 세션 데이터 작업을 나타냅니다.
/// 기본적으로 `SessionDataTask`는 `URLSessionDataTask`를 래핑하고 다운로드 데이터를 관리합니다.
/// `SessionDataTask/CancelToken`을 사용하여 작업을 추적하고 취소를 관리합니다.
public actor SessionDataTask {
    public let task: URLSessionDataTask /// 내부적으로 사용되는 다운로드 작업
    
    private(set) var mutableData: Data /// 다운로드된 데이터를 저장하는 변수
    private(set) var state: SessionTaskState

    public let originalURL: URL?  /// 원본 URL
    
    /// `SessionDataTask`를 초기화합니다.
    init(task: URLSessionDataTask) {
        self.task = task
        self.mutableData = Data() // 데이터 저장을 위한 빈 `Data` 객체 초기화
        self.state = .ready
        self.originalURL = task.originalRequest?.url
        NeoLogger.shared.info("initialized")
    }
    
    /// 작업이 완료될 때 호출되는 메서드
    func didComplete(with result: Result<URLResponse?, Error>) {
        switch result {
        case .success(let response):
            state = .completed(mutableData, response)
        case .failure(let error):
            state = .failed(error)
        }
    }
    
    /// 데이터를 수신하고 저장합니다.
    func didReceiveData(_ data: Data) {
        mutableData.append(data) // 수신된 데이터를 기존 데이터에 추가
    }
    
    /// 작업을 시작합니다.
    func resume() {
        guard case .ready = state  else { return }
        state = .running
        task.resume()
    }
    
    /// 특정 토큰에 해당하는 작업을 취소합니다.
    func cancel() {
        guard case .running = state else { return }
        
        task.cancel()
        state = .cancelled
    }
    
    /// 작업 결과를 비동기적으로 기다립니다.
    public func result() async throws -> (Data, URLResponse?) {
        // 이미 완료된 경우
        switch state {
        case .completed(let data, let response):
            return (data, response)
        case .failed(let error):
            throw error
        case .cancelled:
            throw NeoImageError.requestError(reason: .taskCancelled(task: self, token: 0))
        case .ready, .running:
            // 작업이 아직 완료되지 않았다면 완료될 때까지 대기
            
            /// `withCheckedThrowingContinuation`
            /// completion handler를 사용하는 이전 스타일의 API를 현대적인 async/await 패턴으로 래핑(브릿징)할 때 사용하거나, 이벤트 기반 시스템에서 이벤트가 발생할때까지 기다려야 하는 경우에 사용됩니다.
            ///
            /// NeoImage 패키지에서는 더이상 completion handler 패턴을 사용하는 코드가 없습니다.
            /// 그럼에도 불구하고 사용하는 이유는 다운로드 작업의 상태를 주기적으로 확인하면서 완료될 때까지 기다리는 패턴을 구현하기 위해 사용된 것입니다.
            ///
            /// 비동기로 백그라운드 스레드에서 실행되더라도, 다운로드 완료까지 10ms마다 깨어나서 상태 확인을 위해 스레드를 지속적으로 점유하다보니 여전히
            /// 비효율적입니다. 이는 자연스레 CPU 시간을 소비합니다.
            ///
            // TODO: 때문에 추후, Combine을 사용해 현재코드에 대한 리팩토링이 필요합니다.
            return try await withCheckedThrowingContinuation { continuation in
                Task {
                    // 상태가 변경될 때까지 주기적으로 확인
                    while true {
                        switch state {
                        case .completed(let data, let response):
                            continuation.resume(returning: (data, response))
                            return
                        case .failed(let error):
                            continuation.resume(throwing: error)
                            return
                        case .cancelled:
                            continuation.resume(throwing: NeoImageError.requestError(reason: .taskCancelled(task: self, token: 0)))
                            return
                        case .ready, .running:
                            // 짧은 간격으로 대기 ***
                            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        }
                    }
                }
            }
        }
    }
}
