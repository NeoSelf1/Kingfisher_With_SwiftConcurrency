import Foundation

/// 프로젝트에 단일로 존재하며, 이미지 다운로드 URL과 SessionDataTask를 관리합니다.
@objc(NeoImageDelegate)
public actor SessionDelegate: NSObject{
    private var tasks: [URL: SessionDataTask] = [:]

    var authenticationChallengeHandler: ((URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?))?

    /// 새 다운로드 작업 생성 기존 append랑 add 모두 포괄
    func createTask(with url: URL, using session: URLSession) async -> DownloadTask {
        if let existingTask = task(for: url) {
            return DownloadTask(sessionTask: existingTask)
        } else {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15.0)
            let dataTask = session.dataTask(with: request)
            
            /// SessionDelegate가 관리하는 SessionDataTask 딕셔너리에 항목 갱신
            let sessionTask = SessionDataTask(task: dataTask)
            tasks[url] = sessionTask
            
            /// URLSessionDataTask 작업 시작 -> URLSessionDataDelegate 프로토콜 메서드 호출 시작
            await sessionTask.resume()
            
            return DownloadTask(sessionTask: sessionTask)
        }
    }

    /// URL에 해당하는 SessionDataTask 반환
    func task(for url: URL) -> SessionDataTask? {
        return tasks[url]
    }
    
    /// 작업 제거
    func removeTask(_ task: SessionDataTask) {
        guard let url = task.originalURL else { return }
        tasks[url] = nil
    }
}

// MARK: - URLSessionDataDelegate
// 각 작업의 상태(ready, running, completed, failed, cancelled)를 세밀하게 추적하기 위해 Delegate 메서드 사용이 필요합니다.
extension SessionDelegate: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse
    ) async -> URLSession.ResponseDisposition {
        guard response is HTTPURLResponse else {
            if let task = getSessionTask(for: dataTask) { // 유효하지 않은 응답 처리
                let error = NeoImageError.responseError(reason: .URLSessionError(description: "invalid http Response"))
                
                await task.didComplete(with: .failure(error))
                removeTask(task)
            }
            
            return .cancel
        }
        
        return .allow
    }
    
    nonisolated public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        Task {
            if let task = await getSessionTask(for: dataTask) {
                await task.didReceiveData(data)
            }
        }
    }
    
    /// Actor-isolated instance method 'urlSession(_:task:didCompleteWithError:)' cannot be @objc
    /// Swift의 actor와 Objective-C 런타입 간 호환성 문제에 발생하는 컴파일 에러입니다.
    /// URLSessionDelegate 메서드들은 모두 Objective-C 런타임을 통해 호출되기에 프로토콜을 구현하는 메서드는 @objc로 노출되어야 합니다.
    /// SessionDelegate 클래스는 actor로 선언되어있기에 actor-isolated입니다. 이는 비동기적으로 실행되어야 합니다.
    
    /// 하지만 Objective-C는 Swift의 async/await의 actor 모델을 이해하지 못하기에 에러가 발생합니다.
    ///
    nonisolated public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task {
            /// SessionDataTask가 actor로 마이그레이션 되면서, 내부 didComplete 메서드는 비동기 컨텍스트에서 실행되어야 합니다.
            /// Actor-isolated instance method 'urlSession(_:task:didCompleteWithError:)' cannot be @objc
            ///
            if let sessionTask = await getSessionTask(for: task) {
                if let error = error {
                    await sessionTask.didComplete(with: .failure(error))
                } else {
                    await sessionTask.didComplete(with: .success(task.response))
                }
                await removeTask(sessionTask)
            }
        }
    }
    
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if let handler = authenticationChallengeHandler {
            return await handler(challenge)
        }
        
        return (.performDefaultHandling, nil)
    }
    
    // MARK: - 헬퍼 메서드
    
    /// URLSessionTask에 대응하는 SessionDataTask 찾기
    private func getSessionTask(for task: URLSessionTask) -> SessionDataTask? {
        guard let url = task.originalRequest?.url else { return nil }
        
        guard let sessionTask = tasks[url] else { return nil }
        
        // MARK: URLSesssionTask 클래스의 taskIdentifier로 기존 cancelToken 대체
        guard sessionTask.task.taskIdentifier == task.taskIdentifier else { return nil }
        
        return sessionTask
    }
}
